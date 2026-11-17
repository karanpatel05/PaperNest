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
    static var closeDraftTitle: String { tr("studio.closeDraftTitle") }
    static var closeDraftMessage: String { tr("studio.closeDraftMessage") }
    static var keepDocumentOpen: String { tr("studio.keepOpen") }

    // iPad capture decision
    static var scannerKeepScan: String { tr("scanner.keepScan") }
    static var scannerReviewCapture: String { tr("scanner.reviewCapture") }
    static var scannerReviewCaptureHint: String { tr("scanner.reviewCaptureHint") }
    static var scannerAuto: String { tr("scanner.auto") }
    static var scannerManual: String { tr("scanner.manual") }
    static var scannerEnhance: String { tr("scanner.enhance") }
    static var scannerEdit: String { tr("scanner.edit") }
    static var scannerMoveEarlier: String { tr("scanner.moveEarlier") }
    static var scannerMoveLater: String { tr("scanner.moveLater") }

    static var scannerFlash: String { tr("scanner.flash") }
    static var scannerOn: String { tr("scanner.on") }
    static var scannerOff: String { tr("scanner.off") }
    static var scannerNative: String { tr("scanner.native") }
    static var scannerCameraUnavailable: String { tr("scanner.cameraUnavailable") }
    static var scannerRetry: String { tr("scanner.retry") }
    static var scannerReview: String { tr("scanner.review") }
    static var scannerWhiteboard: String { tr("scanner.mode.whiteboard") }
    static var scannerCard: String { tr("scanner.mode.card") }
    static var scannerPresets: String { tr("scanner.presets") }
    static var scannerOriginal: String { tr("scanner.preset.original") }
    static var scannerAutoPreset: String { tr("scanner.preset.auto") }
    static var scannerEnhancedPreset: String { tr("scanner.preset.enhanced") }
    static var scannerHighContrast: String { tr("scanner.preset.highContrast") }
    static var scannerCleanup: String { tr("scanner.cleanup") }
    static var scannerRemoveShadows: String { tr("scanner.cleanup.shadows") }
    static var scannerWhitenBackground: String { tr("scanner.cleanup.whiten") }
    static var scannerSharpenText: String { tr("scanner.cleanup.sharpen") }
    static var scannerApplyToPage: String { tr("scanner.cleanup.applyPage") }
    static var scannerApplyToAll: String { tr("scanner.cleanup.applyAll") }
    static var scannerSelectPages: String { tr("scanner.selectPages") }

    // Approved studio redesign: workspace navigation.
    static var showPageThumbnails: String { tr("studio.showPages") }
    static var hidePageThumbnails: String { tr("studio.hidePages") }
    static var closeDocumentTab: String { tr("studio.closeTab") }
    static var openAnotherDocument: String { tr("studio.openAnother") }
    static func openDocumentTabs(_ count: Int) -> String { tr("studio.openTabs", count) }

    // PDF tools sidebar
    static var pdfTools: String { tr("pdfTools.title") }
    // Editor side panels (Claude, merged panel control 2026-11-10)
    static var editorPanels: String { tr("studio.panels") }
    static var hidePDFTools: String { tr("pdfTools.hide") }

    // PDF form workspace
    static var formTitle: String { tr("form.formTitle") }
    static func formCopyName(_ name: String) -> String { tr("form.formCopyName", name) }
    static var formSaved: String { tr("form.formSaved") }
    static var formLoadFailed: String { tr("form.formLoadFailed") }
    static var formNoFields: String { tr("form.formNoFields") }
    static var formNoFieldsHelp: String { tr("form.formNoFieldsHelp") }
    static var formCopyHelp: String { tr("form.formCopyHelp") }
    static var formExportHelp: String { tr("form.formExportHelp") }
    static var formUnsupported: String { tr("form.formUnsupported") }
    static var formSaveCopy: String { tr("form.formSaveCopy") }

    // Inline text editing
    static var inlineBack: String { tr("inline.back") }
    static var inlinePlace: String { tr("inline.inlinePlace") }
    static var inlineFont: String { tr("inline.inlineFont") }
    static var inlineBold: String { tr("inline.inlineBold") }
    static var inlineItalic: String { tr("inline.inlineItalic") }
    static var inlineSans: String { tr("inline.inlineSans") }
    static var inlineSerif: String { tr("inline.inlineSerif") }
    static var inlineMono: String { tr("inline.inlineMono") }
    static var inlineRetry: String { tr("inline.inlineRetry") }
    static var inlineCopyText: String { tr("inline.copyText") }
    static var inlineRecover: String { tr("inline.recover") }
    static var inlineSaveAsNew: String { tr("inline.saveAsNew") }
    static var inlineDiscardDraft: String { tr("inline.discardDraft") }
    static var inlineDiscardHelp: String { tr("inline.discardHelp") }
    static var inlineLarger: String { tr("inline.inlineLarger") }
    static var inlineSmaller: String { tr("inline.inlineSmaller") }
    static var inlineMoveLeft: String { tr("inline.inlineMoveLeft") }
    static var inlineMoveRight: String { tr("inline.inlineMoveRight") }
    static var inlineMoveUp: String { tr("inline.inlineMoveUp") }
    static var inlineMoveDown: String { tr("inline.inlineMoveDown") }
    static var inlineWider: String { tr("inline.inlineWider") }
    static var inlineNarrower: String { tr("inline.inlineNarrower") }
    static var inlineTaller: String { tr("inline.inlineTaller") }
    static var inlineShorter: String { tr("inline.inlineShorter") }
    static var inlineGeometryHint: String { tr("inline.inlineGeometryHint") }

    // Notes library
    static var emptyNotesTitle: String { tr("notes.empty.title") }
    static var emptyNotesMessage: String { tr("notes.empty.message") }
    static var proClose: String { tr("pro.close") }
    // Pro and Profile
    static var profile: String { tr("pro.profile") }
    static var proTitle: String { tr("pro.proTitle") }
    static var proHeadline: String { tr("pro.proHeadline") }
    static var proSubtitle: String { tr("pro.proSubtitle") }
    static var proNotebooks: String { tr("pro.proNotebooks") }
    static var proFeatureRecognition: String { tr("pro.feature.recognition") }
    static var proFeatureTextExport: String { tr("pro.feature.textExport") }
    static var proFeaturePassword: String { tr("pro.feature.password") }
    static var proFeaturePageTools: String { tr("pro.feature.pageTools") }
    static var proFeatureMarkup: String { tr("pro.feature.markup") }
    static var proFeatureSignature: String { tr("pro.feature.signature") }
    static var proFeatureForms: String { tr("pro.feature.forms") }
    static func proFeatureLocked(_ value0: String) -> String { tr("pro.feature.locked", value0) }
    static var proMonthly: String { tr("pro.proMonthly") }
    static var proYearly: String { tr("pro.proYearly") }
    static func proMonthPrice(_ value0: String) -> String { tr("pro.proMonthPrice", value0) }
    static func proYearPrice(_ value0: String) -> String { tr("pro.proYearPrice", value0) }
    static var proTrialCTA: String { tr("pro.proTrialCTA") }
    static var proSubscribe: String { tr("pro.proSubscribe") }
    static var proUpgrade: String { tr("pro.proUpgrade") }
    static var proContinueFree: String { tr("pro.proContinueFree") }
    static var proFreeDetail: String { tr("pro.proFreeDetail") }
    static func proTrialBilling(_ value0: String) -> String { tr("pro.proTrialBilling", value0) }
    static var proRenewalTerms: String { tr("pro.proRenewalTerms") }
    static var proRestore: String { tr("pro.proRestore") }
    static var proManage: String { tr("pro.proManage") }
    static var proTerms: String { tr("pro.proTerms") }
    static var proPrivacy: String { tr("pro.proPrivacy") }
    static var proSupport: String { tr("pro.proSupport") }
    static var proUnavailable: String { tr("pro.proUnavailable") }
    static var proLegalUnavailable: String { tr("pro.proLegalUnavailable") }
    static var proLoadError: String { tr("pro.proLoadError") }
    static var proVerificationError: String { tr("pro.proVerificationError") }
    static var proPending: String { tr("pro.proPending") }
    static var proPurchaseError: String { tr("pro.proPurchaseError") }
    static var proRestored: String { tr("pro.proRestored") }
    static var proNothingToRestore: String { tr("pro.proNothingToRestore") }
    static var proRestoreError: String { tr("pro.proRestoreError") }
    static var proFree: String { tr("pro.proFree") }
    static var proTrial: String { tr("pro.proTrial") }
    static var proActive: String { tr("pro.proActive") }
    static var proCanceled: String { tr("pro.proCanceled") }
    static var proExpired: String { tr("pro.proExpired") }
    static var proBillingIssue: String { tr("pro.proBillingIssue") }
    static func proTrialEnds(_ value0: String, _ value1: String) -> String { tr("pro.proTrialEnds", value0, value1) }
    static func proRenews(_ value0: String) -> String { tr("pro.proRenews", value0) }
    static func proAccessEnds(_ value0: String) -> String { tr("pro.proAccessEnds", value0) }
    static var proContentSafe: String { tr("pro.proContentSafe") }
    static var proLoading: String { tr("pro.proLoading") }
    static var proRetry: String { tr("pro.proRetry") }

    // Unified studio redesign
    static var studioShared: String { tr("studio.shared") }
    static var studioSharedDetail: String { tr("studio.shared.detail") }
    static var studioLocalStorage: String { tr("studio.localStorage") }
    static var studioSyncDetail: String { tr("studio.sync.detail") }
    static var studioMySpace: String { tr("studio.mySpace") }
    static var studioToolSettings: String { tr("studio.toolSettings") }
    // Compact notebook writing controls
    static var studioStrokePreview: String { tr("studio.strokePreview") }
    // Round eraser controls
    static var eraserSize: String { tr("eraser.size") }
    static var eraserSmall: String { tr("eraser.small") }
    static var eraserMedium: String { tr("eraser.medium") }
    static var eraserLarge: String { tr("eraser.large") }
    static var eraserMode: String { tr("eraser.mode") }
    static var eraserPrecision: String { tr("eraser.precision") }
    static var eraserStroke: String { tr("eraser.stroke") }
    static var eraserPrecisionDetail: String { tr("eraser.precision.detail") }
    static var studioEraserDetail: String { tr("studio.eraserDetail") }
    static func studioWidthValue(_ value: String) -> String { tr("studio.widthValue", value) }
    static var studioOpacity: String { tr("studio.opacity") }

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
    static var notebookScrollAdd: String { tr("notebook.scrollAdd") }

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

