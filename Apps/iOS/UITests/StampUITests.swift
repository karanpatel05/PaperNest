import XCTest
import ImageIO
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore

/// Text and image stamps from Document Tools: Approved placed in a corner,
/// undone, redone and read back from disk after a relaunch; one's own words
/// kept and offered again; a saved image placed the same way; French and
/// Spanish; and a free user asked to upgrade with nothing placed.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class StampUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func seed() async throws -> (URL, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-stamps-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let invoice = try store.assets.store(SyntheticDocuments.textPDF(pages: ["Invoice 1042 for three hours of work"]),
                                             kind: .pdf, originalFilename: "Invoice.pdf")
        let item = try await store.createItem(kind: .document, name: "Invoice", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(invoice.id, index: 0)),
        ], assets: [invoice])
        return (directory, store, item.id)
    }

    private func launch(_ directory: URL, language: String = "en", free: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Invoice", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language]
        if free {
            app.launchArguments += ["-PaperNestDebugProProducts", "test.papernest.pro.monthly,test.papernest.pro.yearly"]
        }
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-stamp-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// Opens the Text Stamp sheet from Document Tools.
    private func openStamps(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard app.descendants(matching: .any)["document-page-image"].firstMatch.waitForExistence(timeout: 30) else {
            XCTFail("no document", file: file, line: line); return false
        }
        let button = app.buttons["editor-text-stamps"]
        app.revealInDocumentTools(button, file: file, line: line)
        button.tap()
        guard app.buttons["text-stamp-place"].waitForExistence(timeout: 15) else {
            XCTFail("the Text Stamp sheet did not open", file: file, line: line); return false
        }
        return true
    }

    /// Scrolls the sheet's form until `element` can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !wholly(element, in: app) {
            app.swipeUp(velocity: .slow)
        }
    }

    /// On screen and wholly inside the sheet's list. A row cut off at the
    /// sheet's foot counts as hittable, but a tap at its far end lands past
    /// the sheet, on the page behind, and closes the sheet: on an iPad Pro 13
    /// that is what tapping the Keep switch did (2026-11-20).
    private func wholly(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists, element.isHittable else { return false }
        guard !element.identifier.isEmpty else { return true }
        let list = app.collectionViews.containing(NSPredicate(format: "identifier == %@", element.identifier)).firstMatch
        return !list.exists || list.frame.contains(element.frame)
    }

    /// The preview heads the sheet's list, so bringing a lower row into view
    /// can take it out of the list altogether. Drags the list back down, a
    /// little at a time and held at the end: a drag that ran on past the top
    /// would pull the sheet down instead.
    private func revealPreview(in app: XCUIApplication) -> XCUIElement {
        let preview = app.descendants(matching: .any)["text-stamp-preview"].firstMatch
        let list = app.collectionViews.containing(NSPredicate(format: "identifier BEGINSWITH %@", "text-stamp-")).firstMatch
        for _ in 0..<12 where !(preview.exists && preview.isHittable) && list.exists {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 160)),
                        withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        return preview
    }

    private func stamps(_ store: LibraryStore, _ item: ItemID) async throws -> [TextBox] {
        guard let page = try await store.pages(of: item).first else { return [] }
        return try await store.objects(on: page.id).compactMap { object -> TextBox? in
            if case .text(let box) = object.payload, box.stamp != nil { return box }
            return nil
        }
    }

    /// Waits for the page to carry `count` stamps, read from disk.
    private func waitForStamps(_ store: LibraryStore, _ item: ItemID, count: Int) async throws -> [TextBox] {
        var found: [TextBox] = []
        for _ in 0..<60 {
            found = try await stamps(store, item)
            if found.count == count { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        return found
    }

    private func tapHistory(_ app: XCUIApplication, _ identifier: String) {
        let button = app.buttons[identifier]
        if !(button.exists && button.isHittable) { app.revealInDocumentTools(button) }
        button.tap()
    }

    func testAnApprovedStampIsPlacedUndoneRedoneAndKept() async throws {
        let (directory, store, item) = try await seed()
        var app = launch(directory)
        defer { app.terminate() }
        guard openStamps(app) else { return }

        XCTAssertEqual(app.buttons["text-stamp-preset-approved"].value as? String, "Selected")
        XCTAssertEqual(app.descendants(matching: .any)["text-stamp-preview"].firstMatch.value as? String, "APPROVED")
        snap(app, "sheet-en")
        let corner = app.buttons["text-stamp-placement-bottomRight"]
        reveal(corner, in: app)
        corner.tap()
        XCTAssertEqual(corner.value as? String, "Selected")
        app.buttons["text-stamp-place"].tap()
        XCTAssertTrue(app.buttons["text-stamp-place"].waitForNonExistence(timeout: 10), "the sheet stayed open")

        let placed = try await waitForStamps(store, item, count: 1)
        XCTAssertEqual(placed.first?.text, "APPROVED")
        XCTAssertEqual(placed.first?.stamp, .outlined)
        if let frame = placed.first?.frame {
            XCTAssertGreaterThan(frame.midX, 306, "not on the right")
            XCTAssertGreaterThan(frame.midY, 396, "not at the bottom")
        }
        snap(app, "placed-en")

        tapHistory(app, "notebook-undo")
        let undone = try await waitForStamps(store, item, count: 0)
        XCTAssertTrue(undone.isEmpty, "Undo left the stamp")
        tapHistory(app, "notebook-redo")
        let redone = try await waitForStamps(store, item, count: 1)
        XCTAssertEqual(redone.first?.text, "APPROVED", "Redo did not bring it back")

        app.terminate()
        app = launch(directory)
        XCTAssertTrue(app.descendants(matching: .any)["document-page-image"].firstMatch.waitForExistence(timeout: 30))
        let reopened = try await stamps(store, item)
        XCTAssertEqual(reopened.map(\.text), ["APPROVED"], "not there after reopening")
    }

    func testOwnWordsAreKeptAndOfferedAgain() async throws {
        let (directory, store, item) = try await seed()
        let app = launch(directory)
        defer { app.terminate() }
        guard openStamps(app) else { return }

        let custom = app.buttons["text-stamp-custom"]
        reveal(custom, in: app)
        custom.tap()
        let field = app.textFields["text-stamp-custom-text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // Return puts the keyboard away. Left up, on an iPad it shrinks the
        // sheet to the room above it, and the rows below the words go under.
        field.typeText("Checked by Ana\n")
        XCTAssertTrue(app.buttons["text-stamp-place"].isEnabled, "Place is off with words typed")
        let keep = app.switches["text-stamp-keep"]
        reveal(keep, in: app)
        // The switch itself, not its label, at the trailing end.
        keep.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(keep.value as? String, "1")
        app.buttons["text-stamp-place"].tap()
        XCTAssertTrue(app.buttons["text-stamp-place"].waitForNonExistence(timeout: 10))

        let placed = try await waitForStamps(store, item, count: 1)
        XCTAssertEqual(placed.first?.text, "Checked by Ana")
        let kept = try await store.savedStamps().map(\.design.text)
        XCTAssertEqual(kept, ["Checked by Ana"])

        guard openStamps(app) else { return }
        let saved = app.buttons["text-stamp-saved-1"]
        reveal(saved, in: app)
        XCTAssertTrue(saved.exists, "the kept stamp is not offered")
        saved.tap()
        XCTAssertEqual(saved.value as? String, "Selected")
        XCTAssertEqual(revealPreview(in: app).value as? String, "Checked by Ana")
        snap(app, "saved-en")
        app.buttons["text-stamp-cancel"].tap()
    }

    func testTheStampSheetInFrenchAndSpanish() async throws {
        for (language, word) in [("fr", "APPROUVÉ"), ("es", "APROBADO")] {
            let (directory, store, item) = try await seed()
            let app = launch(directory, language: language)
            defer { app.terminate() }
            guard openStamps(app) else { return }
            XCTAssertEqual(app.descendants(matching: .any)["text-stamp-preview"].firstMatch.value as? String, word,
                           "\(language): preview")
            XCTAssertTrue(app.buttons["text-stamp-preset-approved"].isHittable, "\(language): first preset")
            XCTAssertTrue(app.buttons["text-stamp-place"].isHittable, "\(language): Place out of reach")
            snap(app, "sheet-\(language)")
            let large = app.buttons["text-stamp-size-large"]
            reveal(large, in: app)
            XCTAssertTrue(large.isHittable, "\(language): sizes out of reach")
            snap(app, "options-\(language)")
            app.buttons["text-stamp-place"].tap()
            let placed = try await waitForStamps(store, item, count: 1)
            XCTAssertEqual(placed.first?.text, word, "\(language): placed word")
            app.terminate()
        }
    }

    /// Stamps are markup, which is Pro: Place asks a free user to upgrade,
    /// and closing that leaves the page as it was.
    func testAFreeUserIsAskedToUpgradeAndNothingIsPlaced() async throws {
        let (directory, store, item) = try await seed()
        let app = launch(directory, free: true)
        defer { app.terminate() }
        guard openStamps(app) else { return }
        app.buttons["text-stamp-place"].tap()
        let locked = app.descendants(matching: .any)["pro-locked-feature"]
        XCTAssertTrue(locked.waitForExistence(timeout: 15), "placed without a subscription")
        XCTAssertEqual(locked.value as? String, "markup")
        app.buttons["pro-close"].tap()
        XCTAssertTrue(locked.waitForNonExistence(timeout: 10))
        try await Task.sleep(for: .seconds(1))
        let placed = try await stamps(store, item)
        XCTAssertTrue(placed.isEmpty, "a stamp was placed for a free user")
    }

    // MARK: - Images

    /// A saved picture stamp, put in the library before launch: the system
    /// Photos and Files pickers are not driven here.
    private func seedPicture(_ store: LibraryStore) async throws -> SavedPictureStamp {
        let context = CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.8, alpha: 1))
        context.fillEllipse(in: CGRect(x: 20, y: 20, width: 360, height: 160))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        let staged = try store.assets.store(data as Data, kind: .png, originalFilename: "logo.png")
        return try await store.savePictureStamp(staged, pixelSize: CGSize(width: 400, height: 200))
    }

    private func placedImages(_ store: LibraryStore, _ item: ItemID) async throws -> [PlacedImage] {
        guard let page = try await store.pages(of: item).first else { return [] }
        return try await store.objects(on: page.id).compactMap { if case .image(let image) = $0.payload { image } else { nil } }
    }

    private func waitForImages(_ store: LibraryStore, _ item: ItemID, count: Int) async throws -> [PlacedImage] {
        var found: [PlacedImage] = []
        for _ in 0..<60 {
            found = try await placedImages(store, item)
            if found.count == count { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        return found
    }

    func testASavedImageIsPlacedUndoneRedoneAndKept() async throws {
        let (directory, store, item) = try await seed()
        let picture = try await seedPicture(store)
        var app = launch(directory)
        defer { app.terminate() }
        guard openStamps(app) else { return }

        let row = app.buttons["text-stamp-picture-1"]
        reveal(row, in: app)
        XCTAssertTrue(row.exists, "the saved image is not offered")
        row.tap()
        XCTAssertEqual(row.value as? String, "Selected")
        XCTAssertFalse(app.switches["text-stamp-date"].exists, "an image has no date")
        snap(app, "image-chosen-en")
        app.buttons["text-stamp-place"].tap()
        XCTAssertTrue(app.buttons["text-stamp-place"].waitForNonExistence(timeout: 10), "the sheet stayed open")

        let placed = try await waitForImages(store, item, count: 1)
        XCTAssertEqual(placed.first?.assetID, picture.assetID)
        if let frame = placed.first?.frame {
            XCTAssertEqual(frame.width / frame.height, 2, accuracy: 0.01, "not in the image's own proportions")
            XCTAssertGreaterThan(frame.midX, 306, "not on the right")
        }
        snap(app, "image-placed-en")

        tapHistory(app, "notebook-undo")
        let undone = try await waitForImages(store, item, count: 0)
        XCTAssertTrue(undone.isEmpty, "Undo left the image")
        tapHistory(app, "notebook-redo")
        let redone = try await waitForImages(store, item, count: 1)
        XCTAssertEqual(redone.first?.assetID, picture.assetID, "Redo did not bring it back")

        app.terminate()
        app = launch(directory)
        XCTAssertTrue(app.descendants(matching: .any)["document-page-image"].firstMatch.waitForExistence(timeout: 30))
        let reopened = try await placedImages(store, item)
        XCTAssertEqual(reopened.map(\.assetID), [picture.assetID], "not there after reopening")
        let kept = try await store.savedPictureStamps()
        XCTAssertEqual(kept.map(\.id), [picture.id], "the saved image went")
    }

    func testImagesInFrenchAndSpanish() async throws {
        for (language, label) in [("fr", "Image 1"), ("es", "Imagen 1")] {
            let (directory, store, _) = try await seed()
            _ = try await seedPicture(store)
            let app = launch(directory, language: language)
            defer { app.terminate() }
            guard openStamps(app) else { return }
            let row = app.buttons["text-stamp-picture-1"]
            reveal(row, in: app)
            XCTAssertTrue(row.isHittable, "\(language): the image row is out of reach")
            XCTAssertTrue(row.label.contains(label), "\(language): row reads \(row.label)")
            XCTAssertTrue(app.buttons["text-stamp-add-file"].exists, "\(language): no way to add an image")
            snap(app, "images-\(language)")
            app.terminate()
        }
    }

    func testAFreeUserPlacingAnImageIsAskedToUpgrade() async throws {
        let (directory, store, item) = try await seed()
        _ = try await seedPicture(store)
        let app = launch(directory, free: true)
        defer { app.terminate() }
        guard openStamps(app) else { return }
        let row = app.buttons["text-stamp-picture-1"]
        reveal(row, in: app)
        row.tap()
        app.buttons["text-stamp-place"].tap()
        let locked = app.descendants(matching: .any)["pro-locked-feature"]
        XCTAssertTrue(locked.waitForExistence(timeout: 15), "placed without a subscription")
        XCTAssertEqual(locked.value as? String, "markup")
        app.buttons["pro-close"].tap()
        XCTAssertTrue(locked.waitForNonExistence(timeout: 10))
        try await Task.sleep(for: .seconds(1))
        let placed = try await placedImages(store, item)
        XCTAssertTrue(placed.isEmpty, "an image was placed for a free user")
    }
}
