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
    static var welcomeImportDetail: String { tr("welcome.import.detail") }

    static var welcomeMacSubtitle: String { tr("welcome.mac.subtitle") }

    // First-launch welcome
    static var welcomeBrand: String { tr("welcome.brand") }
    static var welcomeTitle: String { tr("welcome.title") }
    static var welcomeSubtitle: String { tr("welcome.subtitle") }
    static var welcomeCaptureTitle: String { tr("welcome.capture.title") }
    static var welcomeCaptureDetail: String { tr("welcome.capture.detail") }
    static var welcomeNoteTitle: String { tr("welcome.note.title") }
    static var welcomeNoteDetail: String { tr("welcome.note.detail") }
    static var welcomeOrganizeTitle: String { tr("welcome.organize.title") }
    static var welcomeOrganizeDetail: String { tr("welcome.organize.detail") }
    static var welcomeContinue: String { tr("welcome.continue") }
    static var welcomeNoAccount: String { tr("welcome.noAccount") }

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

    static func shapeCoordinates(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) -> String { tr("shape.coordinates", x1, y1, x2, y2) }
    static var shapeTitle: String { tr("shape.title") }

    static var shapeAdd: String { tr("shape.add") }
    static var shapeRectangle: String { tr("shape.rectangle") }
    static var shapeEllipse: String { tr("shape.ellipse") }
    static var shapeLine: String { tr("shape.line") }
    static var shapeArrow: String { tr("shape.arrow") }
    static var shapePosition: String { tr("shape.position") }
    static var shapeStartX: String { tr("shape.startX") }
    static var shapeStartY: String { tr("shape.startY") }
    static var shapeEndX: String { tr("shape.endX") }
    static var shapeEndY: String { tr("shape.endY") }
    static var shapeWidth: String { tr("shape.width") }
    static var shapeThin: String { tr("shape.thin") }
    static var shapeMedium: String { tr("shape.medium") }
    static var shapeThick: String { tr("shape.thick") }
    static var shapeStyle: String { tr("shape.style") }
    static var shapePreview: String { tr("shape.preview") }
    static var shapeDrag: String { tr("shape.drag") }
    static var shapeInvalid: String { tr("shape.invalid") }
    static var shapeHelp: String { tr("shape.help") }
    static var shapeSaveFailed: String { tr("shape.saveFailed") }

    // Symbol stamps
    static var stampTitle: String { tr("stamp.title") }
    static var stampCheckmark: String { tr("stamp.checkmark") }
    static var stampCross: String { tr("stamp.cross") }
    static var stampStar: String { tr("stamp.star") }
    static var stampPreview: String { tr("stamp.preview") }
    static var stampDrag: String { tr("stamp.drag") }
    static var stampInvalid: String { tr("stamp.invalid") }
    static var stampHelp: String { tr("stamp.help") }
    static var stampSaveFailed: String { tr("stamp.saveFailed") }

    // Sidebar
    static var sidebarLibrary: String { tr("sidebar.library") }
    static var allDocuments: String { tr("sidebar.allDocuments") }
    static var favorites: String { tr("sidebar.favorites") }
    static var recentlyDeleted: String { tr("sidebar.recentlyDeleted") }

    // Library
    static var libraryLayout: String { tr("library.layout") }
    static var gridView: String { tr("library.layout.grid") }
    static var listView: String { tr("library.layout.list") }
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
    static var rotate: String { tr("page.rotate") }
    static var more: String { tr("action.more") }
    static var selectedPage: String { tr("page.selected") }
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
    static var scanPages: String { tr("page.scanPages") }
    static var rescanPage: String { tr("page.rescan") }
    static var replacePageWithFile: String { tr("page.replaceWithFile") }
    static var addOrReplacePages: String { tr("page.addOrReplace") }
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
    static var undoReplacePage: String { tr("undo.replacePage") }
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
    // Design pass 3: export sheet
    static var exportDestination: String { tr("export.destination") }
    static var exportToFiles: String { tr("export.destination.files") }
    static var exportToDisk: String { tr("export.destination.disk") }
    static var exportCopy: String { tr("export.destination.copy") }
    static var exportShareTile: String { tr("export.destination.share") }
    static var exportCopyUnavailable: String { tr("export.copy.unavailable") }
    static var exportCopied: String { tr("export.copied") }

    // Settings
    static var settingsTitle: String { tr("settings.title") }
    static var settingsStorage: String { tr("settings.storage") }
    static var settingsDocuments: String { tr("settings.documents") }
    static var settingsSpaceUsed: String { tr("settings.spaceUsed") }
    static func settingsStorageFooter(days: Int) -> String { tr("settings.storage.footer", days) }
    static var settingsExportAll: String { tr("settings.exportAll") }
    static var settingsExportAllFooter: String { tr("settings.exportAll.footer") }
    static func backupArchiveName(_ date: String) -> String { tr("settings.backup.archiveName", Brand.displayName, date) }
    static var settingsLanguage: String { tr("settings.language") }
    static var settingsChangeLanguage: String { tr("settings.language.change") }
    static var settingsLanguageMac: String { tr("settings.language.mac", Brand.displayName) }
    static var settingsAbout: String { tr("settings.about") }
    static var settingsVersion: String { tr("settings.version") }
    static var settingsPrivacy: String { tr("settings.privacy", Brand.displayName) }

    // Design pass 2: folders and sorting
    static var folders: String { tr("sidebar.folders") }
    static var newFolder: String { tr("folder.new") }
    static var renameFolderTitle: String { tr("folder.rename.title") }
    static var deleteFolder: String { tr("folder.delete") }
    static func deleteFolderTitle(_ name: String) -> String { tr("folder.delete.title", name) }
    static var deleteFolderMessage: String { tr("folder.delete.message") }
    static var deleteFolderConfirm: String { tr("folder.delete.confirm") }
    static var moveToFolder: String { tr("folder.moveTo") }
    static var noFolder: String { tr("folder.none") }
    static var emptyFolderTitle: String { tr("library.empty.folder.title") }
    static var emptyFolderMessage: String { tr("library.empty.folder.message") }
    static var sortBy: String { tr("sort.title") }
    static var sortDateModified: String { tr("sort.dateModified") }
    static var sortDateAdded: String { tr("sort.dateAdded") }
    static var sortName: String { tr("sort.name") }
    static func itemCount(_ count: Int) -> String { plural("library.itemCount", count) }
    static var homeTitle: String { tr("library.home.title") }
    static var homeRecent: String { tr("library.home.recent") }
    static var homeSeeAll: String { tr("library.home.seeAll") }

    // Pass 7: Apple Pencil
    static var undoInk: String { tr("undo.ink") }
    static var markup: String { tr("page.markup") }
    static var drawWithFinger: String { tr("page.drawWithFinger") }
    static func strokeCount(_ count: Int) -> String { plural("ink.strokeCount", count) }

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