// Placing an image — ledger row 21.
extension L10n {
    // Notes camera capture
    static var takePhoto: String { tr("image.take_photo") }
    static var photoCameraPermission: String { tr("image.camera_permission") }
    static var photoCaptureFailed: String { tr("image.capture_failed") }
    static var insertImage: String { tr("image.insert") }
}

// The Mac eraser — ledger row 21.
extension L10n {
    static var inkEraser: String { tr("ink.eraser") }
}

// A password on an exported PDF — row 27.
extension L10n {
    static var exportPasswordTitle: String { tr("export.password.title") }
    static var exportPasswordField: String { tr("export.password.field") }
    static var exportPasswordFooter: String { tr("export.password.footer") }
    static var exportPasswordNotRepresentable: String { tr("export.password.notRepresentable") }
    static var exportPasswordNotSupported: String { tr("export.password.notSupported") }
    static var exportPasswordEmpty: String { tr("export.password.empty") }
    static var exportPasswordTruncated: String { tr("export.password.truncated") }
}

// Exporting as plain text or Word — row 35 follow-up.
extension L10n {
    static var exportWordsOnlyNote: String { tr("export.wordsOnlyNote") }
    static var exportNoTextToExport: String { tr("export.noTextToExport") }
}

// Choosing which languages text recognition reads in — F4.
extension L10n {
    static var settingsRecognitionLanguages: String { tr("settings.recognitionLanguages") }
    static var settingsRecognitionLanguagesFooter: String { tr("settings.recognitionLanguagesFooter") }
    static func settingsRecognitionUnavailable(_ names: String) -> String {
        tr("settings.recognitionUnavailable", names)
    }
}

// Resizing a mark by a corner — ledger row 21.
extension L10n {
    static var resizeObject: String { tr("object.resize") }
}

// Changing a text box already on a page — ledger row 21.
extension L10n {
    static var textBoxSave: String { tr("textBox.save") }
    static var textBoxEdit: String { tr("textBox.edit") }
}

