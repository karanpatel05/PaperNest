import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestUI

/// Read aloud's player, driven by a fake voice: what it says, which page it
/// is on, what is lit, and how it answers the reader.
@MainActor @Suite(.serialized) struct ReadAloudTests {
    /// Says nothing; records what it was asked to say and lets the test report
    /// what a real synthesizer would.
    final class FakeSpeech: SpeechOutput {
        var onEvent: (@MainActor (Int, SpeechEvent) -> Void)?
        private(set) var said: [(token: Int, text: String, language: String?, speed: Float)] = []
        private(set) var pauses = 0, resumes = 0, stops = 0, releases = 0
        private var nextToken = 1

        func speak(_ text: String, language: String?, speed: Float) -> Int {
            defer { nextToken += 1 }
            said.append((nextToken, text, language, speed))
            return nextToken
        }
        func pause() { pauses += 1 }
        func resume() { resumes += 1 }
        func stop() { stops += 1 }
        func release() { stops += 1; releases += 1 }

        var last: (token: Int, text: String, language: String?, speed: Float)? { said.last }

        /// Reports saying `word` of the last utterance.
        func saying(_ word: String) {
            guard let last else { return }
            onEvent?(last.token, .speaking((last.text as NSString).range(of: word)))
        }
        func finish(_ token: Int? = nil) { onEvent?(token ?? last?.token ?? 0, .finished) }
    }

    /// A document of pages, each with the given words (an empty list is a
    /// page with no text), and a record of the pages it was turned to.
    final class Document {
        let ids: [PageID]
        let words: [PageID: [String]]
        var turnedTo: [PageID] = []
        var shown: PageID

        init(_ pages: [[String]]) {
            ids = pages.map { _ in PageID.make() }
            words = Dictionary(uniqueKeysWithValues: zip(ids, pages))
            shown = ids[0]
        }

        @MainActor var source: ReadAloud.Source {
            ReadAloud.Source(
                pages: { self.ids },
                text: { id in
                    let words = self.words[id] ?? []
                    return PageTextLayout(lines: words.isEmpty ? [] : [PageTextLayout.Line(
                        fragments: words.enumerated().map { index, word in
                            .init(text: word, box: .exact(x: 0.1 + Double(index) * 0.1, y: 0.1, width: 0.08, height: 0.03),
                                  spaceAfter: index < words.count - 1)
                        }, origin: .embedded)])
                },
                turn: { id in self.turnedTo.append(id); self.shown = id })
        }
    }

    private func reading(_ document: Document, from index: Int = 0, speech: FakeSpeech) async -> ReadAloud {
        let readAloud = ReadAloud(output: speech)
        readAloud.start(from: document.ids[index], source: document.source)
        await readAloud.settle()
        return readAloud
    }

    @Test func itStartsAtThePageBeingReadAndLightsEachWord() async throws {
        let speech = FakeSpeech()
        let document = Document([["Cover"], ["The", "budget", "grew"], ["End"]])
        let readAloud = await reading(document, from: 1, speech: speech)
        defer { readAloud.stop() }

        #expect(readAloud.state == .speaking)
        #expect(readAloud.pageID == document.ids[1])
        #expect(speech.last?.text == "The budget grew")
        speech.saying("budget")
        #expect(readAloud.word == "budget")
        let box = try #require(readAloud.boxes.first)
        #expect(abs(box.x - 0.2) < 0.0001)
        #expect(document.turnedTo.isEmpty, "it turned the page it was already on")
    }

    @Test func itTurnsToTheNextPageWithWordsAndPassesOverOneWithout() async {
        let speech = FakeSpeech()
        let document = Document([["First"], [], ["Third", "page"]])
        let readAloud = await reading(document, speech: speech)
        defer { readAloud.stop() }

        speech.finish()
        await readAloud.settle()
        #expect(document.turnedTo == [document.ids[2]], "an empty page was shown, or none was")
        #expect(speech.releases == 0, "the audio was let go between pages")
        #expect(readAloud.pageID == document.ids[2])
        #expect(speech.last?.text == "Third page")
        // The selection change its own turn causes is not the reader turning.
        readAloud.pageChanged(to: document.ids[2])
        await readAloud.settle()
        #expect(speech.said.count == 2, "its own page turn restarted the reading")
    }

