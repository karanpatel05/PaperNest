import AVFoundation
import NaturalLanguage
import Observation
import PaperNestCore
import PaperNestRender
import SwiftUI

// MARK: - Speech

/// Something a speech output reports about one utterance.
enum SpeechEvent: Equatable, Sendable {
    /// It is saying this range (UTF-16 units) of the text it was given.
    case speaking(NSRange)
    /// It said all of it.
    case finished
    /// Something else took the audio — a call, an alarm. Reading pauses.
    case interrupted
}

/// Says text out loud. `SystemSpeech` is the real one; tests use a fake.
@MainActor protocol SpeechOutput: AnyObject {
    /// Called on the main actor, in the order things happened, with the token
    /// `speak` returned for the utterance each event is about.
    var onEvent: (@MainActor (Int, SpeechEvent) -> Void)? { get set }
    /// Starts saying `text`, stopping anything already being said.
    /// `speed` multiplies the system's default rate.
    func speak(_ text: String, language: String?, speed: Float) -> Int
    func pause()
    func resume()
    /// Stops what is being said. The audio stays this app's, so the next
    /// utterance — the next page, the same page at another speed — starts
    /// without the session going off and on in between.
    func stop()
    /// Stops, and gives the audio back to whatever was playing before.
    func release()
}

/// The system's speech synthesizer.
///
/// The synthesizer is held, not made per sentence: one made and dropped in a
/// function goes silent the moment it is released. But one that was **cut
/// off** mid-utterance is not asked to speak again: it is let go and a fresh
/// one takes the next utterance. On iOS 27.1 an utterance handed to a
/// synthesizer straight after `stopSpeaking(at: .immediate)` was sometimes
/// never said — measured in the speed-change UI test, which failed two runs
/// in three that way on the iPhone Simulator and never on iPadOS 26.5.
///
/// Its delegate is called on a queue of its own; every call is passed to the
/// main queue, which keeps them in order, rather than to a task each, which
/// would not.
@MainActor final class SystemSpeech: SpeechOutput {
    var onEvent: (@MainActor (Int, SpeechEvent) -> Void)?

    /// Made on first use: a document that never reads aloud never makes one,
    /// and a view rebuilt many times does not make many.
    private var made: AVSpeechSynthesizer?
    private var synthesizer: AVSpeechSynthesizer {
        if let made { return made }
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = relay
        made = synthesizer
        return synthesizer
    }
    private let relay = Relay()
    private var tokens: [ObjectIdentifier: Int] = [:]
    private var nextToken = 1
    private var current: Int?
    #if os(iOS)
    private var interruptions: NSObjectProtocol?
    private var holdsAudio = false
    /// Setting up and letting go of the audio session can block, and the
    /// system warns against doing it on the main thread. A serial queue keeps
    /// the two in the order they were asked for.
    private static let audio = DispatchQueue(label: "PaperNest.ReadAloud.audio")
    #endif