// Removing a text box or an image — ledger row 21.
extension L10n {
    static var markupImage: String { tr("markup.image") }
}

// The Mac lasso — ledger row 21.
extension L10n {
    static var inkLasso: String { tr("ink.lasso") }
    static var moveInk: String { tr("ink.move") }
    static func inkSelectionCount(_ count: Int) -> String { plural("ink.selectionCount", count) }
}

// Import destination prompt, shared by iPhone, iPad and Mac.
extension L10n {
    static var importLocationTitle: String { tr("import.location.title") }
    static var importLocationHome: String { tr("import.location.home") }
    static var importLocationSave: String { tr("import.location.save") }
}

// Reusable handwritten signatures — visual ink, no certificate claims.
extension L10n {
    static var signatureTitle: String { tr("signature.title") }
    static var signatureSaved: String { tr("signature.saved") }
    static var signatureNew: String { tr("signature.new") }
    static var signatureDraw: String { tr("signature.draw") }
    static var signatureDrawHint: String { tr("signature.drawHint") }
    static var signatureNameRequired: String { tr("signature.nameRequired") }
    static var signatureName: String { tr("signature.name") }
    static var signatureClear: String { tr("signature.clear") }
    static var signatureSave: String { tr("signature.save") }
    static var signaturePlace: String { tr("signature.place") }
    static var signatureHelp: String { tr("signature.help") }
    static var signaturePosition: String { tr("signature.position") }
    static var signatureHorizontal: String { tr("signature.horizontal") }
    static var signatureVertical: String { tr("signature.vertical") }
    static var signatureWidth: String { tr("signature.width") }
    static var signatureHeight: String { tr("signature.height") }
    static var signaturePreview: String { tr("signature.preview") }
    static var signatureDrag: String { tr("signature.drag") }
    static var signatureSaveFailed: String { tr("signature.saveFailed") }
    static var signatureRefreshPreview: String { tr("signature.refreshPreview") }
    static var signatureNoSaved: String { tr("signature.noSaved") }
    static func signatureDeleteNamed(_ name: String) -> String { tr("signature.deleteNamed", name) }
}

// Lasso interaction guidance.
extension L10n {
    static var lassoInkHint: String { tr("ink.lasso.help") }
    static var selectionMode: String { tr("selection.mode") }
    static var selectionFreehand: String { tr("selection.freehand") }
    static var selectionRectangle: String { tr("selection.rectangle") }
    static var selectionEdit: String { tr("selection.edit") }
}

// Notes Editor toolbar redesign (Claude, 2026-11-12).
extension L10n {
    static var toolShapes: String { tr("editorTools.shapes") }
    static var toolText: String { tr("editorTools.text") }
    static var toolImage: String { tr("editorTools.image") }
    static var toolSticker: String { tr("editorTools.sticker") }
    static var toolInsert: String { tr("editorTools.insert") }
    static var toolRestoreDefaults: String { tr("editorTools.restoreDefaults") }
    static func toolDecrease(_ name: String) -> String { tr("editorTools.decrease", name) }
    static func toolIncrease(_ name: String) -> String { tr("editorTools.increase", name) }
    static func toolPointsShort(_ value: String) -> String { tr("editorTools.pointsShort", value) }
    static var toolAdvanced: String { tr("editorTools.advanced") }
    static var toolFingerDetail: String { tr("editorTools.fingerDetail") }
    static var colorBlack: String { tr("tools.color.black") }
    static var colorSky: String { tr("tools.color.sky") }
    static var colorPink: String { tr("tools.color.pink") }
    static var colorRecent: String { tr("tools.color.recent") }
    static var colorFavorites: String { tr("tools.color.favorites") }
    static var colorAddFavorite: String { tr("tools.color.addFavorite") }
    static var colorRemoveFavorite: String { tr("tools.color.removeFavorite") }
    static func colorCustomNumbered(_ number: Int) -> String { tr("tools.color.customNumbered", number) }
    static var penFountain: String { tr("pen.fountain") }
    static var penBallpoint: String { tr("pen.ballpoint") }
    static var penGel: String { tr("pen.gel") }
    static var penPencil: String { tr("pen.pencil") }
    static var penMarker: String { tr("pen.marker") }
    static var penBrush: String { tr("pen.brush") }
    static var penType: String { tr("pen.type") }
    static var penStrokeAndSize: String { tr("pen.strokeAndSize") }
    static var penPressure: String { tr("pen.pressure") }
    static var penPressureDetail: String { tr("pen.pressure.detail") }
    static var penSnap: String { tr("pen.snap") }
    static var penSnapDetail: String { tr("pen.snap.detail") }
    static var penSmoothing: String { tr("pen.smoothing") }
    static var highlighterStandard: String { tr("highlighter.standard") }
    static var highlighterFlat: String { tr("highlighter.flat") }
    static var highlighterUnderline: String { tr("highlighter.underline") }
    static var highlighterMarker: String { tr("highlighter.marker") }
    static var highlighterStraight: String { tr("highlighter.straight") }
    static var highlighterStyle: String { tr("highlighter.style") }
    static var highlighterPreview: String { tr("highlighter.preview") }
    static var highlighterSample: String { tr("highlighter.sample") }
    static var highlighterReadable: String { tr("highlighter.readable") }
    static var highlighterStrength: String { tr("highlighter.strength") }
    static var highlighterSnapToText: String { tr("highlighter.snapToText") }
    static var highlighterSnapToTextDetail: String { tr("highlighter.snapToText.detail") }
    static var eraserTarget: String { tr("eraser.target") }
    static var eraserTargetAll: String { tr("eraser.target.all") }
    static var eraserTargetHandwriting: String { tr("eraser.target.handwriting") }
    static var eraserTargetHighlights: String { tr("eraser.target.highlights") }
    static var eraserProtected: String { tr("eraser.protected") }
    static var lassoHandwriting: String { tr("lasso.handwriting") }
    static var lassoHighlights: String { tr("lasso.highlights") }
    static var lassoTextBoxes: String { tr("lasso.textBoxes") }
    static var lassoImages: String { tr("lasso.images") }
    static var lassoContent: String { tr("lasso.content") }
    static var lassoActions: String { tr("lasso.actions") }
    static var lassoActionsDetail: String { tr("lasso.actions.detail") }
    static var shapeRoundedRectangle: String { tr("shape.roundedRectangle") }
    static var shapeTriangle: String { tr("shape.triangle") }
    static var shapeDiamond: String { tr("shape.diamond") }
    static var shapePentagon: String { tr("shape.pentagon") }
    static var shapeHexagon: String { tr("shape.hexagon") }
    static var shapeSpeechBubble: String { tr("shape.speechBubble") }
    static var shapeDragToDraw: String { tr("shape.dragToDraw") }
    static var shapeLockAspect: String { tr("shape.lockAspect") }
    static var shapeLockAspectDetail: String { tr("shape.lockAspect.detail") }
    static var textSelectedBox: String { tr("textTool.selected") }
    static var textNewBoxes: String { tr("textTool.new") }
    static var textPlace: String { tr("textTool.place") }
    static var imageOnPage: String { tr("imageTool.onPage") }
    static var imageOnPageDetail: String { tr("imageTool.onPage.detail") }
    static var stickerAll: String { tr("sticker.all") }
    static var stickerSearch: String { tr("sticker.search") }
    static var stickerNoFavorites: String { tr("sticker.noFavorites") }
    static var stickerNoMatches: String { tr("sticker.noMatches") }
    static var stickerHint: String { tr("sticker.hint") }
    static var stickerProductivity: String { tr("sticker.category.productivity") }
    static var stickerPlanning: String { tr("sticker.category.planning") }
    static var stickerEducation: String { tr("sticker.category.education") }
    static var stickerDecorative: String { tr("sticker.category.decorative") }
    static var stickerCheck: String { tr("sticker.name.check") }
    static var stickerStar: String { tr("sticker.name.star") }
    static var stickerFlag: String { tr("sticker.name.flag") }
    static var stickerImportant: String { tr("sticker.name.important") }
    static var stickerIdea: String { tr("sticker.name.idea") }
    static var stickerCalendar: String { tr("sticker.name.calendar") }
    static var stickerClock: String { tr("sticker.name.clock") }
    static var stickerTarget: String { tr("sticker.name.target") }
    static var stickerNote: String { tr("sticker.name.note") }
    static var stickerBook: String { tr("sticker.name.book") }
    static var stickerPencil: String { tr("sticker.name.pencil") }
    static var stickerGrade: String { tr("sticker.name.grade") }
    static var stickerHeart: String { tr("sticker.name.heart") }
    static var stickerArrow: String { tr("sticker.name.arrow") }
    static var stickerRibbon: String { tr("sticker.name.ribbon") }
    static var stickerBubble: String { tr("sticker.name.bubble") }
    static var insertPageDetail: String { tr("insert.page.detail") }
    static var insertOnPage: String { tr("insert.onPage") }
    static var insertDateTime: String { tr("insert.dateTime") }
    static var insertDivider: String { tr("insert.divider") }
    static var insertFromFiles: String { tr("insert.fromFiles") }
    static var insertDuplicatePage: String { tr("insert.duplicatePage") }
    static var insertOrganize: String { tr("insert.organize") }
}

