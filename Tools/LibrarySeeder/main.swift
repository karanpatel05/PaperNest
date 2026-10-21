// Imports files into a PaperNest library directory using the app's own
// importer, so dev builds and Simulator runs can start with real content.
// Usage: swift run papernest-seed <library-dir> <file>... [--password <pw>]
import Foundation
import PaperNestImport
import PaperNestStore

var args = Array(CommandLine.arguments.dropFirst())
var password: String?
if let i = args.firstIndex(of: "--password"), i + 1 < args.count {
    password = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: papernest-seed <library-dir> <file>... [--password <pw>]\n".utf8))
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
        print("imported \(url.lastPathComponent) as \"\(item.name)\"")
    } catch {
        failures += 1
        print("skipped \(url.lastPathComponent): \(error)")
    }
}
exit(failures == 0 ? 0 : 1)