    init() {
        relay.deliver = { [weak self] utterance, event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(utterance, event) }
            }
        }
    }

    func speak(_ text: String, language: String?, speed: Float) -> Int {
        stop()
        #if os(iOS)
        holdAudio()
        #endif
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: language)
        let rate = AVSpeechUtteranceDefaultSpeechRate * speed
        utterance.rate = min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
        utterance.volume = Self.volume
        let token = nextToken
        nextToken += 1
        tokens[ObjectIdentifier(utterance)] = token
        current = token
        synthesizer.speak(utterance)
        return token
    }

    func pause() { made?.pauseSpeaking(at: .word) }
    func resume() { made?.continueSpeaking() }

    func stop() {
        current = nil
        tokens.removeAll()
        if let made, made.isSpeaking || made.isPaused {
            made.stopSpeaking(at: .immediate)
            // Cut off: the next utterance goes to a fresh synthesizer.
            self.made = nil
        }
    }

    func release() {
        stop()
        #if os(iOS)
        letGoOfAudio()
        #endif
    }

    #if os(iOS)
    /// Spoken audio: heard with the ring switch on silent, and other audio
    /// ducks under it rather than stopping. A call or an alarm pauses reading;
    /// that is watched only while the audio is held, so a document that never
    /// reads aloud leaves nothing behind.
    private func holdAudio() {
        guard !holdsAudio else { return }
        holdsAudio = true
        Self.audio.async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try? session.setActive(true)
        }
        interruptions = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            guard began else { return }
            MainActor.assumeIsolated {
                guard let self, let current = self.current else { return }
                self.onEvent?(current, .interrupted)
            }
        }
    }

    private func letGoOfAudio() {
        guard holdsAudio else { return }
        holdsAudio = false
        if let interruptions { NotificationCenter.default.removeObserver(interruptions) }
        interruptions = nil
        Self.audio.async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    #endif

    private func handle(_ utterance: ObjectIdentifier, _ event: SpeechEvent) {
        guard let token = tokens[utterance] else { return }
        if event == .finished { tokens[utterance] = nil; if current == token { current = nil } }
        onEvent?(token, event)
    }

    /// A voice for `language`: the reader's own variant of it when they use
    /// one (Canadian French for someone set to fr-CA), any installed one
    /// otherwise, and the system's default when there is none.
    static func voice(for language: String?) -> AVSpeechSynthesisVoice? {
        guard let language else { return nil }
        if let preferred = Locale.preferredLanguages.first(where: { $0.hasPrefix(language + "-") || $0 == language }),
           let voice = AVSpeechSynthesisVoice(language: preferred) {
            return voice
        }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(language + "-") }
    }

    /// Full volume, except in a development build told otherwise: UI tests
    /// run with `-PaperNestDebugSpeechVolume 0` so they read the page without
    /// talking through the Mac's speakers.
    static var volume: Float {
        #if DEBUG
        if let value = UserDefaults.standard.object(forKey: "PaperNestDebugSpeechVolume") as? NSNumber {
            return min(max(value.floatValue, 0), 1)
        }
        #endif
        return 1
    }

    /// The synthesizer's delegate. Not isolated: the synthesizer calls it on a
    /// queue of its own.
    private final class Relay: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        var deliver: (@Sendable (ObjectIdentifier, SpeechEvent) -> Void)?

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                               utterance: AVSpeechUtterance) {
            deliver?(ObjectIdentifier(utterance), .speaking(characterRange))
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            deliver?(ObjectIdentifier(utterance), .finished)
        }
    }
}

// MARK: - Reading a document aloud

/// Reading the open document aloud, from the page being read to the end,
/// lighting each word as it is said.
///
/// It turns the page itself when it reaches the next one with words on it;
/// pages without (a scan nobody has recognised) are passed over. If the reader
/// turns the page while it is talking, it starts again there. Only one
/// document talks at a time: starting another stops this one.
@MainActor @Observable
final class ReadAloud {
    enum State: Equatable {
        case idle
        /// Reading the next page's words.
        case preparing
        case speaking
        case paused
        /// Nothing from where it started to the end has any words to say.
        case noText
    }

    /// How fast, as a multiple of the system's own rate. The button cycles
    /// through them in this order.
    enum Speed: CaseIterable, Equatable {
        case normal, faster, fastest, slower

        var multiplier: Float {
            switch self {
            case .normal: 1
            case .faster: 1.25
            case .fastest: 1.5
            case .slower: 0.75
            }
        }

        /// What the button shows. Numbers and a sign, the same in every language.
        var label: String {
            switch self {
            case .normal: "1×"
            case .faster: "1.25×"
            case .fastest: "1.5×"
            case .slower: "0.75×"
            }
        }