// Document Utilities sidebar and viewport bar (Claude, 2026-11-12).
extension L10n {
    static var documentUtilities: String { tr("utilities.title") }
    static var documentUtilitiesSubtitle: String { tr("utilities.subtitle") }
    static var documentUtilitiesClose: String { tr("utilities.close") }
    static func documentUtilitiesPages(_ count: Int) -> String { tr("utilities.pages", count) }
    static var sectionExpanded: String { tr("utilities.expanded") }
    static var sectionCollapsed: String { tr("utilities.collapsed") }
    static var documentUtilitiesAddPage: String { tr("utilities.addPage") }
    static var displaySettings: String { tr("display.title") }
    static var displayZoom: String { tr("display.zoom") }
    static var displayFitWidth: String { tr("display.fitWidth") }
    static var displayDrawingMode: String { tr("display.drawingMode") }
}

// Find in document (Claude, 2026-11-12).
extension L10n {
    static var find: String { tr("find.title") }
    static var findMenu: String { tr("find.menu") }
    static var findPlaceholder: String { tr("find.placeholder") }
    static var findNext: String { tr("find.next") }
    static var findPrevious: String { tr("find.previous") }
    static var findClear: String { tr("find.clear") }
    static func findCount(_ number: Int, of total: Int) -> String { tr("find.count", number, total) }
    static var findNoResults: String { tr("find.noResults") }
    static var findNoText: String { tr("find.noText") }
    static var findNoTextDetail: String { tr("find.noText.detail") }
    static var findSearching: String { tr("find.searching") }
    static var findOnPage: String { tr("find.onPage") }
}

// Select and copy text (Claude, 2026-11-12).
extension L10n {
    static var textSelection: String { tr("textSelection.title") }
    static var textCopied: String { tr("textSelection.copied") }
}

// Links and Go to Page (Claude, 2026-11-12).
extension L10n {
    static var linkOpenTitle: String { tr("link.open.title") }
    static var linkOpen: String { tr("link.open") }
    static var linkCopy: String { tr("link.copy") }
    static func linkToAddress(_ address: String) -> String { tr("link.address", address) }
    static func linkToPage(_ number: Int) -> String { tr("link.page", number) }
    static var goToPage: String { tr("goToPage.title") }
    static func goToPageMessage(_ count: Int) -> String { tr("goToPage.message", count) }
    static var goToPageField: String { tr("goToPage.field") }
    static var goToPageGo: String { tr("goToPage.go") }
}

// Print (Claude, 2026-11-13).
extension L10n {
    static var printMenu: String { tr("print.menu") }
    static var printPreparing: String { tr("print.preparing") }
    static var printFailed: String { tr("print.failed") }
}

// Night mode (Claude, 2026-11-13).
extension L10n {
    static var displayReading: String { tr("display.reading") }
    static var nightMode: String { tr("display.nightMode") }
    static var nightModeDetail: String { tr("display.nightMode.detail") }
}