// File tools: selection, composition and labels.
extension L10n {
    static var mergeTitle: String { tr("tools.mergeTitle") }
    static var extractTitle: String { tr("tools.extractTitle") }
    static var selectItems: String { tr("tools.select") }
    static var selectAll: String { tr("tools.selectAll") }
    static var deselectAll: String { tr("tools.deselectAll") }
    static var duplicate: String { tr("tools.duplicate") }
    static var mergeDocuments: String { tr("tools.merge") }
    static var extractPages: String { tr("tools.extract") }
    static var createDocument: String { tr("tools.create") }
    static var documentName: String { tr("tools.name") }
    static var mergedDocumentName: String { tr("tools.mergedName") }
    static var mergeOrder: String { tr("tools.order") }
    static var toolsPreserveOriginals: String { tr("tools.preserve") }
    static var extractChoosePages: String { tr("tools.choosePages") }
    static var colorLabel: String { tr("tools.colorLabel") }
    static var noColorLabel: String { tr("tools.color.none") }
    static var colorRed: String { tr("tools.color.red") }
    static var colorOrange: String { tr("tools.color.orange") }
    static var colorYellow: String { tr("tools.color.yellow") }
    static var colorGreen: String { tr("tools.color.green") }
    static var colorBlue: String { tr("tools.color.blue") }
    static var colorPurple: String { tr("tools.color.purple") }
    static var colorGray: String { tr("tools.color.gray") }
    static var selectionOn: String { tr("tools.selected") }
    static var selectionOff: String { tr("tools.notSelected") }
    static func selectionCount(_ count: Int) -> String { tr("tools.selectionCount", count) }
    static func extractedDocumentName(_ name: String) -> String { tr("tools.extractedName", name) }
    static func moveDocumentUp(_ name: String) -> String { tr("tools.moveUp", name) }
    static func moveDocumentDown(_ name: String) -> String { tr("tools.moveDown", name) }
}

