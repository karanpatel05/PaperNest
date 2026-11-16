import Foundation
import Testing

/// App Store Connect rejects an upload whose code calls a "required reason"
/// API that `PrivacyInfo.xcprivacy` does not declare (ITMS-91053). Nothing
/// fails locally when that happens: the build, the tests and the app all work,
/// and the rejection arrives only after an archive is uploaded.
///
/// So this reads the shipped app's source the way `BrandMarkTests` does and
/// checks every category it finds against the manifest. A new call to one of
/// these APIs then fails here, naming the file, instead of at upload.
///
/// The symbols are Apple's list at
/// https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
/// as it applies to Swift. Choosing the *reason* stays a human decision: the
/// test only insists that each category used has at least one.
@Suite struct PrivacyManifestTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // PaperNestUITests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // repository root

    /// Category → patterns that mean the shipped code uses it.
    private static let categories: [(name: String, patterns: [String])] = [
        ("NSPrivacyAccessedAPICategoryFileTimestamp", [
            #"\bcreationDateKey\b"#, #"\bcontentModificationDateKey\b"#, #"\bcontentAccessDateKey\b"#,
            #"\bfileCreationDate\b"#, #"\bfileModificationDate\b"#, #"FileAttributeKey\.(creationDate|modificationDate)"#,
            #"\bgetattrlist\b"#, #"\b(f|l)?stat\("#,
        ]),
        ("NSPrivacyAccessedAPICategorySystemBootTime", [
            #"\bsystemUptime\b"#, #"\bmach_absolute_time\b"#,
        ]),
        ("NSPrivacyAccessedAPICategoryDiskSpace", [
            #"\bvolumeAvailableCapacity\w*Key\b"#, #"\bvolumeTotalCapacityKey\b"#,
            #"\.systemFreeSize\b"#, #"\.systemSize\b"#, #"\bstatv?fs\b"#,
        ]),
        ("NSPrivacyAccessedAPICategoryActiveKeyboards", [
            #"\bactiveInputModes\b"#,
        ]),
        ("NSPrivacyAccessedAPICategoryUserDefaults", [
            #"\bUserDefaults\b"#, #"@AppStorage\b"#,
        ]),
    ]

    @Test func everyRequiredReasonAPITheAppCallsIsDeclared() throws {
        let declared = try Self.declaredCategories()
        var missing: [String] = []
        for (name, files) in try Self.usedCategories() where !declared.contains(name) {
            missing.append("\(name), used in \(files.sorted().joined(separator: ", "))")
        }
        #expect(missing.isEmpty, "Declare these in Apps/Shared/PrivacyInfo.xcprivacy: \(missing.joined(separator: "; "))")
    }

    /// Guards the scan itself: if the paths moved and it read nothing, the
    /// test above would pass while checking no code at all.
    @Test func theScanReadsTheShippedSource() throws {
        let used = try Self.usedCategories()
        #expect(used["NSPrivacyAccessedAPICategoryUserDefaults"] != nil)
        #expect(used["NSPrivacyAccessedAPICategoryFileTimestamp"] != nil)
    }

    /// Categories with at least one reason code in the manifest.
    private static func declaredCategories() throws -> Set<String> {
        let data = try Data(contentsOf: root.appendingPathComponent("Apps/Shared/PrivacyInfo.xcprivacy"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let entries = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        return Set(entries.compactMap { entry in
            guard let type = entry["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String], !reasons.isEmpty else { return nil }
            return type
        })
    }

    /// Category → repository-relative files that use it, over the code that
    /// ships in the app: every module under `Sources` and the app targets'
    /// own `Sources`. Test targets are not in the app and are not read.
    private static func usedCategories() throws -> [String: Set<String>] {
        let directories = ["Sources", "Apps/iOS/Sources", "Apps/Mac/Sources"].map { root.appendingPathComponent($0) }
        let compiled = try categories.map { ($0.name, try $0.patterns.map { try NSRegularExpression(pattern: $0) }) }
        var used: [String: Set<String>] = [:]
        for directory in directories {
            guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                let range = NSRange(text.startIndex..., in: text)
                let relative = String(file.path.dropFirst(root.path.count + 1))
                for (name, patterns) in compiled where patterns.contains(where: { $0.firstMatch(in: text, range: range) != nil }) {
                    used[name, default: []].insert(relative)
                }
            }
        }
        return used
    }
}