        var next: Speed {
            let all = Self.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    /// The document being read, as read aloud needs it.
    struct Source {
        /// The document's pages, in order, as they are now.
        var pages: @MainActor () -> [PageID]
        /// A page's words, or nil when they cannot be read.
        var text: @MainActor (PageID) async -> PageTextLayout?
        /// Shows the reader `PageID`.
        var turn: @MainActor (PageID) -> Void
    }

    /// The scroll anchor the first box of the word being said carries.
    static let anchorID = "read-aloud-current"

    private(set) var state = State.idle
    var isActive: Bool { state != .idle }
    /// The page being read.
    private(set) var pageID: PageID?
    /// Where the word being said is on `pageID`: one box per line.
    private(set) var boxes: [NormalizedRect] = []
    /// The word being said, for VoiceOver and for tests.
    private(set) var word = ""
    private(set) var speed = Speed.normal
    /// Goes up when the word being said moves to another line, so the page
    /// can keep it in view.
    private(set) var lineRequest = 0
    /// The `lineRequest` whose word is laid out on screen. Written by the
    /// highlight, read by the page viewer.
    var shownLine = 0

    private let output: SpeechOutput
    private var source: Source?
    private var script: ReadAloudScript?
    private var language: String?
    private var token: Int?
    /// Where in `script.text` the utterance being said started.
    private var offset = 0
    /// The range of `script.text` last reported.
    private var spoken = NSRange(location: 0, length: 0)
    /// Whether anything has been said since `start`.
    private var hasSpoken = false
    /// The speed changed while paused: say the current word again at the new
    /// speed on resume.
    private var restartOnResume = false
    private var loading: Task<Void, Never>?
    private var generation = 0

    /// The one that is talking, so starting another can stop it.
    private static weak var talking: ReadAloud?

    init(output: SpeechOutput? = nil) {
        self.output = output ?? SystemSpeech()
        self.output.onEvent = { [weak self] token, event in self?.handle(token, event) }
    }

    /// Starts reading at `pageID` (the first page when nil).
    func start(from pageID: PageID?, source: Source) {
        if let other = Self.talking, other !== self { other.stop() }
        Self.talking = self
        self.source = source
        hasSpoken = false
        guard let first = pageID ?? source.pages().first else { state = .noText; return }
        read(first, turning: false)
    }

    func pause() {
        guard state == .speaking else { return }
        output.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        if script == nil, let pageID {
            // The reader turned the page while paused: start there.
            read(pageID, turning: false)
        } else if restartOnResume {
            restartOnResume = false
            sayFromCurrentWord()
        } else {
            output.resume()
            state = .speaking
        }
    }

    func stop() {
        generation += 1
        loading?.cancel()
        loading = nil
        token = nil
        output.release()
        state = .idle
        pageID = nil
        script = nil
        boxes = []
        word = ""
        restartOnResume = false
        source = nil
        if Self.talking === self { Self.talking = nil }
    }

    /// The next speed. Takes effect at once, from the word being said.
    func cycleSpeed() {
        speed = speed.next
        switch state {
        case .speaking: sayFromCurrentWord()
        case .paused: restartOnResume = true
        default: break
        }
    }

    /// The page shown changed. A turn this made itself is to the page it is
    /// already reading, so it changes nothing; any other is the reader turning
    /// the page, and reading follows them.
    func pageChanged(to id: PageID?) {
        guard let id, isActive, id != pageID else { return }
        switch state {
        case .paused:
            // Wait for Resume, then read from here.
            generation += 1
            token = nil
            output.stop()
            pageID = id
            script = nil
            boxes = []
            word = ""
        case .speaking, .preparing, .noText:
            hasSpoken = false
            read(id, turning: false)
        case .idle:
            break
        }
    }

    /// For tests: waits until the page being prepared has been read.
    func settle() async {
        while let loading { await loading.value; if self.loading == loading { break } }
    }

    // MARK: - Internals

    private func read(_ id: PageID, turning: Bool) {
        generation += 1
        let generation = generation
        token = nil
        output.stop()
        state = .preparing
        pageID = id
        script = nil
        boxes = []
        word = ""
        loading?.cancel()
        loading = Task { [weak self] in
            guard let self, let source = self.source else { return }
            let layout = await source.text(id)
            guard generation == self.generation, !Task.isCancelled else { return }
            let script = ReadAloudScript(layout ?? .empty)
            if script.isEmpty {
                self.advance(after: id)
                return
            }
            // `pageID` is already this page, so the selection change the
            // turn causes is not taken for the reader turning it.
            if turning { source.turn(id) }
            self.script = script
            self.language = Self.language(of: script.text)
            self.offset = 0
            self.spoken = NSRange(location: 0, length: 0)
            self.say(from: 0)
        }
    }

    private func say(from start: Int) {
        guard let script else { return }
        offset = start
        token = output.speak(script.suffix(from: start), language: language, speed: speed.multiplier)
        state = .speaking
    }

    private func sayFromCurrentWord() {
        guard let script else { return }
        token = nil
        output.stop()
        say(from: script.wordStart(atOrBefore: spoken.location))
    }

    private func advance(after id: PageID) {
        guard let source else { return }
        let pages = source.pages()
        guard let index = pages.firstIndex(of: id), index + 1 < pages.count else {
            finish()
            return
        }
        read(pages[index + 1], turning: true)
    }

    private func finish() {
        if hasSpoken {
            stop()
        } else {
            generation += 1
            token = nil
            output.release()
            state = .noText
            boxes = []
            word = ""
        }
    }

    private func handle(_ token: Int, _ event: SpeechEvent) {
        // Anything about an utterance that was stopped or replaced is old news.
        guard token == self.token, let script else { return }
        switch event {
        case .speaking(let range):
            let shifted = NSRange(location: range.location + offset, length: range.length)
            spoken = shifted
            word = script.words(for: shifted)
            let lit = script.boxes(for: shifted)
            // A word with no place on the page — one a scan's recognition did
            // not box — leaves the light where it was rather than putting it
            // out mid-sentence.
            guard let first = lit.first else { break }
            if abs(first.y - (boxes.first?.y ?? -1)) > first.height / 2 { lineRequest += 1 }
            boxes = lit
        case .finished:
            self.token = nil
            hasSpoken = true
            if let pageID { advance(after: pageID) }
        case .interrupted:
            pause()
        }
    }

    /// The language `text` is in, as far as it can be told: a BCP 47 code
    /// such as "fr", or nil when nothing is sure enough to be worth a voice
    /// of its own.
    nonisolated static func language(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2_000)))
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= 0.6 else { return nil }
        return language.rawValue
    }
}

