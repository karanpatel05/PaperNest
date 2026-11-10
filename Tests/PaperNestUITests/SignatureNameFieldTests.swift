import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
@testable import PaperNestUI

/// The owner reported "save signature feature is not working on mac", and the
/// symptom turned out to be **"unable to enter name"**.
///
/// On macOS a `TextField(title, text:)` inside a `.formStyle(.grouped)` Form
/// renders its title as an *external leading label*, not as an in-field
/// placeholder the way iOS does. The field itself is then an empty, borderless,
/// right-aligned strip with nothing drawn in it, and clicking the visible word
/// "Name" focuses nothing — so there is no affordance anywhere in the row.
/// `canSave` requires a non-empty name, so Save Signature stays greyed forever
/// and the whole feature is unreachable.
///
/// The field therefore carries its own prompt. These tests pin that contract
/// and the reason it matters; the *visible* result was checked by running the
/// Mac app, which a unit test cannot do.
@MainActor @Suite struct SignatureNameFieldTests {
    private func draft() async throws -> (SignatureDraft, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let library = LibrarySession(libraryURL: root)
        await library.bootstrap()
        let env = try #require(library.environment)
        let item = try await env.store.createItem(kind: .notebook, name: "Names", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let model = DocumentModel(itemID: item.id, session: library)
        await model.load()
        let page = try #require(model.selectedPage)
        return (SignatureDraft(model: model, page: page), root)
    }

    /// The field must say something while it is empty. Without this the Mac
    /// shows a row whose only visible text is a label that cannot be clicked.
    @Test func theNameFieldCarriesAPromptWhileItIsEmpty() throws {
        let prompt = SignatureSheet.namePrompt
        #expect(!prompt.trimmingCharacters(in: .whitespaces).isEmpty,
                "an empty prompt leaves the Mac field invisible again")
        #expect(prompt != "signature.name",
                "the prompt must resolve through L10n, not leak a raw key")
    }

    /// Why the prompt is not cosmetic: ink alone never enables the save, so a
    /// field the user cannot find is the whole feature failing.
    @Test func inkWithoutANameCannotBeSavedButANameUnlocksIt() async throws {
        let (draft, root) = try await self.draft()
        defer { try? FileManager.default.removeItem(at: root) }
        draft.strokes = [InkStroke(tool: .pen, color: .black, width: 2,
                                   points: [InkPoint(x: 0, y: 0), InkPoint(x: 40, y: 20)])]
        #expect(!draft.canSave, "ink with no name must not be saveable")
        draft.name = "   "
        #expect(!draft.canSave, "whitespace is not a name")
        draft.name = SignatureSheet.namePrompt
        #expect(draft.canSave, "once a name is entered the save becomes available")
    }

    /// A guard with teeth. The fix is a single argument in a single line of the
    /// view, and none of the assertions above would notice if it were deleted —
    /// they would all still pass while the Mac field went invisible again.
    /// `LocalizationTests` already reads source through `#filePath`; this reads
    /// the one line that matters the same way.
    @Test func theNameTextFieldStillHandsThatPromptToSwiftUI() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PaperNestUI/SignatureSheet.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let field = try #require(text.split(separator: "\n").first { $0.contains("text: $draft.name") },
                                 "the signature name TextField moved or was renamed")
        #expect(field.contains("prompt:"), """
            The signature name field no longer passes a prompt. On macOS that makes it an \
            empty borderless strip with nothing to see or click, no name can be entered, \
            and Save Signature stays greyed out. Line found: \
            \(field.trimmingCharacters(in: .whitespaces))
            """)
    }

    /// Drawing and saving still work end to end through the draft the view owns,
    /// so the added argument changed nothing about the save itself.
    @Test func inkWithANameIsStillSavedAndKept() async throws {
        let (draft, root) = try await self.draft()
        defer { try? FileManager.default.removeItem(at: root) }
        draft.strokes = [InkStroke(tool: .pen, color: .black, width: 2,
                                   points: [InkPoint(x: 0, y: 0), InkPoint(x: 40, y: 20),
                                            InkPoint(x: 80, y: 0)])]
        draft.name = "Everyday"
        #expect(await draft.saveReusable())
        let store = try LibraryStore(directory: root)
        #expect(try await store.signatures().map(\.name) == ["Everyday"])
    }
}
