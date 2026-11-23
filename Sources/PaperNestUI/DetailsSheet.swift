import SwiftUI
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestRender
import PaperNestStore

/// Reading a receipt's, a business card's or an invoice's details off the
/// page on screen, for review: every value can be edited, a value read with
/// little certainty says so, and nothing is kept until Save.
@MainActor @Observable
final class DetailsModel {
    enum Phase: Equatable { case loading, noText, ready, failed }

    let session: LibrarySession
    let itemID: ItemID
    let pageID: PageID
    private(set) var phase: Phase = .loading
    private(set) var kind: DetailKind = .receipt
    var texts: [DetailField: String] = [:]
    var lineItems: [LineItem] = []
    private(set) var isStale = false
    /// Details kept from another page of the document, which Save replaces.
    private(set) var replacesPage: Int?
    /// The revision kept details were read at, while they are shown without
    /// reading the page again: saving them keeps them marked as old.
    private var keptRevision: Int?
    /// What was read, to tell a value someone typed from one that was read.
    private var read = CapturedDetails(kind: .receipt)
    private var lines: [CaptureLine] = []

    init(itemID: ItemID, pageID: PageID, session: LibrarySession) {
        self.itemID = itemID
        self.pageID = pageID
        self.session = session
    }

    private var store: LibraryStore? { session.environment?.store }

    /// Shows the details kept for this page, or reads them.
    func load() async {
        guard let store else { phase = .failed; return }
        let kept = try? await store.documentDetails(of: itemID)
        if let kept, kept.pageID != pageID, let pages = try? await store.pages(of: itemID),
           let index = pages.firstIndex(where: { $0.id == kept.pageID }) {
            replacesPage = index + 1
        }
        if let kept, kept.pageID == pageID {
            isStale = kept.isStale
            keptRevision = kept.isStale ? kept.pageRevision : nil
            show(kept.details)
            _ = await readLines()
            phase = .ready
            return
        }
        await readAgain(guessing: true)
    }

    /// Reads the page's current text again, as the kind chosen (or a guess).
    func readAgain(guessing: Bool = false) async {
        guard await readLines() else { return }
        let chosen = guessing ? DetailExtractor.guessKind(lines) : kind
        isStale = false
        keptRevision = nil
        show(DetailExtractor.extract(chosen, from: lines))
        phase = .ready
    }

    private func readLines() async -> Bool {
        guard let store, let renderer = session.environment?.renderer,
              let page = try? await store.page(pageID) else { phase = .failed; return false }
        lines = (try? await renderer.captureLines(for: page)) ?? []
        if lines.isEmpty && phase != .ready { phase = .noText }
        return !lines.isEmpty
    }

    func choose(_ kind: DetailKind) {
        guard kind != self.kind else { return }
        if lines.isEmpty { self.kind = kind; return }
        show(DetailExtractor.extract(kind, from: lines))
    }

    private func show(_ details: CapturedDetails) {
        read = details
        kind = details.kind
        texts = Dictionary(uniqueKeysWithValues: details.kind.fields.map { ($0, details[$0]) })
        lineItems = details.lineItems
    }

    /// Whether a value read with little certainty is still as it was read.
    func needsCheck(_ field: DetailField) -> Bool {
        guard let value = read.values[field] else { return false }
        return value.needsReview && texts[field] == value.text
    }

    /// The details as reviewed: a value someone changed counts as certain.
    var reviewed: CapturedDetails {
        var details = CapturedDetails(kind: kind, lineItems: lineItems.filter { !$0.description.isEmpty || !$0.amount.isEmpty })
        for field in kind.fields {
            let text = (texts[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if let value = read.values[field], value.text == text { details.values[field] = value }
            else { details.values[field] = DetailValue(text: text, confidence: 1) }
        }
        return details
    }

    func save() async -> Bool {
        guard let store else { return false }
        do {
            try await store.saveDocumentDetails(reviewed, for: itemID, readFrom: pageID, keepingRevision: keptRevision)
            return true
        } catch {
            phase = .failed
            return false
        }
    }

    func label(_ field: DetailField) -> String {
        switch field {
        case .merchant: L10n.detailsFieldMerchant
        case .date: L10n.detailsFieldDate
        case .total: L10n.detailsFieldTotal
        case .tax: L10n.detailsFieldTax
        case .currency: L10n.detailsFieldCurrency
        case .name: L10n.detailsFieldName
        case .company: L10n.detailsFieldCompany
        case .phone: L10n.detailsFieldPhone
        case .email: L10n.detailsFieldEmail
        case .address: L10n.detailsFieldAddress
        case .website: L10n.detailsFieldWebsite
        case .supplier: L10n.detailsFieldSupplier
        case .invoiceNumber: L10n.detailsFieldInvoiceNumber
        case .dueDate: L10n.detailsFieldDueDate
        }
    }

    var vCard: DetailsFile {
        DetailsFile(data: Data(DetailFormats.vCard(reviewed).utf8), type: .vCard, name: "Contact.vcf")
    }

    var csv: DetailsFile {
        DetailsFile(data: Data(DetailFormats.csv(reviewed, label: label(_:),
                                                 itemHeaders: (L10n.detailsDescription, L10n.detailsAmount)).utf8),
                    type: .commaSeparatedText, name: "Details.csv")
    }
}

/// A vCard or CSV handed to the share sheet, written only when shared.
struct DetailsFile: Transferable {
    let data: Data
    let type: UTType
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .vCard) { $0.data }.suggestedFileName("Contact.vcf")
            .exportingCondition { $0.type == .vCard }
        DataRepresentation(exportedContentType: .commaSeparatedText) { $0.data }.suggestedFileName("Details.csv")
            .exportingCondition { $0.type == .commaSeparatedText }
    }
}