extension ReadAloud {
    /// Starts reading `model` from the page being read.
    func start(reading model: DocumentModel) {
        start(from: model.selectedPageID ?? model.pages.first?.id, source: Source(
            pages: { model.pages.map(\.id) },
            text: { id in
                guard let page = model.pages.first(where: { $0.id == id }),
                      let renderer = model.session.environment?.renderer else { return nil }
                return try? await renderer.textLayout(for: page)
            },
            turn: { id in model.selectedPageID = id }))
    }

    /// Read Aloud when nothing is being read; Stop Reading when something is.
    func toggle(reading model: DocumentModel) {
        if isActive { stop() } else { start(reading: model) }
    }
}

// MARK: - Plumbing

struct ReadAloudKey: FocusedValueKey {
    typealias Value = ReadAloud
}

extension FocusedValues {
    /// The focused document's read aloud, for the Page menu.
    var readAloud: ReadAloud? {
        get { self[ReadAloudKey.self] }
        set { self[ReadAloudKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// The open document's read aloud, for the highlight over its pages.
    @Entry var readAloud: ReadAloud?
}

// MARK: - On screen

/// The word being said, lit on its page. It takes no touches.
struct ReadAloudHighlight: View {
    let page: Page
    /// Source space to this view's space, as every other layer over the page has.
    let sourceToView: CGAffineTransform

    @Environment(\.readAloud) private var readAloud
    @Environment(\.pageNightMode) private var isNight

    var body: some View {
        Group {
            if let readAloud, readAloud.pageID == page.id, !readAloud.boxes.isEmpty {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(readAloud.boxes.enumerated()), id: \.offset) { index, box in
                        let rect = box.denormalized(in: page.sourceSize).applying(sourceToView)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            // Find's colour for the hit you are on, night or day.
                            .fill(FindHighlightsOverlay.fill(isCurrent: true, isNight: isNight))
                            .frame(width: max(rect.width, 2), height: max(rect.height, 2))
                            .id(index == 0 ? AnyHashable(ReadAloud.anchorID) : AnyHashable("read-aloud-\(index)"))
                            .padding(.leading, max(rect.minX, 0))
                            .padding(.top, max(rect.minY, 0))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("read-aloud-word")
                .accessibilityValue(readAloud.word)
                .onChange(of: readAloud.lineRequest, initial: true) { _, request in
                    // Laid out now: the viewer can scroll to it.
                    readAloud.shownLine = request
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// The bar under the toolbar while a document is being read aloud: where it
/// is, Pause or Resume, how fast, and Stop.
struct ReadAloudBar: View {
    let readAloud: ReadAloud
    let model: DocumentModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text(status)
                .font(.app(.subheadline))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(readAloud.state == .noText ? "read-aloud-message" : "read-aloud-status")
            if readAloud.state != .noText {
                Button { readAloud.cycleSpeed() } label: {
                    Text(verbatim: readAloud.speed.label)
                        .font(.app(.subheadline).monospacedDigit().weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.readAloudSpeed)
                .accessibilityValue(Text(verbatim: readAloud.speed.label))
                .accessibilityIdentifier("read-aloud-speed")
                Button {
                    if readAloud.state == .paused { readAloud.resume() } else { readAloud.pause() }
                } label: {
                    Image(systemName: readAloud.state == .paused ? "play.fill" : "pause.fill")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(readAloud.state == .preparing)
                .accessibilityLabel(readAloud.state == .paused ? L10n.readAloudResume : L10n.readAloudPause)
                .accessibilityValue(Text(verbatim: readAloud.state == .paused ? "paused" : "speaking"))
                .accessibilityIdentifier("read-aloud-pause")
            }
            Button { readAloud.stop() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.app(.title3))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.readAloudStop)
            .accessibilityIdentifier("read-aloud-stop")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Theme.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("read-aloud-bar")
    }

    private var status: String {
        if readAloud.state == .noText { return L10n.readAloudNoText }
        let number = (model.pages.firstIndex { $0.id == readAloud.pageID } ?? 0) + 1
        return L10n.readAloudStatus(number, of: model.pages.count)
    }
}
