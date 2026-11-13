// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "FBNative",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LibraryCore", targets: ["LibraryCore"]),
        .library(name: "FactorioData", targets: ["FactorioData"]),
        .library(name: "PreviewRenderer", targets: ["PreviewRenderer"]),
        .executable(name: "fb-native", targets: ["FBNativeCLI"]),
        .executable(name: "preview-probe", targets: ["PreviewProbe"]),
        .executable(name: "preview-worker", targets: ["PreviewWorker"]),
    ],
    targets: [
        .target(name: "CLibraryPlatform", publicHeadersPath: "include"),
        .target(name: "LibraryCore", dependencies: ["CLibraryPlatform"]),
        .target(name: "FactorioData", dependencies: ["LibraryCore"]),
        .target(
            name: "PreviewRenderer",
            dependencies: ["LibraryCore", "FactorioData", "CLibraryPlatform"],
            resources: [.copy("Resources")],
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        ),
        .executableTarget(name: "FBNativeCLI", dependencies: ["LibraryCore", "FactorioData"]),
        .executableTarget(name: "PreviewWorker", dependencies: ["PreviewRenderer"]),
        .executableTarget(name: "PreviewProbe", dependencies: ["PreviewRenderer", "PreviewWorker", "LibraryCore"]),
        .executableTarget(name: "StorageTestDriver", dependencies: ["LibraryCore"], path: "Tests/Support/StorageTestDriver"),
        .testTarget(
            name: "LibraryCoreTests",
            dependencies: ["LibraryCore", "StorageTestDriver", "FBNativeCLI"],
            resources: [.copy("Fixtures")]
        ),
        .executableTarget(name: "PreviewTestWorker", dependencies: ["PreviewRenderer"], path: "Tests/Support/PreviewTestWorker"),
        .testTarget(name: "PreviewRendererTests", dependencies: ["PreviewRenderer", "PreviewWorker", "PreviewTestWorker", "PreviewProbe", "LibraryCore"]),
        .testTarget(name: "FactorioDataTests", dependencies: ["FactorioData", "LibraryCore", "FBNativeCLI"]),
    ]
)