// Bookmarks (Claude, 2026-11-13).
extension L10n {
    static var bookmarkAdd: String { tr("bookmark.add") }
    static var bookmarkRemove: String { tr("bookmark.remove") }
    static var bookmarkList: String { tr("bookmark.list") }
    static var bookmarkTitle: String { tr("bookmark.title") }
    static var bookmarkEmpty: String { tr("bookmark.empty") }
    static var bookmarkEmptyDetail: String { tr("bookmark.empty.detail") }
    static var bookmarkRenameTitle: String { tr("bookmark.rename.title") }
    static var bookmarkRenameMessage: String { tr("bookmark.rename.message") }
    static func bookmarkPage(_ number: Int) -> String { tr("bookmark.page", number) }
    static func bookmarkActions(_ name: String) -> String { tr("bookmark.actions", name) }
    static var bookmarkMarked: String { tr("bookmark.marked") }
    static var bookmarkFailed: String { tr("bookmark.failed") }
    static var bookmarkLocalOnly: String { tr("bookmark.localOnly") }
}

// Restricted PDFs (Claude, 2026-11-13).
extension L10n {
    static var restrictedCopyRefused: String { tr("restricted.copy.refused") }
    static var restrictedExportNote: String { tr("restricted.export.note") }
    static var restrictedExportRefused: String { tr("restricted.export.refused") }
    static var restrictedPrintRefused: String { tr("restricted.print.refused") }
}

// iCloud sync (Claude, 2026-11-13).
extension L10n {
    static var syncStatusSavedLocally: String { tr("sync.status.savedLocally") }
    static var syncStatusWaiting: String { tr("sync.status.waiting") }
    static var syncStatusSyncing: String { tr("sync.status.syncing") }
    static var syncStatusUpToDate: String { tr("sync.status.upToDate") }
    static var syncStatusOffline: String { tr("sync.status.offline") }
    static var syncStatusCloudUnavailable: String { tr("sync.status.cloudUnavailable") }
    static var syncStatusConflict: String { tr("sync.status.conflict") }
    static var syncStatusNeedsAttention: String { tr("sync.status.needsAttention") }
    static var syncSettingsTitle: String { tr("sync.settings.title") }
    static var syncSettingsToggle: String { tr("sync.settings.toggle") }
    static var syncSettingsFooter: String { tr("sync.settings.footer") }
    static var syncSettingsNotConfigured: String { tr("sync.settings.notConfigured", Brand.displayName) }
    static var syncSettingsAccount: String { tr("sync.settings.account") }
    static var syncAccountReady: String { tr("sync.account.ready") }
    static var syncAccountChecking: String { tr("sync.account.checking") }
    static var syncAccountNoAccount: String { tr("sync.account.noAccount") }
    static var syncAccountRestricted: String { tr("sync.account.restricted") }
    static var syncAccountTemporarilyUnavailable: String { tr("sync.account.temporarilyUnavailable") }
    static var syncAccountUnknown: String { tr("sync.account.unknown") }
    static var syncAccountChangedTitle: String { tr("sync.account.changed.title") }
    static var syncAccountChangedMessage: String { tr("sync.account.changed.message") }
    static var syncAccountUseCurrent: String { tr("sync.account.useCurrent") }
    static var syncAccountUseCurrentConfirm: String { tr("sync.account.useCurrent.confirm") }
    static var syncAccountStop: String { tr("sync.account.stop") }
    static var syncSettingsStatus: String { tr("sync.settings.status") }
    static var syncSettingsLastSynced: String { tr("sync.settings.lastSynced") }
    static var syncSettingsNever: String { tr("sync.settings.never") }
    static var syncSettingsPending: String { tr("sync.settings.pending") }
    static var syncSettingsPendingUploads: String { tr("sync.settings.pendingUploads") }
    static var syncSettingsPendingDownloads: String { tr("sync.settings.pendingDownloads") }
    static var syncSettingsSyncNow: String { tr("sync.settings.syncNow") }
    static var syncSettingsOnDemand: String { tr("sync.settings.onDemand") }
    static var syncSettingsOnDemandFooter: String { tr("sync.settings.onDemand.footer") }
    static var syncIssueQuota: String { tr("sync.issue.quota") }
    static var syncIssueCloudDeleted: String { tr("sync.issue.cloudDeleted", Brand.displayName) }
    static var syncIssueNewerApp: String { tr("sync.issue.newerApp", Brand.displayName) }
    static var syncIssueGeneral: String { tr("sync.issue.general") }
    static var syncConflictTitle: String { tr("sync.conflict.title") }
    static func syncConflictPage(_ name: String) -> String { tr("sync.conflict.page", name) }
    static func syncConflictObject(_ name: String) -> String { tr("sync.conflict.object", name) }
    static var syncConflictSomeDocument: String { tr("sync.conflict.someDocument") }
    static var syncConflictKeepBoth: String { tr("sync.conflict.keepBoth") }
    static var syncConflictRemoveCopy: String { tr("sync.conflict.removeCopy") }
    static var syncTroubleTitle: String { tr("sync.trouble.title") }
    static var syncTroubleText: String { tr("sync.trouble.text") }
    static var syncDeleteCloud: String { tr("sync.deleteCloud") }
    static var syncDeleteCloudTitle: String { tr("sync.deleteCloud.title", Brand.displayName) }
    static var syncDeleteCloudMessage: String { tr("sync.deleteCloud.message") }
    static var syncDeleteCloudConfirm: String { tr("sync.deleteCloud.confirm") }
    static var syncItemDownload: String { tr("sync.item.download") }
    static var syncItemRemoveDownload: String { tr("sync.item.removeDownload") }
    static var syncItemCloudOnly: String { tr("sync.item.cloudOnly") }
    static var syncEnableFailed: String { tr("sync.enableFailed") }
    static var syncActionFailed: String { tr("sync.actionFailed") }

    // Home and scanner redesign
    static var homeSubtitle: String { tr("home.subtitle") }
    static var homeNewNote: String { tr("home.newNote") }
    static var homeImportFile: String { tr("home.importFile") }
    static var homeRecentDocuments: String { tr("home.recentDocuments") }
    static var homeFiles: String { tr("home.files") }
    static var homeSyncNotSetUp: String { tr("home.sync.notSetUp") }
    static var foldersEmpty: String { tr("folders.empty") }
    static var foldersEmptyDetail: String { tr("folders.emptyDetail") }
    static var scannerKind: String { tr("scanner.kind") }
    static var scannerKindDocument: String { tr("scanner.kind.document") }
    static var scannerKindPhoto: String { tr("scanner.kind.photo") }
    static var scannerPages: String { tr("scanner.pages") }
    static var scannerTools: String { tr("scanner.tools") }
}

