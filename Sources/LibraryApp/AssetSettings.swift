import FactorioData
import Foundation
import LibraryCore
import Observation

/// The asset release previews and statistics use (spec SET-1 to SET-6; screen specs, "Settings").
/// Everything else in the app works without one.
@MainActor @Observable
public final class AssetSettings {
    /// The configured release as the app last checked it.
    public enum State: Equatable, Sendable {
        case none
        case checking(URL)
        case verified(URL, name: String, gameVersion: String, identity: String)
        /// Configured but unusable now (missing, changed, or failing verification); `message` says why.
        case problem(URL, LibraryMessage)
    }

    public private(set) var state: State = .none
    /// A folder being checked after Choose…, while the previous release stays active (SET-1).
    public private(set) var candidate: URL?
    /// Why the last chosen folder was refused; the previous setting is kept (SET-2, SET-3).
    public private(set) var choiceFailure: LibraryMessage?
    /// Increases whenever the active release changes, so previews and statistics reload (SET-5a).
    public private(set) var revision = 0

    static let pathKey = "assetReleasePath"
    private let defaults: UserDefaults
    private var choice = 0
    /// The prototype map, loaded once per verified release (SET-5).
    private var map: (identity: String, map: PrototypeMap)?
    private var mapTask: Task<Result<PrototypeMap, LibraryMessage>, Never>?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        if let path = defaults.string(forKey: Self.pathKey) {
            state = .checking(URL(fileURLWithPath: path, isDirectory: true))
        }
    }

    /// The release URL when it verified, else nil.
    public var verifiedURL: URL? {
        if case .verified(let url, _, _, _) = state { return url }
        return nil
    }

    /// Re-verifies the saved release at launch; a missing or changed folder becomes a problem (SET-4).
    public func verifySaved() async {
        guard case .checking(let url) = state else { return }
        state = await Self.check(url)
        revision += 1
    }

    /// Checks a chosen folder and makes it active only if it verifies and does not overlap `library` (SET-1 to SET-3).
    public func choose(_ url: URL, library: URL?) async {
        choice += 1
        let current = choice
        choiceFailure = nil
        if let library, Self.overlaps(url, library) {
            choiceFailure = Self.overlapMessage
            return
        }
        candidate = url
        let checked = await Self.check(url)
        guard current == choice else { return }
        candidate = nil
        switch checked {
        case .verified:
            state = checked
            defaults.set(RecentLibraryStore.normalizedPath(url), forKey: Self.pathKey)
            map = nil
            mapTask = nil
            revision += 1
        case .problem(_, let message):
            choiceFailure = message
        default:
            break
        }
    }

    /// Stops waiting for a folder being checked; the previous setting stays.
    public func cancelChoice() {
        choice += 1
        candidate = nil
    }

    /// Previews and statistics become unavailable; everything else keeps working (SET-6).
    public func clear() {
        choice += 1
        candidate = nil
        choiceFailure = nil
        state = .none
        defaults.removeObject(forKey: Self.pathKey)
        map = nil
        mapTask = nil
        revision += 1
    }

    /// The release previews and statistics may use with `library` open, or why there is none.
    public func availability(for library: URL?) -> Result<URL, LibraryMessage> {
        switch state {
        case .none:
            return .failure(Self.noneMessage)
        case .checking:
            return .failure(LibraryMessage(title: "Checking the asset release…", guidance: "This takes a moment."))
        case .problem(_, let message):
            return .failure(message)
        case .verified(let url, _, _, _):
            if let library, Self.overlaps(url, library) { return .failure(Self.overlapMessage) }
            return .success(url)
        }
    }

    /// The prototype map for statistics, loaded at most once per release and session (SET-5, STA-6).
    public func prototypeMap() async -> Result<PrototypeMap, LibraryMessage> {
        guard case .verified(let url, _, _, let identity) = state else {
            return .failure(availabilityMessage)
        }
        if let map, map.identity == identity { return .success(map.map) }
        let task: Task<Result<PrototypeMap, LibraryMessage>, Never>
        if let mapTask {
            task = mapTask
        } else {
            task = Task.detached {
                do { return .success(try PrototypeMap.load(release: url)) } catch {
                    return .failure(
                        LibraryMessage.describing(error, activity: .statistics)
                            ?? LibraryMessage(title: "Statistics are unavailable", guidance: "Try again."))
                }
            }
            mapTask = task
        }
        let result = await task.value
        mapTask = nil
        guard case .verified(_, _, _, let still) = state, still == identity else {
            return .failure(availabilityMessage)
        }
        switch result {
        case .success(let loaded):
            map = (identity, loaded)
            mapLoads += 1
            return .success(loaded)
        case .failure(let message):
            return .failure(message)
        }
    }

    /// How many times the prototype map was loaded; tests check it loads once (SET-5).
    public private(set) var mapLoads = 0

    private var availabilityMessage: LibraryMessage {
        if case .failure(let message) = availability(for: nil) { return message }
        return Self.noneMessage
    }

    static let noneMessage = LibraryMessage(
        title: "No asset release is configured",
        guidance: "Previews and statistics need one. Choose it in Settings; everything else works without it.")

    static let overlapMessage = LibraryMessage(
        title: "The asset release can't be inside the library folder, or contain it",
        guidance: "Keep the asset release in its own folder outside the library.")

    /// Whether the folders are the same or one contains the other, after resolving links.
    static func overlaps(_ release: URL, _ library: URL) -> Bool {
        let a = RecentLibraryStore.normalizedPath(release)
        let b = RecentLibraryStore.normalizedPath(library)
        return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }

    /// Verifies a release folder off the main thread.
    static func check(_ url: URL) async -> State {
        await Task.detached { () -> State in
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .problem(
                    url,
                    LibraryMessage(
                        title: "The asset release folder is missing",
                        guidance: "Choose it again in Settings, or clear the setting."))
            }
            do {
                let report = try AssetRelease.verify(at: url)
                return .verified(
                    url, name: report.id, gameVersion: report.profile.gameVersion, identity: report.identity)
            } catch {
                // Any failure means the folder is not a release; missing files arrive as errno failures too.
                let described = LibraryMessage.describing(error, activity: .verifyingAssets)
                return .problem(
                    url,
                    LibraryMessage(
                        title: "This folder isn't a usable asset release",
                        guidance: "Choose a folder assembled by the asset tools, with release.json, sprites, and "
                            + "statistics.",
                        code: described?.code ?? "INVALID_ASSET_RELEASE",
                        technical: described?.technical ?? String(describing: error)))
            }
        }.value
    }
}
