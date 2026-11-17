import FactorioData
import Foundation
import LibraryCore
import PreviewRenderer
import Testing

@testable import LibraryApp

private let activities: [LibraryActivity] = [
    .opening, .creating, .listing, .recovering, .changing, .commenting, .importing, .exporting, .rendering,
    .statistics, .verifyingAssets,
]

/// Every case of every error type the app can receive, with the code its details must carry (nil: none defined).
private let cases: [(Error, String?)] = {
    let library: [NativeLibraryError] = [
        .inUse, .closed, .unsupportedFilesystem, .unsafePath, .invalidFormat, .unsupportedVersion, .invalidMetadata,
        .integrity, .recoveryRequired, .notFound, .limitExceeded, .invalidInput, .nameCollision, .folderNotEmpty,
        .sourceChanged, .ambiguousId, .io(ENOSPC),
    ]
    let limits: [BlueprintCodecLimit] = [
        .sourceBytes, .decodedBytes, .jsonDepth, .bookDepth, .entries, .entitiesAndTiles, .jsonNodes,
    ]
    let codec: [BlueprintCodecError] =
        [.invalidSource("Not base64."), .invalidEntryPath, .invalidLimits, .compressionFailure]
        + limits.map { .limitExceeded($0) }
    let preview: [PreviewError] = [
        .invalidInput, .invalidDrawList, .assetDecode, .imageAllocation, .imageEncoding, .timedOut, .workerFailed,
        .workerProtocol, .workerBusy, .memoryLimit,
    ]
    let planner: [PlannerRuntimeError] = [.resourceMissing, .contextUnavailable, .javascript("boom"), .invalidResult]
    return library.map { ($0, $0.code) } + codec.map { ($0, "BLUEPRINT_CODEC_ERROR") }
        + preview.map { ($0, $0.code) } + planner.map { ($0, nil) }
        + [
            (StatisticsError.invalidData("bad"), "STATISTICS_INVALID_INPUT"),
            (AssetReleaseError.invalid("missing"), "INVALID_ASSET_RELEASE"),
            (PrototypeMapError.invalid("missing"), "INVALID_PROTOTYPE_MAP"),
            (CocoaError(.fileReadNoPermission), nil),
        ]
}()

@Suite("Library messages")
struct LibraryMessageTests {
    @Test("Every error case maps to a title and guidance without codes, with its code in the details")
    func everyCase() throws {
        for (error, code) in cases {
            for activity in activities {
                let message = try #require(
                    LibraryMessage.describing(error, activity: activity, libraryName: "Trains"),
                    "\(error) during \(activity)")
                #expect(!message.title.isEmpty && !message.guidance.isEmpty, "\(error)")
                #expect(message.code == code, "\(error)")
                #expect(!message.technical.isEmpty, "\(error)")
                for text in [message.title, message.guidance] {
                    #expect(!text.contains("_"), "code-like text in \(text)")
                    #expect(!text.lowercased().contains("errno"), "errno in \(text)")
                    if let code { #expect(!text.contains(code), "\(code) in \(text)") }
                }
            }
        }
    }

    @Test("Messages follow the activity: listing limits, operation limits, comments, and opening")
    func activitySpecific() throws {
        let listing = try #require(LibraryMessage.describing(NativeLibraryError.limitExceeded, activity: .listing))
        #expect(listing.title == "This library is too large to list")
        let change = try #require(LibraryMessage.describing(NativeLibraryError.limitExceeded, activity: .changing))
        #expect(change.guidance.contains("cyano staging-cleanup"))
        let comment = try #require(LibraryMessage.describing(NativeLibraryError.invalidInput, activity: .commenting))
        #expect(comment.title == "That comment can't be used")
        let inUse = try #require(
            LibraryMessage.describing(NativeLibraryError.inUse, activity: .opening, libraryName: "Trains"))
        #expect(inUse.title == "“Trains” is in use")
        let io = try #require(LibraryMessage.describing(NativeLibraryError.io(ENOSPC), activity: .changing))
        #expect(io.technical.contains("No space left on device"))
    }

    @Test("Cancelled renders show nothing")
    func cancellation() {
        #expect(LibraryMessage.describing(PreviewError.cancelled, activity: .rendering) == nil)
    }

    @Test("Listing issues have their own wording")
    func listingIssues() {
        for code in [
            "INTEGRITY_CONFLICT", "INVALID_METADATA", "INVALID_SOURCE", "UNSAFE_PATH", "AMBIGUOUS_ID",
            "FILESYSTEM_ERROR", "SOMETHING_NEW",
        ] {
            let line = LibraryMessage.listingIssue(code: code)
            #expect(line.hasSuffix("Close the library before fixing it in Finder.") && !line.contains(code))
        }
        #expect(LibraryMessage.listingIssue(code: "INTEGRITY_CONFLICT").contains("letter case"))
    }
}