// Document tools follow-up: splitting one document into one document per page.
extension L10n {
    static var splitPages: String { tr("tools.split") }
    static func splitPageName(_ name: String, _ page: Int) -> String { tr("tools.splitName", name, page) }
}

// Document tools follow-up: exporting a selection as one ZIP of PDFs.
extension L10n {
    static var exportAsZip: String { tr("tools.exportZip") }
    static var exportZipTitle: String { tr("tools.exportZip.title") }
    static var exportZipFooter: String { tr("tools.exportZip.footer") }
    static func exportZipArchiveName(_ date: String) -> String { tr("tools.exportZip.archiveName", Brand.displayName, date) }
}

// The Tools screen: one home for the tools that work today.
extension L10n {
    static var toolsTitle: String { tr("tools.screen.title") }
    static var toolsCreate: String { tr("tools.screen.create") }
    static var toolsDocuments: String { tr("tools.screen.documents") }
    static var toolsNoDocuments: String { tr("tools.screen.empty") }
    static var toolsContinue: String { tr("tools.screen.continue") }
    static var importPhotos: String { tr("tools.photos") }
    static var pickForMerge: String { tr("tools.pick.merge") }
    static var pickForExtract: String { tr("tools.pick.extract") }
    static var pickForSplit: String { tr("tools.pick.split") }
    static var pickForArchive: String { tr("tools.pick.archive") }
}

// F4: reading the printed text on a page.
extension L10n {
    static var recognizeText: String { tr("document.recognizeText") }
    static func recognizeProgress(_ page: Int, _ total: Int) -> String { tr("document.recognizeProgress", page, total) }
}

// F3a: marking recognized lines with editable ink.
extension L10n {
    static var annotateText: String { tr("annotation.title") }
    static var annotationStyle: String { tr("annotation.style") }
    static var annotationHighlight: String { tr("annotation.highlight") }
    static var annotationUnderline: String { tr("annotation.underline") }
    static var annotationStrikethrough: String { tr("annotation.strikethrough") }
    static var annotationLines: String { tr("annotation.lines") }
    static var annotationNoText: String { tr("annotation.noText") }
    static var annotationHelp: String { tr("annotation.help") }
    static var annotationApply: String { tr("annotation.apply") }
    static var annotationChanged: String { tr("annotation.changed") }
}

// F3b: colors and managing saved ink.
extension L10n {
    static var manageMarkup: String { tr("markup.manage") }
    static var markupColor: String { tr("markup.color") }
    static var markupCustomColor: String { tr("markup.customColor") }
    static var markupSaved: String { tr("markup.saved") }
    static var markupEmpty: String { tr("markup.empty") }
    static var markupHelp: String { tr("markup.help") }
    static var markupRecolor: String { tr("markup.recolor") }
    static var markupRemove: String { tr("markup.remove") }
    static var markupChanged: String { tr("markup.changed") }
    static func markupMark(_ number: Int) -> String { tr("markup.mark", number) }
}

// F2a: files kept as themselves.
extension L10n {
    static var filePreviewFailed: String { tr("file.preview.failed") }
    static var filePreviewFailedDescription: String { tr("file.preview.failedDescription") }
    static var fileDetailsTitle: String { tr("file.details.title") }
    static var fileDetailsFooter: String { tr("file.details.footer") }
    static var fileShowDetails: String { tr("file.details.show") }
    static var fileKind: String { tr("file.kind") }
    static var fileKindUnknown: String { tr("file.kind.unknown") }
    static var fileOriginalName: String { tr("file.originalName") }
    static var fileSize: String { tr("file.size") }
    static var fileAdded: String { tr("file.added") }
    static var fileModified: String { tr("file.modified") }
    static var fileSaveCopy: String { tr("file.saveCopy") }
    static var fileExtract: String { tr("file.extract") }
    static var extractArchiveFailed: String { tr("file.extract.failed") }
}

