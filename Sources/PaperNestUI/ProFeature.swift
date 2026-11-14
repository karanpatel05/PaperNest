import SwiftUI

/// The one list of what PaperNest Pro unlocks. Everything not named here is
/// free. A screen asks `SubscriptionStore.allows(_:)` with the feature it is
/// about to use, and the paywall is built from this same list, so what is
/// blocked and what is advertised cannot drift apart.
enum ProFeature: String, CaseIterable, Identifiable, Sendable {
    /// More than `freeNotebookAllowance` notebooks.
    case notebooks
    /// Reading the text in a scan, which is also what makes it searchable.
    case textRecognition
    /// Searchable PDF, plain text and Word export.
    case textExport
    case passwordExport
    /// Merge, split and extract.
    case pageTools
    /// Shapes, stamps and highlight / underline / strikethrough on text.
    case markup
    case signature
    /// Saving a filled PDF form.
    case forms

    static let freeNotebookAllowance = 3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notebooks: L10n.proNotebooks
        case .textRecognition: L10n.proFeatureRecognition
        case .textExport: L10n.proFeatureTextExport
        case .passwordExport: L10n.proFeaturePassword
        case .pageTools: L10n.proFeaturePageTools
        case .markup: L10n.proFeatureMarkup
        case .signature: L10n.proFeatureSignature
        case .forms: L10n.proFeatureForms
        }
    }

    var symbol: String {
        switch self {
        case .notebooks: "books.vertical"
        case .textRecognition: "text.viewfinder"
        case .textExport: "doc.text"
        case .passwordExport: "lock.doc"
        case .pageTools: "doc.on.doc"
        case .markup: "highlighter"
        case .signature: "signature"
        case .forms: "list.bullet.rectangle"
        }
    }
}

extension View {
    /// Presents the paywall for the feature that was just refused. Attach it
    /// to the screen the refusal happened on: a sheet cannot be presented
    /// from underneath another one.
    func proPaywall(_ feature: Binding<ProFeature?>) -> some View {
        sheet(item: feature) { ProPaywallView(store: .shared, feature: $0) }
    }
}
