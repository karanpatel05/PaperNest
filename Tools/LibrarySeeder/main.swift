// Imports files into a PaperNest library directory using the app's own
// importer, so dev builds and Simulator runs can start with real content.
// Usage: swift run papernest-seed <library-dir> <file>... [--password <pw>] [--crop x,y,w,h]
// --crop applies a normalized source-space crop to every imported page.
import Foundation
import PaperNestCore
import PaperNestImport
import PaperNestStore

var args = Array(CommandLine.arguments.dropFirst())
var password: String?
if let i = args.firstIndex(of: "--password"), i + 1 < args.count {
    password = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
var crop: NormalizedRect?
if let i = args.firstIndex(of: "--crop"), i + 1 < args.count {
    let parts = args[i + 1].split(separator: ",").compactMap { Double($0) }
    guard parts.count == 4 else {
        FileHandle.standardError.write(Data("--crop expects x,y,w,h in 0...1\n".utf8))
        exit(64)
    }
    crop = NormalizedRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    args.removeSubrange(i...(i + 1))
}
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: papernest-seed <library-dir> <file>... [--password <pw>] [--crop x,y,w,h]\n".utf8))
    exit(64)
}
let library = URL(fileURLWithPath: args[0], isDirectory: true)
let store = try LibraryStore(directory: library)
let importer = DocumentImporter(store: store)
var failures = 0
for path in args.dropFirst() {
    let url = URL(fileURLWithPath: path)
    do {
        let item = try await importer.importItem(.file(url), password: password)
        if let crop {
            for page in try await store.pages(of: item.id) {
                try await store.updateTransform(page.id, to: PageTransform(crop: crop, rotation: page.transform.rotation))
            }
        }
        print("imported \(url.lastPathComponent) as \"\(item.name)\"\(crop == nil ? "" : " (cropped)")")
    } catch {
        failures += 1
        print("skipped \(url.lastPathComponent): \(error)")
    }
}
exit(failures == 0 ? 0 : 1)