    @Test func theReaderTurningThePageStartsItThere() async {
        let speech = FakeSpeech()
        let document = Document([["One"], ["Two"], ["Three", "words", "here"]])
        let readAloud = await reading(document, speech: speech)
        defer { readAloud.stop() }

        readAloud.pageChanged(to: document.ids[2])
        await readAloud.settle()
        #expect(readAloud.pageID == document.ids[2])
        #expect(speech.last?.text == "Three words here")
        #expect(readAloud.state == .speaking)
    }

    @Test func turningThePageWhilePausedWaitsForResume() async {
        let speech = FakeSpeech()
        let document = Document([["One"], ["Two", "words"]])
        let readAloud = await reading(document, speech: speech)
        defer { readAloud.stop() }

        readAloud.pause()
        readAloud.pageChanged(to: document.ids[1])
        await readAloud.settle()
        #expect(readAloud.state == .paused)
        #expect(speech.said.count == 1, "it started talking while paused")
        readAloud.resume()
        await readAloud.settle()
        #expect(speech.last?.text == "Two words")
        #expect(readAloud.state == .speaking)
    }

    /// The synthesizer reports finishing an utterance after it was stopped.
    /// That must not turn the page or start talking again.
    @Test func aLateFinishAfterStopDoesNothing() async {
        let speech = FakeSpeech()
        let document = Document([["One"], ["Two"]])
        let readAloud = await reading(document, speech: speech)
        let token = speech.last?.token

        readAloud.stop()
        speech.finish(token)
        await readAloud.settle()
        #expect(readAloud.state == .idle)
        #expect(document.turnedTo.isEmpty)
        #expect(speech.said.count == 1)
        #expect(readAloud.boxes.isEmpty && readAloud.word.isEmpty)
        #expect(speech.releases == 1, "Stop did not give the audio back")
    }

    /// A new speed says the rest of the page from the word being said, and
    /// the old utterance finishing late must not count as the page finishing.
    @Test func aNewSpeedStartsFromTheCurrentWordAndSkipsNoPage() async {
        let speech = FakeSpeech()
        let document = Document([["One", "two", "three", "four"], ["Next"], ["Last"]])
        let readAloud = await reading(document, speech: speech)
        defer { readAloud.stop() }
        let first = speech.last?.token

        speech.saying("three")
        readAloud.cycleSpeed()
        #expect(readAloud.speed == .faster)
        #expect(speech.last?.text == "three four")
        #expect(speech.last?.speed == 1.25)
        #expect(speech.releases == 0, "a new speed let the audio go and took it back")
        // The new utterance reports "four"; it is still the fourth word of the page.
        speech.saying("four")
        #expect(readAloud.word == "four")
        // The first utterance's finish arrives late: ignored.
        speech.finish(first)
        await readAloud.settle()
        #expect(document.turnedTo.isEmpty, "the stopped utterance turned the page")
        speech.finish()
        await readAloud.settle()
        #expect(document.turnedTo == [document.ids[1]], "a page was skipped: \(document.turnedTo)")
    }

    @Test func pauseAndResumeAndAChangeOfSpeedWhilePaused() async {
        let speech = FakeSpeech()
        let document = Document([["One", "two", "three"]])
        let readAloud = await reading(document, speech: speech)
        defer { readAloud.stop() }

        speech.saying("two")
        readAloud.pause()
        #expect(readAloud.state == .paused && speech.pauses == 1)
        readAloud.resume()
        #expect(readAloud.state == .speaking && speech.resumes == 1)

        readAloud.pause()
        readAloud.cycleSpeed()
        #expect(speech.said.count == 1, "it talked while paused")
        readAloud.resume()
        #expect(speech.last?.text == "two three", "resume did not take the new speed from the word")
        #expect(readAloud.state == .speaking)
    }

