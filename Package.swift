// swift-tools-version: 6.2
import PackageDescription

// Stash is a macOS 26 app. `StashCore` is plain Foundation so its logic
// (storage, parsing, ranking) can also be built and tested on Linux.

var products: [Product] = [
    .library(name: "StashCore", targets: ["StashCore"]),
]

var dependencies: [Package.Dependency] = []

var targets: [Target] = [
    // Only used on Linux, where the SQLite3 module is not part of the SDK.
    .systemLibrary(
        name: "CSQLite",
        path: "Sources/CSQLite",
        providers: [.apt(["libsqlite3-dev"])]
    ),
    .target(
        name: "StashCore",
        dependencies: [
            .target(name: "CSQLite", condition: .when(platforms: [.linux])),
        ]
    ),
    .testTarget(
        name: "StashCoreTests",
        dependencies: ["StashCore"]
    ),
]

#if os(macOS)
products.append(.executable(name: "Stash", targets: ["Stash"]))
dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"))
targets.append(
    .executableTarget(
        name: "Stash",
        dependencies: ["StashCore", .product(name: "Sparkle", package: "Sparkle")],
        // Copied into Stash.app/Contents/Resources by scripts/build-app.sh.
        exclude: ["Resources"]
    )
)
#endif

let package = Package(
    name: "Stash",
    platforms: [.macOS("26.0")],
    products: products,
    dependencies: dependencies,
    targets: targets,
    swiftLanguageModes: [.v5]
)
