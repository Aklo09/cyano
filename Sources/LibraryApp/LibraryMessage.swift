import Darwin
import FactorioData
import Foundation
import LibraryCore
import PreviewRenderer

/// What the app was doing when a failure happened; the same error code can mean different things in each.
public enum LibraryActivity: Sendable, Equatable {
    case opening, creating, listing, recovering, changing, commenting, importing, exporting, rendering, statistics
    case verifyingAssets
}

/// A failure as the owner sees it: what happened, what they can do, and support details kept out of both
/// (screen specs, "Messages"; spec GEN-3). Codes and errno values appear only in `code` and `technical`.
public struct LibraryMessage: Sendable, Equatable, Error {
    public let title: String
    public let guidance: String
    /// The error code where the error type (or the CLI's mapping of it) defines one.
    public let code: String?
    /// The underlying description, for the Details disclosure.
    public let technical: String

    public init(title: String, guidance: String, code: String? = nil, technical: String = "") {
        self.title = title
        self.guidance = guidance
        self.code = code
        self.technical = technical
    }

    /// The message for `error`, or nil when nothing should be shown: renders the owner cancelled (GEN-3a).
    public static func describing(_ error: Error, activity: LibraryActivity, libraryName: String? = nil)
        -> LibraryMessage?
    {
        if let message = error as? LibraryMessage { return message }
        if let error = error as? NativeLibraryError {
            return library(error, activity: activity, name: libraryName)
        }
        if let error = error as? BlueprintCodecError { return codec(error, activity: activity) }
        if let error = error as? PreviewError { return preview(error) }
        if let error = error as? StatisticsError {
            return LibraryMessage(
                title: "Statistics can't be calculated for this blueprint",
                guidance: "It contains data that would make the totals misleading. The saved string is unchanged.",
                code: error.code, technical: error.description)
        }
        if let error = error as? AssetReleaseError {
            return LibraryMessage(
                title: "This folder isn't a usable asset release",
                guidance: "Choose a complete asset release folder in Settings. Previews and statistics need one; "
                    + "everything else works without it.",
                code: "INVALID_ASSET_RELEASE", technical: error.description)
        }
        if let error = error as? PrototypeMapError {
            return LibraryMessage(
                title: "The selected asset release can't provide statistics",
                guidance: "Choose a release with a valid prototype map in Settings. Previews are not affected.",
                code: "INVALID_PROTOTYPE_MAP", technical: error.description)
        }
        if let error = error as? PlannerRuntimeError {
            return LibraryMessage(
                title: "The preview couldn't be rendered",
                guidance: "The app's preview planner failed. Try again; if it keeps failing, reinstall the app.",
                technical: error.description)
        }
        return LibraryMessage(
            title: "Something went wrong",
            guidance: "Try again. If it keeps happening, close and reopen the library.",
            technical: String(describing: error))
    }

    /// One line for a listing issue in the Listing issues sheet (screen specs appendix).
    public static func listingIssue(code: String) -> String {
        let reason =
            switch code {
            case NativeLibraryError.integrity.code:
                "Another name in this folder is the same when letter case is ignored, or the item's .txt and "
                    + ".json files don't match."
            case NativeLibraryError.invalidMetadata.code:
                "The item's .json file is malformed or from an unsupported version."
            case NativeLibraryError.unsafePath.code: "This is a link, alias, special file, or unsupported name."
            case NativeLibraryError.ambiguousId.code: "Another item has the same ID."
            case NativeLibraryError.io(0).code: "The file couldn't be read."
            case "INVALID_SOURCE": "The item's .txt file isn't a valid blueprint string."
            default: "The item can't be used."
            }
        return reason + " Close the library before fixing it in Finder."
    }