    @Test func aCallPausesReading() async {
        let speech = FakeSpeech()
        let readAloud = await reading(Document([["Hello", "there"]]), speech: speech)
        defer { readAloud.stop() }
        speech.onEvent?(speech.last?.token ?? 0, .interrupted)
        #expect(readAloud.state == .paused)
    }

    @Test func theEndOfTheDocumentStops() async {
        let speech = FakeSpeech()
        let document = Document([["Only", "page"]])
        let readAloud = await reading(document, speech: speech)
        speech.finish()
        await readAloud.settle()
        #expect(readAloud.state == .idle)
        #expect(!readAloud.isActive)
    }

    @Test func aDocumentWithNoWordsSaysSo() async {
        let speech = FakeSpeech()
        let readAloud = await reading(Document([[], []]), speech: speech)
        defer { readAloud.stop() }
        #expect(readAloud.state == .noText)
        #expect(speech.said.isEmpty)
    }

    /// One voice at a time across the app: a second document starting to read
    /// stops the first.
    @Test func startingAnotherStopsThisOne() async {
        let first = FakeSpeech(), second = FakeSpeech()
        let one = await reading(Document([["Alpha"]]), speech: first)
        let two = await reading(Document([["Beta"]]), speech: second)
        defer { two.stop() }
        #expect(one.state == .idle)
        #expect(two.state == .speaking)
    }

    /// A word with no box keeps the light on the word before it, and the word
    /// said is still reported.
    @Test func aWordWithNoPlaceLeavesTheLightWhereItWas() async throws {
        let speech = FakeSpeech()
        let id = PageID.make()
        let readAloud = ReadAloud(output: speech)
        readAloud.start(from: id, source: ReadAloud.Source(
            pages: { [id] },
            text: { _ in PageTextLayout(lines: [PageTextLayout.Line(fragments: [
                .init(text: "Boxed", box: .exact(x: 0.1, y: 0.1, width: 0.1, height: 0.03), spaceAfter: true),
                .init(text: "unplaced", box: .exact(x: 0, y: 0, width: 0, height: 0), spaceAfter: false),
            ], origin: .recognized)]) },
            turn: { _ in }))
        await readAloud.settle()
        defer { readAloud.stop() }
        speech.saying("Boxed")
        speech.saying("unplaced")
        #expect(readAloud.word == "unplaced")
        let box = try #require(readAloud.boxes.first)
        #expect(abs(box.x - 0.1) < 0.0001, "the light went out or moved to nowhere")
    }

    @Test func theSpeedButtonGoesRoundAndBack() {
        var speed = ReadAloud.Speed.normal
        var labels: [String] = []
        for _ in 0..<5 { labels.append(speed.label); speed = speed.next }
        #expect(labels == ["1×", "1.25×", "1.5×", "0.75×", "1×"])
    }

    /// A page is read in a voice for its own language.
    @Test func eachPageIsReadInItsOwnLanguage() async {
        #expect(ReadAloud.language(of: "Le budget de la ville a augmenté cette année, selon le rapport du conseil.") == "fr")
        #expect(ReadAloud.language(of: "El presupuesto de la ciudad creció este año, según el informe del consejo.") == "es")
        #expect(ReadAloud.language(of: "The city budget grew this year, according to the council report.") == "en")
        #expect(ReadAloud.language(of: "12 34 56") == nil)

        let speech = FakeSpeech()
        let readAloud = await reading(Document([["Le", "budget", "de", "la", "ville", "a", "augmenté", "cette", "année."]]),
                                      speech: speech)
        defer { readAloud.stop() }
        #expect(speech.last?.language == "fr")
    }
}
