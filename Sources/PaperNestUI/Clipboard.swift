import Foundation
import ImageIO
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Reads importable content from the system clipboard.
enum Clipboard {
    enum Content {
        case files([URL])
        /// PNG, JPEG or PDF bytes.
        case image(Data)
    }

    static let pasteableTypes: [UTType] = [.fileURL, .pdf, .png, .jpeg, .tiff]

    @MainActor
    static func read() -> Content? {
        #if canImport(AppKit)
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return .files(urls)
        }
        if let pdf = board.data(forType: .pdf) { return .image(pdf) }
        if let png = board.data(forType: .png) { return .image(png) }
        if let tiff = board.data(forType: .tiff), let png = convertToPNG(tiff) { return .image(png) }
        return nil
        #elseif canImport(UIKit)
        let board = UIPasteboard.general
        if let png = board.data(forPasteboardType: UTType.png.identifier) { return .image(png) }
        if let jpeg = board.data(forPasteboardType: UTType.jpeg.identifier) { return .image(jpeg) }
        if let image = board.image, let png = image.pngData() { return .image(png) }
        return nil
        #endif
    }

    /// Screenshots and copied images often arrive as TIFF; the library
    /// stores PNG instead.
    static func convertToPNG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