// Read aloud (Claude, 2026-11-14).
extension L10n {
    static var readAloudMenu: String { tr("readAloud.menu") }
    static var readAloudStop: String { tr("readAloud.stop") }
    static var readAloudPause: String { tr("readAloud.pause") }
    static var readAloudResume: String { tr("readAloud.resume") }
    static var readAloudSpeed: String { tr("readAloud.speed") }
    static var readAloudNoText: String { tr("readAloud.noText") }
    static func readAloudStatus(_ number: Int, of total: Int) -> String { tr("readAloud.status", number, total) }
}

// Document Tools, Option 6 (Claude, 2026-11-14).
extension L10n {
    static var toolsEditPDF: String { tr("tools2.editPDF") }
    static var toolsAnnotate: String { tr("tools2.annotate") }
    static var toolsInsert: String { tr("tools2.insert") }
    static var toolsProcess: String { tr("tools2.process") }
    static var toolsExportSave: String { tr("tools2.exportSave") }
    static var toolsOrganize: String { tr("tools2.organize") }
    static var toolsHighlightText: String { tr("tools2.highlightText") }
    static var toolsUnderlineText: String { tr("tools2.underlineText") }
    static var toolsStrikeText: String { tr("tools2.strikeText") }
    static var toolsDraw: String { tr("tools2.draw") }
    static var toolsReplacePage: String { tr("tools2.replacePage") }
    static var toolsSplit: String { tr("tools2.split") }
    static var toolsCompress: String { tr("tools2.compress") }
    static var toolsConvert: String { tr("tools2.convert") }
    static var toolsFillForm: String { tr("tools2.fillForm") }
    static var splitDoneTitle: String { tr("tools2.splitDone.title") }
    static func splitDoneMessage(_ count: Int) -> String { tr("tools2.splitDone.message", count) }
    static var compressTitle: String { tr("compress.title") }
    static var compressLevel: String { tr("compress.level") }
    static var compressLight: String { tr("compress.light") }
    static var compressStrong: String { tr("compress.strong") }
    static var compressSmallest: String { tr("compress.smallest") }
    static func compressCurrentSize(_ size: String) -> String { tr("compress.current", size) }
    static var compressRule: String { tr("compress.rule") }
    static var compressAction: String { tr("compress.action") }
    static func compressResult(_ before: String, _ after: String, _ saved: String) -> String { tr("compress.result", before, after, saved) }
    static var compressNoGain: String { tr("compress.noGain") }
    static var pagePrevious: String { tr("pageNav.previous") }
    static var pageNext: String { tr("pageNav.next") }
    static func pageCounter(_ page: Int, _ count: Int) -> String { tr("pageNav.counter", page, count) }
    static var documentUtilitiesToggleHelp: String { tr("utilities.toggleHelp") }
    static var drawerExpand: String { tr("drawer.expand") }
    static var drawerCollapse: String { tr("drawer.collapse") }
}

// Two-page view (Claude, 2026-11-14).
extension L10n {
    static var twoPages: String { tr("display.twoPages") }
    static var twoPagesDetail: String { tr("display.twoPages.detail") }
    static var twoPagesCover: String { tr("display.twoPages.cover") }
    static var twoPagesCoverDetail: String { tr("display.twoPages.cover.detail") }
}

// Approved OCR and Signature panels.
extension L10n {
    static var ocrIncomplete: String { tr("ocr.panel.incomplete") }
    static var ocrLanguages: String { tr("ocr.panel.languages") }
    static var ocrLanguagesHelp: String { tr("ocr.panel.languagesHelp") }
    static var ocrMoreLanguages: String { tr("ocr.panel.moreLanguages") }
    static var ocrChooseLanguage: String { tr("ocr.panel.chooseLanguage") }
    static var ocrRangeHint: String { tr("ocr.panel.rangeHint") }
    static var ocrInvalidRange: String { tr("ocr.panel.invalidRange") }
    static var ocrOutputHelp: String { tr("ocr.panel.outputHelp") }
    static var signatureSaveThenPlace: String { tr("signature.saveThenPlace") }
    static func ocrSelected(_ count: Int) -> String { tr("ocr.panel.selected", count) }
    static func ocrStart(_ count: Int) -> String { tr("ocr.panel.start", pageCount(count)) }
    static func ocrCompleted(_ count: Int, _ total: Int) -> String { tr("ocr.panel.completed", count, total) }
}

// Spacious Home, owner-approved sample.
extension L10n {
    static var homeSearchPlaceholder: String { tr("home.searchLibrary") }
    static var homeMyFolders: String { tr("home.myFolders") }
}

// Scan Studio functionality: presets and Cleanup that change the page, and batch page actions.
extension L10n {
    static var scannerBefore: String { tr("scanner.cleanup.before") }
    static var scannerAfter: String { tr("scanner.cleanup.after") }
    static var scannerCompare: String { tr("scanner.cleanup.compare") }
    static var scannerRecommended: String { tr("scanner.cleanup.recommended") }
    static var scannerApplyToSelected: String { tr("scanner.cleanup.applySelected") }
    static func scannerSelectedCount(_ count: Int) -> String { tr("scanner.batch.selected", count) }
    static func scannerDeletePagesTitle(_ count: Int) -> String { tr("scanner.batch.deleteTitle", count) }
    static var scannerDeletePagesMessage: String { tr("scanner.batch.deleteMessage") }
}

// Scan Studio capture modes: a card's two sides, and the scanner's defaults.
extension L10n {
    static var scannerCardFront: String { tr("scanner.card.front") }
    static var scannerCardBack: String { tr("scanner.card.back") }
    static var scannerCardFrontSaved: String { tr("scanner.card.frontSaved") }
    static var scannerCardBackPrompt: String { tr("scanner.card.backPrompt") }
    static var scannerCardScanBack: String { tr("scanner.card.scanBack") }
    static var scannerCardContinue: String { tr("scanner.card.continue") }
    static var scannerSettings: String { tr("scanner.settings") }
    static var scannerSettingsDefaultMode: String { tr("scanner.settings.defaultMode") }
    static var scannerSettingsDefaultFilter: String { tr("scanner.settings.defaultFilter") }
    static var scannerSettingsAutoOnEntry: String { tr("scanner.settings.autoOnEntry") }
    static var scannerSettingsNote: String { tr("scanner.settings.note") }
}