// Notebook creation
extension L10n {
    static var newNotebook: String { tr("notebook.new") }
    static var notebookPaper: String { tr("notebook.paper") }
    static var notebookBlank: String { tr("notebook.blank") }
    static var notebookLined: String { tr("notebook.lined") }
    static var notebookGrid: String { tr("notebook.grid") }
    static var notebookFooter: String { tr("notebook.footer") }
}

// Additional notebook pages
extension L10n {
    static var addNotebookPage: String { tr("notebook.addPage") }
    static var notebookPageTitle: String { tr("notebook.pageTitle") }
    static var notebookPageFooter: String { tr("notebook.addPage.footer") }
    static var notebookPageChanged: String { tr("notebook.pageChanged") }
    static var notebookUndo: String { tr("notebook.undo") }
    static var notebookRedo: String { tr("notebook.redo") }
}

// Page comments
extension L10n {
    static var comments: String { tr("comments.title") }
    static var commentAdd: String { tr("comments.add") }
    static var commentBody: String { tr("comments.body") }
    static var commentEmpty: String { tr("comments.empty") }
    static var commentPrivacy: String { tr("comments.privacy") }
    static var commentSave: String { tr("comments.save") }
    static var commentChanged: String { tr("comments.changed") }
    static var commentLimit: String { tr("comments.limit") }
    static var commentAction: String { tr("comments.action") }
}

extension L10n {
    static var commentSaveAsNew: String { tr("comments.saveAsNew") }
    static var commentHistoryChanged: String { tr("comments.historyChanged") }
    static var commentPageUnavailable: String { tr("comments.pageUnavailable") }
}

// Premium reference dashboard.
extension L10n {
    static var premiumNotes: String { tr("premium.notes") }
    static var premiumMorning: String { tr("premium.morning") }
    static var premiumAfternoon: String { tr("premium.afternoon") }
    static var premiumEvening: String { tr("premium.evening") }
    static var premiumWelcome: String { tr("premium.welcome") }
    static var premiumNew: String { tr("premium.new") }
    static var premiumNotesHint: String { tr("premium.notesHint") }
    static var premiumScanHint: String { tr("premium.scanHint") }
    static var premiumImportHint: String { tr("premium.importHint") }
    static var premiumFolderHint: String { tr("premium.folderHint") }
    static var premiumSearch: String { tr("premium.search") }
    static var premiumEmpty: String { tr("premium.empty") }
    static var premiumEmptyDetail: String { tr("premium.emptyDetail") }
}

extension L10n {
    static var premiumNote: String { tr("premium.note") }
    static var premiumScan: String { tr("premium.scan") }
    static var premiumImport: String { tr("premium.import") }
    static var premiumFolder: String { tr("premium.folder") }
}

// Document outline — ledger row 36.
extension L10n {
    static var outline: String { tr("outline.title") }
    static var outlineEmpty: String { tr("outline.empty") }
}

// Text box tool — ledger row 21.
extension L10n {
    static var textBox: String { tr("textBox.title") }
    static var textBoxText: String { tr("textBox.text") }
    static var textBoxSize: String { tr("textBox.size") }
    static var textBoxAlignment: String { tr("textBox.alignment") }
    static var textBoxAlignLeft: String { tr("textBox.align.left") }
    static var textBoxAlignCenter: String { tr("textBox.align.center") }
    static var textBoxAlignRight: String { tr("textBox.align.right") }
    static var textBoxAdd: String { tr("textBox.add") }
}

// Moving a placed mark — ledger row 21.
extension L10n {
    static var moveObject: String { tr("object.move") }
    static var moveObjectHint: String { tr("object.move.hint") }
}

// Drawing on a Mac — ledger row 21.
extension L10n {
    static var inkPen: String { tr("ink.pen") }
    static var inkHighlighter: String { tr("ink.highlighter") }
}
