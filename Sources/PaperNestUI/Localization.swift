import Foundation
import PaperNestCore

/// Locates this module's resource bundle. SwiftPM's generated `Bundle.module`
/// looks beside the app bundle root, which is not where a signed `.app`
/// keeps resources, so `Contents/Resources` is checked first.
enum ResourceBundle {
    static let name = "PaperNest_PaperNestUI.bundle"

    static let ui: Bundle = {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(name),
            Bundle.main.bundleURL.appendingPathComponent(name),
            Bundle(for: Marker.self).resourceURL?.appendingPathComponent(name),
        ]
        for case let url? in candidates {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return Bundle.module
    }()

    private final class Marker {}
}

/// Every user-visible string. Keys live in `Resources/<lang>.lproj`;
/// `LocalizationTests` checks that each key used here exists in English,
/// French and Spanish with matching format arguments.
enum L10n {
    static func tr(_ key: String) -> String {
        ResourceBundle.ui.localizedString(forKey: key, value: nil, table: nil)
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: args)
    }

    /// Plural-aware lookup backed by `Localizable.stringsdict`.
    static func plural(_ key: String, _ count: Int) -> String {
        String.localizedStringWithFormat(ResourceBundle.ui.localizedString(forKey: key, value: nil, table: nil), count)
    }

    // Sidebar
    static var sidebarLibrary: String { tr("sidebar.library") }
    static var allDocuments: String { tr("sidebar.allDocuments") }
    static var favorites: String { tr("sidebar.favorites") }
    static var recentlyDeleted: String { tr("sidebar.recentlyDeleted") }

    // Library
    static var emptyLibraryTitle: String { tr("library.empty.title") }
    static var emptyLibraryMessageMac: String { tr("library.empty.message.mac") }
    static var emptyLibraryMessageTouch: String { tr("library.empty.message.touch") }
    static var emptyFavoritesTitle: String { tr("library.empty.favorites.title") }
    static var emptyFavoritesMessage: String { tr("library.empty.favorites.message") }
    static var emptyDeletedTitle: String { tr("library.empty.deleted.title") }
    static func emptyDeletedMessage(days: Int) -> String { tr("library.empty.deleted.message", days) }
    static var searchPrompt: String { tr("library.search.prompt") }
    static var noResultsTitle: String { tr("library.search.noResults.title") }
    static func noResultsMessage(_ query: String) -> String { tr("library.search.noResults.message", query) }
    static func pageCount(_ count: Int) -> String { plural("item.pageCount", count) }
    static func deletedOn(_ date: String) -> String { tr("item.deletedOn", date) }
    static func itemAccessibilityLabel(name: String, pages: String) -> String { tr("accessibility.itemSummary", name, pages) }
    static var loadingLibrary: String { tr("library.loading") }
    static var importing: String { tr("library.importing") }

    // Actions
    static var importFiles: String { tr("action.import") }
    static var scan: String { tr("action.scan") }
    static var paste: String { tr("action.paste") }
    static var open: String { tr("action.open") }
    static var rename: String { tr("action.rename") }
    static var addFavorite: String { tr("action.favorite") }
    static var removeFavorite: String { tr("action.unfavorite") }
    static var delete: String { tr("action.delete") }
    static var recover: String { tr("action.recover") }
    static var deletePermanently: String { tr("action.deletePermanently") }
    static var cancel: String { tr("action.cancel") }
    static var ok: String { tr("action.ok") }
    static var done: String { tr("action.done") }
    static var export: String { tr("action.export") }

    static var renameTitle: String { tr("rename.title") }
    static var renamePlaceholder: String { tr("rename.placeholder") }
    static func deletePermanentlyTitle(_ name: String) -> String { tr("deletePermanently.title", name) }
    static var deletePermanentlyMessage: String { tr("deletePermanently.message") }
    static func pastedImageName(_ date: String) -> String { tr("paste.defaultName", date) }
    static func scanName(_ date: String) -> String { tr("scan.defaultName", date) }
    static var scanUnsupported: String { tr("scan.unsupported") }
    static var scanFailed: String { tr("scan.failed", Brand.displayName) }

    // Document
    static var pages: String { tr("document.pages") }
    static var emptyDocumentTitle: String { tr("document.empty.title") }
    static var emptyDocumentMessage: String { tr("document.empty.message") }
    static var rotateLeft: String { tr("page.rotateLeft") }
    static var rotateRight: String { tr("page.rotateRight") }
    static var filter: String { tr("page.filter") }
    static var filterOriginal: String { tr("filter.original") }
    static var filterGrayscale: String { tr("filter.grayscale") }
    static var filterBlackAndWhite: String { tr("filter.blackAndWhite") }
    static var adjustments: String { tr("page.adjustments") }
    static var brightness: String { tr("page.brightness") }
    static var contrast: String { tr("page.contrast") }
    static var resetAdjustments: String { tr("page.resetAdjustments") }
    static var revertToOriginal: String { tr("page.revert") }
    static var crop: String { tr("page.crop") }
    static var cropMenuItem: String { tr("page.cropMenuItem") }
    static var cropReset: String { tr("crop.reset") }
    static var cropArea: String { tr("crop.area") }
    static var cropHint: String { tr("crop.hint") }
    static func cropKept(width: String, height: String) -> String { tr("crop.kept", width, height) }
    static var deletePage: String { tr("page.delete") }
    static var movePageUp: String { tr("page.moveUp") }
    static var movePageDown: String { tr("page.moveDown") }
    static var addPages: String { tr("page.addPages") }
    static func pageLabel(_ number: Int, of total: Int) -> String { tr("page.label", number, total) }
    static var pageUnavailable: String { tr("page.unavailable") }
    static var pageLoadFailed: String { tr("page.loadFailed") }
    static var zoomIn: String { tr("page.zoomIn") }
    static var zoomOut: String { tr("page.zoomOut") }
    static var zoomToFit: String { tr("page.zoomToFit") }
    static var menuPage: String { tr("menu.page") }

    static var undoRotate: String { tr("undo.rotate") }
    static var undoFilter: String { tr("undo.filter") }
    static var undoAdjust: String { tr("undo.adjust") }
    static var undoCrop: String { tr("undo.crop") }
    static var undoDeletePage: String { tr("undo.deletePage") }
    static var undoMovePage: String { tr("undo.movePage") }

    // Export
    static var exportTitle: String { tr("export.title") }
    static var exportFormat: String { tr("export.format") }
    static var exportPages: String { tr("export.pages") }
    static var exportAllPages: String { tr("export.pages.all") }
    static var exportCurrentPage: String { tr("export.pages.current") }
    static var exportRange: String { tr("export.pages.range") }
    static var exportFrom: String { tr("export.pages.from") }
    static var exportTo: String { tr("export.pages.to") }
    static var paperSize: String { tr("export.paperSize") }
    static var paperOriginal: String { tr("paper.original") }
    static var paperLetter: String { tr("paper.usLetter") }
    static var paperA4: String { tr("paper.a4") }
    static var paperNote: String { tr("export.paperSize.note") }
    static var imageQuality: String { tr("export.quality") }
    static var qualityBest: String { tr("quality.best") }
    static var qualityBalanced: String { tr("quality.balanced") }
    static var qualityCompact: String { tr("quality.compact") }
    static var resolution: String { tr("export.resolution") }
    static func dpi(_ value: Int) -> String { tr("export.resolution.dpi", value) }
    static var jpegQuality: String { tr("export.jpegQuality") }
    static var multiplePages: String { tr("export.packaging") }
    static var packagingZip: String { tr("packaging.zip") }
    static var packagingSeparate: String { tr("packaging.separate") }
    static func exportProgress(_ done: Int, _ total: Int) -> String { tr("export.progress", done, total) }
    static func exportReady(_ size: String) -> String { tr("export.ready", size) }
    static var exportButton: String { tr("export.button") }
    static var exportSave: String { tr("export.save") }
    static var exportShare: String { tr("export.share") }
    static var exportVectorNote: String { tr("export.vectorNote") }
    static var exportFailed: String { tr("export.failed") }
    static var exportInvalidRange: String { tr("export.invalidRange") }

    // Errors
    static func importErrorTitle(_ file: String) -> String { tr("error.import.title", file) }
    static var importErrorsTitle: String { tr("error.import.multiple.title") }
    static func importErrorLine(_ file: String, _ reason: String) -> String { tr("error.import.line", file, reason) }
    static var importUnsupported: String { tr("error.import.unsupported") }
    static var importUnreadable: String { tr("error.import.unreadable") }
    static var importDamaged: String { tr("error.import.damaged") }
    static var importEmpty: String { tr("error.import.empty") }
    static var importIncorrectPassword: String { tr("error.import.incorrectPassword") }
    static var importProtectedUnsupported: String { tr("error.import.protectedUnsupported") }
    static var importRestricted: String { tr("error.import.restricted") }
    static var importTooLarge: String { tr("error.import.tooLarge") }
    static func passwordTitle(_ file: String) -> String { tr("password.title", file) }
    static var passwordMessage: String { tr("password.message", Brand.displayName) }
    static var passwordField: String { tr("password.field") }
    static var passwordOpen: String { tr("password.open") }
    static var genericErrorTitle: String { tr("error.generic.title") }
    static var saveFailed: String { tr("error.save") }
    static var libraryErrorTitle: String { tr("error.library.title") }
    static var libraryNewer: String { tr("error.library.newer", Brand.displayName) }
    static var libraryOpenFailed: String { tr("error.library.open") }
}