// Word page images: the second Word layout, each page as a picture.
extension L10n {
    static var exportDocxLayout: String { tr("export.docxLayout") }
    static var exportDocxLayoutText: String { tr("export.docxLayout.text") }
    static var exportDocxLayoutTextDetail: String { tr("export.docxLayout.text.detail") }
    static var exportDocxLayoutImages: String { tr("export.docxLayout.images") }
    static var exportDocxLayoutImagesDetail: String { tr("export.docxLayout.images.detail") }
    static var exportDocxImagesNote: String { tr("export.docxImagesNote") }
}

// Export watermark: Confidential, Draft, Approved and Custom marks drawn into an export.
extension L10n {
    static var exportWatermarkTitle: String { tr("export.watermark.title") }
    static var exportWatermarkNone: String { tr("export.watermark.none") }
    static var exportWatermarkConfidential: String { tr("export.watermark.preset.confidential") }
    static var exportWatermarkDraft: String { tr("export.watermark.preset.draft") }
    static var exportWatermarkApproved: String { tr("export.watermark.preset.approved") }
    static var exportWatermarkCustom: String { tr("export.watermark.preset.custom") }
    static var exportWatermarkWordConfidential: String { tr("export.watermark.word.confidential") }
    static var exportWatermarkWordDraft: String { tr("export.watermark.word.draft") }
    static var exportWatermarkWordApproved: String { tr("export.watermark.word.approved") }
    static var exportWatermarkText: String { tr("export.watermark.text") }
    static var exportWatermarkTextPlaceholder: String { tr("export.watermark.text.placeholder") }
    static var exportWatermarkTextMissing: String { tr("export.watermark.text.missing") }
    static var exportWatermarkTextUndrawable: String { tr("export.watermark.text.undrawable") }
    static var exportWatermarkPlacementBottomLeft: String { tr("export.watermark.placement.bottomLeft") }
    static var exportWatermarkMark: String { tr("export.watermark.mark", Brand.displayName) }
    static var exportWatermarkMarkFree: String { tr("export.watermark.mark.free", Brand.displayName) }
    static var exportWatermarkMarkPro: String { tr("export.watermark.mark.pro", Brand.displayName) }
    static var exportWatermarkPreviewMarkOnly: String { tr("export.watermark.preview.markOnly", Brand.displayName) }
    static func exportWatermarkPreviewValueWithMark(_ preset: String, _ placement: String, _ opacity: String) -> String {
        tr("export.watermark.preview.valueWithMark", preset, placement, opacity, Brand.displayName)
    }
    static var proFeatureRemoveWatermark: String { tr("pro.feature.removeWatermark", Brand.displayName) }
    static var exportWatermarkFreeRedrawNote: String { tr("export.watermark.freeRedrawNote", Brand.displayName) }
    static var exportWatermarkCompressNoGainMarked: String { tr("export.watermark.compressNoGainMarked", Brand.displayName) }
    static var exportWatermarkPlacement: String { tr("export.watermark.placement") }
    static var exportWatermarkPlacementCenter: String { tr("export.watermark.placement.center") }
    static var exportWatermarkPlacementTopRight: String { tr("export.watermark.placement.topRight") }
    static var exportWatermarkPlacementBottomRight: String { tr("export.watermark.placement.bottomRight") }
    static var exportWatermarkPlacementTiled: String { tr("export.watermark.placement.tiled") }
    static var exportWatermarkOpacity: String { tr("export.watermark.opacity") }
    static var exportWatermarkRotation: String { tr("export.watermark.rotation") }
    static var exportWatermarkIncludeDate: String { tr("export.watermark.includeDate") }
    static var exportWatermarkPreview: String { tr("export.watermark.preview") }
    static func exportWatermarkPreviewValue(_ preset: String, _ placement: String, _ opacity: String) -> String {
        tr("export.watermark.preview.value", preset, placement, opacity)
    }
    static var exportWatermarkNote: String { tr("export.watermark.note") }
    static var exportWatermarkPDFNote: String { tr("export.watermark.pdfNote") }
    static var exportWatermarkNotSupported: String { tr("export.watermark.notSupported") }
}

// OCR correction: correcting recognized text, and the page's recognition state.
extension L10n {
    static var ocrCorrectSection: String { tr("ocr.correct.section") }
    static var ocrCorrectOpen: String { tr("ocr.correct.open") }
    static var ocrCorrectTitle: String { tr("ocr.correct.title") }
    /// The undo menu's name for a correction: the same words as the title.
    static var ocrCorrectionAction: String { tr("ocr.correct.title") }
    static var ocrCorrectHelp: String { tr("ocr.correct.help") }
    static func ocrCorrectLine(_ number: Int) -> String { tr("ocr.correct.line", number) }
    static var ocrCorrectUnsure: String { tr("ocr.correct.unsure") }
    static var ocrCorrectChanged: String { tr("ocr.correct.changed") }
    static func ocrCorrectChangedCount(_ count: Int) -> String { tr("ocr.correct.changedCount", count) }
    static var ocrCorrectSave: String { tr("ocr.correct.save") }
    static var ocrCorrectDiscardTitle: String { tr("ocr.correct.discardTitle") }
    static var ocrCorrectDiscard: String { tr("ocr.correct.discard") }
    static var ocrCorrectKeepEditing: String { tr("ocr.correct.keepEditing") }
    static var ocrCorrectionChanged: String { tr("ocr.correct.changedElsewhere") }
    static var ocrCorrectionHistoryChanged: String { tr("ocr.correct.historyChanged") }
    static func ocrStatusNone(_ page: Int) -> String { tr("ocr.status.none", page) }
    static func ocrStatusFailed(_ page: Int) -> String { tr("ocr.status.failed", page) }
    static func ocrStatusOwnText(_ page: Int) -> String { tr("ocr.status.ownText", page) }
    static func ocrStatusRecognized(_ page: Int) -> String { tr("ocr.status.recognized", page) }
    static func ocrStatusCorrected(_ page: Int) -> String { tr("ocr.status.corrected", page) }
    static var ocrReplacesCorrections: String { tr("ocr.replacesCorrections") }
}

// Search snippets: which page a search matched, and the words around it.
extension L10n {
    static var searchInPages: String { tr("search.inPages") }
    static func searchHitPlace(_ document: String, _ page: Int) -> String { tr("search.hitPlace", document, page) }
    static var searchHitHint: String { tr("search.hitHint") }
    static var searchSourceRecognized: String { tr("search.source.recognized") }
    static var searchSourcePageText: String { tr("search.source.pageText") }
    static var searchSourceTyped: String { tr("search.source.typed") }
    static var searchSourceTitle: String { tr("search.source.title") }
}

