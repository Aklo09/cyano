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
    ],
    targets: [
        .target(name: "CLibraryPlatform", publicHeadersPath: "include"),
        .target(name: "LibraryCore", dependencies: ["CLibraryPlatform"]),
        .target(name: "FactorioData", dependencies: ["LibraryCore"]),
        .target(
            name: "PreviewRenderer",
            resources: [.copy("Resources")],
            linkerSettings: [.linkedFramework("JavaScriptCore")]
        ),
        .executableTarget(name: "FBNativeCLI", dependencies: ["LibraryCore", "FactorioData"]),
        .executableTarget(name: "PreviewProbe", dependencies: ["PreviewRenderer"]),
        .executableTarget(name: "StorageTestDriver", dependencies: ["LibraryCore"], path: "Tests/Support/StorageTestDriver"),
        .testTarget(
            name: "LibraryCoreTests",
            dependencies: ["LibraryCore", "StorageTestDriver", "FBNativeCLI"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PreviewRendererTests", dependencies: ["PreviewRenderer"]),
        .testTarget(name: "FactorioDataTests", dependencies: ["FactorioData", "LibraryCore", "FBNativeCLI"]),
    ]
)
