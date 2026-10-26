import Foundation
import PDFKit
import PencilKit
import Testing
import PaperNestCore
@testable import PaperNestUI

@MainActor @Suite(.serialized) struct ShapeAnnotationWorkflowTests {
    @Test(arguments: [ShapeAnnotation.rectangle, .checkmark, .cross, .star]) func shapePersistsRendersExportsAndUndoesWithPageCreation(_ kind: ShapeAnnotation) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        let env = try #require(session.environment)
        let id = try await LibraryModel(session: session).createNotebook(named: "Shapes", template: .blank)
        let model = DocumentModel(itemID: id, session: session)
        await model.load()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        try await model.addNotebookPage(.blank, after: model.selectedPageID, undoManager: undo)
        undo.endUndoGrouping()
        let page = try #require(model.selectedPage)
        undo.beginUndoGrouping()
        try await model.addShape(to: page, kind: kind, start: .init(x: 0.25, y: 0.25), end: .init(x: 0.75, y: 0.75), color: .black, width: 4, undoManager: undo)
        undo.endUndoGrouping()
        #expect(try await env.store.objects(on: page.id).count == 1)
        let reopened = DocumentModel(itemID: id, session: session)
        await reopened.load()
        #expect(reopened.pages == model.pages)
        let output = try await env.exporter.export(itemName: "Shapes", pages: [try #require(model.selectedPage)], options: .init(format: .pdf))
        defer { output.removeTemporaryFiles() }
        let document = try #require(CGDocument(output.files[0]))
        var pixels = [UInt8](repeating: 255, count: 600 * 850 * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let ctx = try #require(CGContext(data: buffer.baseAddress, width: 600, height: 850, bitsPerComponent: 8, bytesPerRow: 600 * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            ctx.drawPDFPage(document)
        }
        let painted = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 100 }.count
        #expect(painted > 1000)
        undo.undo()
        undo.undo()
        try await settled(model)
        #expect(model.pages.count == 1)
        #expect(model.presentedError == nil)
        undo.redo()
        undo.redo()
        try await settled(model)
        #expect(model.pages.count == 2)
        #expect(try await env.store.objects(on: page.id).count == 1)
    }

    @Test(arguments: [ShapeAnnotation.rectangle, .arrow, .checkmark, .cross, .star])
    func shapeCornersSurvivePencilKit(_ kind: ShapeAnnotation) throws {
        let geometry = PageGeometry(sourceSize: CGSize(width: 600, height: 800), rotation: .clockwise90)
        let original = try kind.stroke(from: .init(x: 0.2, y: 0.2), to: .init(x: 0.8, y: 0.8),
                                       geometry: geometry, color: .black, width: 4)
        let conversion = InkConversion(sourceToView: geometry.sourceToPage.concatenating(.init(scaleX: 1.5, y: 1.5)))
        let restored = try #require(conversion.inkStrokes(from: conversion.pkStroke(from: original, seed: 42)).first)
        func distance(_ p: InkPoint, _ a: InkPoint, _ b: InkPoint) -> Double {
            let dx = b.x - a.x, dy = b.y - a.y
            let lengthSquared = dx * dx + dy * dy
            let t = lengthSquared == 0 ? 0 : min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared, 0), 1)
            return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
        }
        let segments = Array(zip(original.points, original.points.dropFirst()))
        let deviation = restored.points.map { point in segments.map { distance(point, $0.0, $0.1) }.min()! }.max()!
        #expect(deviation < 0.5, "PencilKit must preserve the saved outline")
        for corner in original.points {
            #expect(restored.points.contains { hypot($0.x - corner.x, $0.y - corner.y) < 1.5 }, "PencilKit must visit every corner")
        }
    }

    private func CGDocument(_ url: URL) -> CGPDFPage? { CGPDFDocument(url as CFURL)?.page(at: 1) }
    private func settled(_ model: DocumentModel) async throws {
        for _ in 0..<150 where model.isChangingNotebookPage { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.isChangingNotebookPage)
    }
}
