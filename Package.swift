// swift-tools-version: 6.0
// PaperNest shared code. The Xcode project (project.yml) consumes these
// libraries for the iOS/iPadOS and macOS app targets; the `PaperNestMac`
// executable lets the Mac app be built and run with Command Line Tools only.
import PackageDescription

let package = Package(
    name: "PaperNest",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PaperNestCore", targets: ["PaperNestCore"]),
        .library(name: "PaperNestStore", targets: ["PaperNestStore"]),
        .library(name: "PaperNestImport", targets: ["PaperNestImport"]),
        .library(name: "PaperNestRender", targets: ["PaperNestRender"]),
        .library(name: "PaperNestExport", targets: ["PaperNestExport"]),
        .library(name: "PaperNestSync", targets: ["PaperNestSync"]),
        .library(name: "PaperNestUI", targets: ["PaperNestUI"]),
        .executable(name: "PaperNestMac", targets: ["PaperNestMac"]),
    ],
    targets: [
        .target(name: "PaperNestCore"),
        .target(name: "PaperNestStore", dependencies: ["PaperNestCore"]),
        .target(name: "PaperNestImport", dependencies: ["PaperNestCore", "PaperNestStore"]),
        .target(name: "PaperNestRender", dependencies: ["PaperNestCore", "PaperNestStore"]),
        .target(name: "PaperNestExport", dependencies: ["PaperNestCore", "PaperNestStore", "PaperNestRender"]),
        // iCloud sync: the CKSyncEngine adapter, asset transfer and the
        // controller the UI observes. The merge and outbox logic it drives
        // lives in PaperNestStore, beside the data it protects.
        .target(name: "PaperNestSync", dependencies: ["PaperNestCore", "PaperNestStore"]),
        .target(
            name: "PaperNestUI",
            dependencies: ["PaperNestCore", "PaperNestStore", "PaperNestImport", "PaperNestRender", "PaperNestExport", "PaperNestSync"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "PaperNestMac",
            dependencies: ["PaperNestUI"],
            path: "Apps/Mac/Sources"
        ),
        // Dev tool: imports files into a library directory through the real
        // importer (used to seed Simulator and dev-app libraries).
        .executableTarget(
            name: "papernest-seed",
            dependencies: ["PaperNestCore", "PaperNestImport", "PaperNestStore"],
            path: "Tools/LibrarySeeder"
        ),
        // Synthetic fixtures shared by tests and the sample generator. Never
        // linked into an app target.
        .target(name: "PaperNestTestSupport", path: "Tests/Support"),
        .executableTarget(
            name: "papernest-samples",
            dependencies: ["PaperNestTestSupport"],
            path: "Tools/SampleGenerator"
        ),
        .testTarget(name: "PaperNestCoreTests", dependencies: ["PaperNestCore"]),
        .testTarget(name: "PaperNestStoreTests", dependencies: ["PaperNestStore"]),
        .testTarget(name: "PaperNestSyncTests", dependencies: ["PaperNestSync", "PaperNestStore", "PaperNestCore"]),
        .testTarget(name: "PaperNestImportTests", dependencies: ["PaperNestImport", "PaperNestRender", "PaperNestTestSupport"]),
        .testTarget(name: "PaperNestExportTests", dependencies: ["PaperNestExport", "PaperNestImport", "PaperNestTestSupport"]),
        .testTarget(name: "PaperNestUITests", dependencies: ["PaperNestUI", "PaperNestImport", "PaperNestTestSupport"]),
    ]
)
