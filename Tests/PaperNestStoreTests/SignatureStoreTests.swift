import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Keeping a signature between sessions. Row 23's storage half.
@Suite struct SignatureStoreTests {
    private func signature(_ name: String) -> SavedSignature {
        SavedSignature(name: name, capturing: [
            InkStroke(tool: .pen, color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1), width: 2,
                      points: [InkPoint(x: 0, y: 0), InkPoint(x: 200, y: 0), InkPoint(x: 200, y: 50)])
        ])!
    }

    @Test func aSignatureSurvivesBeingSavedAndListed() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let mine = signature("Mine")

        try await store.saveSignature(mine)
        let listed = try await store.signatures()

        #expect(listed.count == 1)
        #expect(listed.first?.id == mine.id)
        #expect(listed.first?.name == "Mine")
        #expect(listed.first?.strokes == mine.strokes, "the ink did not survive the round trip")
    }

    @Test func savingTheSameSignatureAgainReplacesIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        var mine = signature("Mine")
        try await store.saveSignature(mine)

        mine.name = "Renamed"
        try await store.saveSignature(mine)

        let listed = try await store.signatures()
        #expect(listed.count == 1, "a second copy was kept")
        #expect(listed.first?.name == "Renamed")
    }

    @Test func deletingRemovesOnlyThatSignature() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let first = signature("First")
        let second = signature("Second")
        try await store.saveSignature(first)
        try await store.saveSignature(second)

        try await store.deleteSignature(first.id)

        let listed = try await store.signatures()
        #expect(listed.map(\.name) == ["Second"])
    }

    @Test func signaturesOutliveReopeningTheLibrary() async throws {
        let dir = TempDirectory()
        let mine = signature("Mine")
        do {
            let store = try LibraryStore(directory: dir.url)
            try await store.saveSignature(mine)
        }

        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.signatures().first?.id == mine.id)
        #expect(try await reopened.schemaVersion() == Schema.latestVersion)
    }
}