// Scanner capture feedback: what the camera sees, while it is pointed.
extension L10n {
    static var scannerFeedbackLighting: String { tr("scanner.feedback.lighting") }
    static var scannerFeedbackMoveBack: String { tr("scanner.feedback.moveBack") }
    static var scannerFeedbackMoveCloser: String { tr("scanner.feedback.moveCloser") }
    static var scannerFeedbackHoldSteady: String { tr("scanner.feedback.holdSteady") }
    static var scannerFeedbackReady: String { tr("scanner.feedback.ready") }
}

// Redact screen: marking areas, the review before applying, and what it cannot do.
extension L10n {
    static var redactTitle: String { tr("redact.title") }
    static var redactPageLabel: String { tr("redact.pageLabel") }
    static var redactHint: String { tr("redact.hint") }
    static func redactAreaCount(_ count: Int) -> String { tr("redact.count", count) }
    static var redactRemoveLast: String { tr("redact.removeLast") }
    static var redactReview: String { tr("redact.review") }
    static var redactPreparing: String { tr("redact.preparing") }
    static var redactPreviewLabel: String { tr("redact.previewLabel") }
    static var redactWarningFlatten: String { tr("redact.warning.flatten") }
    static var redactWarningWholePage: String { tr("redact.warning.wholePage") }
    static var redactWarningUndo: String { tr("redact.warning.undo") }
    static func redactRemoveMarks(_ count: Int) -> String { tr("redact.marks", count) }
    static var redactMarksStay: String { tr("redact.marksStay") }
    static var redactCommentsKept: String { tr("redact.commentsKept") }
    static var redactShared: String { tr("redact.shared") }
    static var redactSync: String { tr("redact.sync") }
    static var redactRestricted: String { tr("redact.restricted") }
    static var redactBack: String { tr("redact.back") }
    static var redactApply: String { tr("redact.apply") }
    static var redactApplying: String { tr("redact.applying") }
    static var redactDoneShared: String { tr("redact.doneShared") }
    static var redactFailed: String { tr("redact.failed") }

    // MARK: Pro tools

    static var proFeatureCompress: String { tr("pro.feature.compress") }
    static var proFeatureRedact: String { tr("pro.feature.redact") }

    // MARK: Compare

    static var compareTitle: String { tr("compare.title") }
    static var compareOriginal: String { tr("compare.original") }
    static var compareNew: String { tr("compare.new") }
    static var compareChoose: String { tr("compare.choose") }
    static var compareChooseTitle: String { tr("compare.chooseTitle") }
    static var compareNoDocuments: String { tr("compare.noDocuments") }
    static var compareSwap: String { tr("compare.swap") }
    static var compareComparing: String { tr("compare.comparing") }
    static var compareModeSideBySide: String { tr("compare.mode.sideBySide") }
    static var compareModeOverlay: String { tr("compare.mode.overlay") }
    static var compareModeText: String { tr("compare.mode.text") }
    static func comparePosition(_ value0: Int, _ value1: Int) -> String { tr("compare.position", value0, value1) }
    static func comparePages(_ value0: Int, _ value1: Int) -> String { tr("compare.pages", value0, value1) }
    static func compareOnlyOriginal(_ value0: Int) -> String { tr("compare.onlyOriginal", value0) }
    static func compareOnlyNew(_ value0: Int) -> String { tr("compare.onlyNew", value0) }
    static var compareKindSame: String { tr("compare.kind.same") }
    static var compareKindChanged: String { tr("compare.kind.changed") }
    static var compareKindAdded: String { tr("compare.kind.added") }
    static var compareKindRemoved: String { tr("compare.kind.removed") }
    static var compareMoved: String { tr("compare.moved") }
    static func compareSummaryText(_ value0: Int) -> String { tr("compare.summary.text", value0) }
    static func compareSummaryPicture(_ value0: Int) -> String { tr("compare.summary.picture", value0) }
    static func compareSummaryPages(_ value0: Int, _ value1: Int, _ value2: Int) -> String { tr("compare.summary.pages", value0, value1, value2) }
    static var compareIdentical: String { tr("compare.identical") }
    static var compareIdenticalByLook: String { tr("compare.identicalByLook") }
    static var compareMethodText: String { tr("compare.method.text") }
    static var compareMethodRecognized: String { tr("compare.method.recognized") }
    static var compareMethodPictureBoth: String { tr("compare.method.pictureBoth") }
    static var compareMethodPictureOld: String { tr("compare.method.pictureOld") }
    static var compareMethodPictureNew: String { tr("compare.method.pictureNew") }
    static var compareSizesDiffer: String { tr("compare.sizesDiffer") }
    static var compareLegendRemoved: String { tr("compare.legend.removed") }
    static var compareLegendAdded: String { tr("compare.legend.added") }
    static var compareLegendPicture: String { tr("compare.legend.picture") }
    static var compareMissing: String { tr("compare.missing") }
    static func compareRemovedWords(_ value0: String) -> String { tr("compare.removedWords", value0) }
    static func compareAddedWords(_ value0: String) -> String { tr("compare.addedWords", value0) }
    static var compareNoTextChanges: String { tr("compare.noTextChanges") }
    static var comparePrevious: String { tr("compare.previous") }
    static var compareNext: String { tr("compare.next") }
    static var compareLimits: String { tr("compare.limits") }
    static var compareFailed: String { tr("compare.failed") }

    // MARK: Stationery

    static var notebookDotted: String { tr("notebook.dotted") }
    static var notebookCornell: String { tr("notebook.cornell") }
    static var notebookChecklist: String { tr("notebook.checklist") }
    static var notebookMeeting: String { tr("notebook.meeting") }
    static var notebookPlanner: String { tr("notebook.planner") }
    static var notebookForm: String { tr("notebook.form") }
    static var templateMeetingTitle: String { tr("template.meetingTitle") }
    static var templateDate: String { tr("template.date") }
    static var templateAttendees: String { tr("template.attendees") }
    static var templateNotes: String { tr("template.notes") }
    static var templateActionItems: String { tr("template.actionItems") }
    static var templateWeekOf: String { tr("template.weekOf") }
}
