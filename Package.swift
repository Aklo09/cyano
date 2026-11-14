// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "FBNative",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "LibraryCore", targets: ["LibraryCore"]),
        .library(name: "FactorioData", targets: ["FactorioData"]),
        .library(name: "PreviewRenderer", targets: ["PreviewRenderer"]),
        .library(name: "LibraryApp", targets: ["LibraryApp"]),
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
        .target(name: "LibraryApp", dependencies: ["LibraryCore", "FactorioData", "PreviewRenderer"]),
        .executableTarget(
            name: "FBNativeCLI", dependencies: ["LibraryCore", "FactorioData", "PreviewRenderer", "PreviewWorker"]),
        // Inside the app bundle the worker sits in Contents/MacOS and loads the package frameworks the app embeds.
        .executableTarget(
            name: "PreviewWorker", dependencies: ["PreviewRenderer"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "PreviewProbe", dependencies: ["PreviewRenderer", "PreviewWorker", "LibraryCore"]),
        .executableTarget(
            name: "StorageTestDriver", dependencies: ["LibraryCore"], path: "Tests/Support/StorageTestDriver"),
        .testTarget(
            name: "LibraryCoreTests",
            dependencies: ["LibraryCore", "StorageTestDriver", "FBNativeCLI"],
            resources: [.copy("Fixtures")]
        ),
        .target(name: "PreviewTestPlatform", path: "Tests/Support/PreviewTestPlatform", publicHeadersPath: "include"),
        .executableTarget(
            name: "PreviewTestWorker", dependencies: ["PreviewRenderer", "PreviewTestPlatform"],
            path: "Tests/Support/PreviewTestWorker"),
        .executableTarget(
            name: "LibraryPreviewTestDriver", dependencies: ["LibraryCore", "PreviewRenderer"],
            path: "Tests/Support/LibraryPreviewTestDriver"),
        .testTarget(
            name: "PreviewRendererTests",
            dependencies: [
                "PreviewRenderer", "PreviewWorker", "PreviewTestWorker", "PreviewProbe", "LibraryCore",
                "LibraryPreviewTestDriver", "FBNativeCLI",
            ]),
        .testTarget(name: "FactorioDataTests", dependencies: ["FactorioData", "LibraryCore", "FBNativeCLI"]),
        .testTarget(
            name: "LibraryAppTests",
            dependencies: ["LibraryApp", "LibraryCore", "FactorioData", "PreviewRenderer", "FBNativeCLI"]),
    ]
)