struct DetailsSheet: View {
    @State private var model: DetailsModel
    @Environment(\.dismiss) private var dismiss

    init(itemID: ItemID, pageID: PageID, session: LibrarySession) {
        _model = State(initialValue: DetailsModel(itemID: itemID, pageID: pageID, session: session))
    }

    var body: some View {
        NavigationStack {
            Form { content }
                .navigationTitle(L10n.detailsTitle)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.cancel) { dismiss() }.accessibilityIdentifier("details-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.detailsSave) {
                            Task { if await model.save() { dismiss() } }
                        }
                        .disabled(model.phase != .ready)
                        .accessibilityIdentifier("details-save")
                    }
                }
                .task { await model.load() }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .noText:
            Text(L10n.detailsNoText).accessibilityIdentifier("details-no-text")
        case .failed:
            Text(L10n.detailsFailed).accessibilityIdentifier("details-failed")
        case .ready:
            kinds
            fields
            if model.kind == .invoice { items }
            actions
        }
    }

    /// Inline rows rather than a pop-up or segmented control: "Une carte de
    /// visite" and "Una tarjeta de visita" are long.
    private var kinds: some View {
        Section(L10n.detailsKind) {
            ForEach(DetailKind.allCases, id: \.self) { kind in
                Button { model.choose(kind) } label: {
                    HStack {
                        Text(verbatim: title(kind)).foregroundStyle(.primary)
                        Spacer()
                        if model.kind == kind { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("details-kind-\(kind.rawValue)")
                .accessibilityValue(model.kind == kind ? L10n.selectionOn : L10n.selectionOff)
            }
        }
    }

    private var fields: some View {
        Section {
            ForEach(model.kind.fields, id: \.self) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: model.label(field)).font(.app(.caption)).foregroundStyle(.secondary)
                    TextField(model.label(field), text: Binding(get: { model.texts[field] ?? "" },
                                                                set: { model.texts[field] = $0 }))
                        .accessibilityIdentifier("details-field-\(field.rawValue)")
                    if model.needsCheck(field) {
                        Label(L10n.detailsCheck, systemImage: "exclamationmark.triangle").font(.app(.caption)).foregroundStyle(.orange)
                            .accessibilityIdentifier("details-check-\(field.rawValue)")
                    }
                }
            }
        } header: {
            Text(L10n.detailsFields)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.detailsOnDevice)
                if model.isStale { Text(L10n.detailsStale).foregroundStyle(.orange).accessibilityIdentifier("details-stale") }
                if let page = model.replacesPage {
                    Text(L10n.detailsReplaces(page)).foregroundStyle(.orange).accessibilityIdentifier("details-replaces")
                }
            }
        }
    }

    private var items: some View {
        Section {
            ForEach($model.lineItems) { $item in
                HStack {
                    TextField(L10n.detailsDescription, text: $item.description)
                    TextField(L10n.detailsAmount, text: $item.amount)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 120)
                }
                .accessibilityIdentifier("details-line-item")
            }
            .onDelete { model.lineItems.remove(atOffsets: $0) }
            Button { model.lineItems.append(LineItem(description: "", amount: "")) } label: {
                Label(L10n.detailsAddRow, systemImage: "plus")
            }
            .accessibilityIdentifier("details-add-row")
        } header: {
            Text(L10n.detailsLineItems)
        } footer: {
            Text(L10n.detailsLineItemsNote)
        }
    }

    private var actions: some View {
        Section {
            Button { Task { await model.readAgain() } } label: {
                Label(L10n.detailsReadAgain, systemImage: "arrow.clockwise")
            }
            .accessibilityIdentifier("details-read-again")
            if model.kind == .businessCard {
                ShareLink(item: model.vCard, preview: SharePreview(model.vCard.name)) {
                    Label(L10n.detailsShareCard, systemImage: "person.crop.square")
                }
                .accessibilityIdentifier("details-share-card")
            } else {
                ShareLink(item: model.csv, preview: SharePreview(model.csv.name)) {
                    Label(L10n.detailsShareCSV, systemImage: "tablecells")
                }
                .accessibilityIdentifier("details-share-csv")
            }
        }
    }

    private func title(_ kind: DetailKind) -> String {
        switch kind {
        case .receipt: L10n.detailsKindReceipt
        case .businessCard: L10n.detailsKindBusinessCard
        case .invoice: L10n.detailsKindInvoice
        }
    }
}