    private static func library(_ error: NativeLibraryError, activity: LibraryActivity, name: String?)
        -> LibraryMessage
    {
        let named = name.map { "“\($0)”" } ?? "The library"
        func message(_ title: String, _ guidance: String) -> LibraryMessage {
            LibraryMessage(title: title, guidance: guidance, code: error.code, technical: error.description)
        }
        switch error {
        case .inUse:
            return message(
                "\(named) is in use", "Close the other app or cyano command that has it open, then try again.")
        case .closed:
            return message("The library is closed", "Open it again to continue.")
        case .unsupportedFilesystem:
            return message(
                "This location can't hold a library",
                "Choose a folder on a local drive outside iCloud Drive and other synchronized folders.")
        case .unsafePath:
            if activity == .opening || activity == .creating {
                return message(
                    "This folder can't be used as a library",
                    "It contains a link, alias, or special file where the library expects ordinary files.")
            }
            return message(
                "That folder or file can't be used",
                "It may have been moved or renamed outside the app, or be a link or alias. Close the library "
                    + "before fixing files in Finder.")
        case .invalidFormat:
            return message(
                "This folder isn't a library", "Choose a library folder, or an empty folder to create one.")
        case .unsupportedVersion:
            return message(
                "This library needs a newer version of the app", "Open it with a version that supports its format.")
        case .invalidMetadata:
            return message(
                "Information in the library can't be read",
                "A metadata file is malformed or from an unsupported version. Close the library and restore or "
                    + "remove the file in Finder.")
        case .integrity:
            return message(
                "Stored files don't match what was expected",
                "Nothing was overwritten. Close the library and check the affected files in Finder.")
        case .recoveryRequired:
            return message("\(named) needs recovery", "Choose Recover.")
        case .notFound:
            return message("The item no longer exists", "It may have been deleted. The list has been refreshed.")
        case .limitExceeded:
            switch activity {
            case .opening, .listing:
                return message(
                    "This library is too large to list",
                    "It exceeds the 100,000-entry or 256 MB listing limit. Close it, create a second library, and "
                        + "move some folders into the new library's library folder in Finder.")
            case .commenting:
                return message(
                    "The comment can't be saved", "Comments can be up to 64 KB, and an item up to 10,000 comments.")
            default:
                return message(
                    "A library limit was reached",
                    "If many interrupted operations are pending, run cyano staging-cleanup on this library "
                        + "with the library closed; otherwise the item or folder is too large for this change.")
            }
        case .invalidInput:
            return message(
                activity == .commenting ? "That comment can't be used" : "That name can't be used",
                activity == .commenting
                    ? "Comments can't be empty or only spaces."
                    : "Names can't be empty, start with a dot, or contain characters such as / or :.")
        case .nameCollision:
            return message(
                "That name already exists here",
                "Choose a different name. Names that differ only in letter case count as the same.")
        case .folderNotEmpty:
            return message("The folder isn't empty", "Move or delete its items first.")
        case .sourceChanged:
            return message(
                "The item changed while its preview was rendering", "Retry to render the current version.")
        case .ambiguousId:
            return message(
                "Two items share the same ID", "Close the library and remove one of the duplicate files in Finder.")
        case .io(let number):
            return LibraryMessage(
                title: "The disk operation failed",
                guidance: "Check that the drive is connected and has free space, then try again.",
                code: error.code, technical: "\(error.description) \(String(cString: strerror(number)))")
        }
    }

    private static func codec(_ error: BlueprintCodecError, activity: LibraryActivity) -> LibraryMessage {
        func message(_ title: String, _ guidance: String) -> LibraryMessage {
            LibraryMessage(
                title: title, guidance: guidance, code: "BLUEPRINT_CODEC_ERROR", technical: error.description)
        }
        switch error {
        case .invalidSource:
            return message(
                "This isn't a blueprint string",
                activity == .importing || activity == .changing
                    ? "Copy the whole string from the game and try again." : "The saved string can't be read.")
        case .limitExceeded(let limit):
            let limitName =
                switch limit {
                case .sourceBytes: "16 MB string size"
                case .decodedBytes: "64 MB decoded size"
                case .jsonDepth: "nesting depth"
                case .bookDepth: "32-level book nesting"
                case .entries: "10,000-entry"
                case .entitiesAndTiles: "100,000 entities and tiles"
                case .jsonNodes: "data size"
                }
            return message(
                "This blueprint exceeds the \(limitName) limit", "Split it into smaller blueprints in the game.")
        case .invalidEntryPath:
            return message("That entry is no longer in the book", "The book may have been replaced. Select it again.")
        case .invalidLimits, .compressionFailure:
            return message("The blueprint couldn't be processed", "Try again. If it keeps failing, restart the app.")
        }
    }

    private static func preview(_ error: PreviewError) -> LibraryMessage? {
        func message(_ title: String, _ guidance: String) -> LibraryMessage {
            LibraryMessage(title: title, guidance: guidance, code: error.code, technical: error.description)
        }
        switch error {
        case .cancelled:
            return nil
        case .invalidInput:
            return message("The preview couldn't be rendered", "This entry can't be previewed.")
        case .invalidDrawList, .workerProtocol, .workerFailed:
            return message("The preview couldn't be rendered", "The renderer stopped unexpectedly. Try again.")
        case .assetDecode:
            return message(
                "The preview couldn't be rendered",
                "An image in the asset release couldn't be read. Check the release in Settings.")
        case .imageAllocation, .imageEncoding:
            return message("The preview couldn't be rendered", "The image couldn't be created. Try again.")
        case .timedOut:
            return message("The preview took too long", "Large blueprints can take a while. Try again.")
        case .memoryLimit:
            return message(
                "The preview needed too much memory", "This blueprint is too large to preview at this size.")
        case .workerBusy:
            return message("Another preview is still rendering", "Try again in a moment.")
        }
    }
}
