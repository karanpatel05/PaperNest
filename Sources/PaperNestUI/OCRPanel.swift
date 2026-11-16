import PaperNestCore
import PaperNestRender
import SwiftUI

struct OCRPanel: View {
    let model: DocumentModel
    var isEmbedded = false
    var onClose: (() -> Void)?
    var beforeAction: (() async -> Bool)?
    @Environment(\.dismiss) private var dismiss
    @State private var languages = Set(RecognitionLanguagePreference.choice().using)
    @State private var available = TextRecognizer.availableLanguages()
    @State private var languageOrder = RecognitionLanguagePreference.choice().using
    @State private var pinnedLanguages = Set(RecognitionLanguagePreference.choice().using)
    @State private var choice = PageChoice.all
    @State private var range = ""
    @State private var running = false
    @State private var result: String?
    @State private var proFeature: ProFeature?
    private enum PageChoice { case all, current, range }

    private var indices: [Int]? {
        switch choice {
        case .all: return Array(model.pages.indices)
        case .current: return model.selectedIndex.map { [$0] }
        case .range: return OCRPageSelection.indices(in: range, pageCount: model.pages.count)
        }
    }
    private var selectedCount: Int { indices?.count ?? 0 }
    private var busy: Bool { running || model.isRecognizing }
    private var preferred: [String] {
        available.filter { TextRecognizer.preferredLanguages.contains($0) || pinnedLanguages.contains($0) }.sorted()
    }
    private var otherLanguages: [String] { available.filter { !preferred.contains($0) }.sorted() }

    var body: some View {
        DocumentToolPanel(title: L10n.recognizeText, symbol: "text.viewfinder", closeID: "ocr-close", busy: busy,
                          close: { if let onClose { onClose() } else { dismiss() } }) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.title2).foregroundStyle(EditorChrome.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: model.item?.name ?? "").font(.headline)
                    Text(L10n.pageCount(model.pages.count)).font(.caption).foregroundStyle(EditorChrome.secondaryText)
                }
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(EditorChrome.lavender, in: RoundedRectangle(cornerRadius: 14))
            PanelSection(title: L10n.ocrLanguages) {
                PanelNote(text: L10n.ocrLanguagesHelp)
                ForEach(preferred, id: \.self) { languageRow($0) }
                if !otherLanguages.isEmpty {
                    DisclosureGroup(L10n.ocrMoreLanguages) {
                        ForEach(otherLanguages, id: \.self) { languageRow($0) }
                    }
                }
                if languages.isEmpty { PanelNote(text: L10n.ocrChooseLanguage) }
            }
            .disabled(busy)
            PanelSection(title: L10n.exportPages) {
                pageChoice(.all, title: L10n.exportAllPages, detail: L10n.pageCount(model.pages.count), id: "all")
                pageChoice(.current, title: L10n.exportCurrentPage,
                           detail: L10n.pageCounter((model.selectedIndex ?? 0) + 1, model.pages.count), id: "current")
                pageChoice(.range, title: L10n.exportRange, detail: nil, id: "range")
                if choice == .range {
                    TextField(L10n.ocrRangeHint, text: $range)
                        .textFieldStyle(.roundedBorder).accessibilityLabel(L10n.exportRange)
                        .accessibilityIdentifier("ocr-range-input")
                    if indices == nil { PanelNote(text: L10n.ocrInvalidRange) }
                }
                Text(L10n.ocrSelected(selectedCount)).font(.caption).foregroundStyle(EditorChrome.secondaryText)
                    .accessibilityIdentifier("ocr-page-count")
                    .accessibilityValue(String(selectedCount))
            }.disabled(busy)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        VStack(spacing: 4) {
                            PageImageView(page: page, pixelSize: 180).frame(width: 54, height: 72)
                                .clipped().background(Color.white)
                            Text(verbatim: "\(index + 1)").font(.caption)
                        }
                        .padding(5)
                        .background((indices ?? []).contains(index) ? EditorChrome.lavender : EditorChrome.surface,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder((indices ?? []).contains(index) ? EditorChrome.purple : EditorChrome.border) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L10n.pageCounter(index + 1, model.pages.count))
                        .accessibilityValue((indices ?? []).contains(index) ? L10n.selectionOn : L10n.selectionOff)
                    }
                }
            }
            PanelNote(text: L10n.ocrOutputHelp)
        } footer: {
            if let progress = model.recognitionProgress {
                ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                Text(L10n.recognizeProgress(min(progress.done + 1, progress.total), progress.total))
                    .font(.caption).accessibilityIdentifier("ocr-progress")
            }
            if let result {
                Text(verbatim: result).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ocr-result")
            }
            Button { start() } label: {
                Text(L10n.ocrStart(selectedCount)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 36)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(busy || selectedCount == 0 || languages.isEmpty)
            .accessibilityIdentifier("ocr-start")
        }
        .toolPanelAppearance(isEmbedded: isEmbedded)
        .interactiveDismissDisabled(busy)
        .proPaywall($proFeature)
        #if os(macOS)
        .frame(minWidth: isEmbedded ? nil : 360, idealWidth: isEmbedded ? nil : 440,
               minHeight: isEmbedded ? nil : 560, idealHeight: isEmbedded ? nil : 720)
        #endif
    }

    private func languageRow(_ code: String) -> some View {
        let selected = languages.contains(code)
        return Button {
            if selected {
                languages.remove(code)
                languageOrder.removeAll { $0 == code }
            } else {
                languages.insert(code)
                languageOrder.append(code)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square").foregroundStyle(EditorChrome.purple)
                Text(verbatim: RecognitionLanguagePreference.name(of: code)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityValue(selected ? L10n.selectionOn : L10n.selectionOff)
            .accessibilityIdentifier("ocr-language-\(code)")
    }

    private func pageChoice(_ value: PageChoice, title: String, detail: String?, id: String) -> some View {
        Button { choice = value; result = nil } label: {
            HStack(spacing: 10) {
                Image(systemName: choice == value ? "largecircle.fill.circle" : "circle").foregroundStyle(EditorChrome.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: title).fixedSize(horizontal: false, vertical: true)
                    if let detail { Text(verbatim: detail).font(.caption).foregroundStyle(EditorChrome.secondaryText) }
                }
                Spacer(minLength: 0)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(choice == value ? L10n.selectionOn : L10n.selectionOff)
            .accessibilityIdentifier("ocr-pages-\(id)")
    }

    private func start() {
        guard !busy, let indices, !indices.isEmpty, !languages.isEmpty else { return }
        guard SubscriptionStore.shared.allows(.textRecognition) else { proFeature = .textRecognition; return }
        let pageIDs = Set(indices.map { model.pages[$0].id })
        let requested = languageOrder.filter { languages.contains($0) && available.contains($0) }
        running = true
        result = nil
        Task {
            defer { running = false }
            guard await beforeAction?() ?? true else { return }
            let completed = await model.recognizeText(pageIDs: pageIDs, languages: requested, reportsErrors: false)
            result = L10n.ocrCompleted(completed, pageIDs.count)
            if completed < pageIDs.count { result = (result ?? "") + "\n" + L10n.ocrIncomplete }
        }
    }
}
