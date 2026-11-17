import Foundation

/// The app's preferences domain. Scripted and test launches pass `-CyanoDefaultsSuite <name>` so they never read
/// or change the owner's recent libraries or reopen their library.
public enum LibraryPreferences {
    public static let suiteArgument = "CyanoDefaultsSuite"

    public static func defaults(_ standard: UserDefaults = .standard) -> UserDefaults {
        guard let suite = standard.string(forKey: suiteArgument), !suite.isEmpty,
            let isolated = UserDefaults(suiteName: suite)
        else { return standard }
        return isolated
    }
}

/// A library the owner opened before, newest first in the recent list.
public struct RecentLibrary: Codable, Equatable, Sendable, Identifiable {
    public let path: String
    public let lastOpened: Date
    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

/// Recent libraries and the library to reopen at launch, kept in the app's preferences (LIB-3, LIB-4, LIB-11).
@MainActor
public final class RecentLibraryStore {
    static let recentsKey = "recentLibraries"
    static let reopenKey = "reopenLibraryPath"
    static let limit = 10

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var recents: [RecentLibrary] {
        guard let data = defaults.data(forKey: Self.recentsKey),
            let decoded = try? JSONDecoder().decode([RecentLibrary].self, from: data)
        else { return [] }
        return decoded
    }

    /// The library that was open when the app last quit, if the owner did not close it.
    public var reopenPath: String? {
        get { defaults.string(forKey: Self.reopenKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.reopenKey)
            } else {
                defaults.removeObject(forKey: Self.reopenKey)
            }
        }
    }

    /// Moves `url` to the top of the recent list.
    public func record(_ url: URL, at date: Date = Date()) {
        let path = Self.normalizedPath(url)
        let updated = [RecentLibrary(path: path, lastOpened: date)] + recents.filter { $0.path != path }
        save(Array(updated.prefix(Self.limit)))
    }

    public func remove(_ path: String) {
        save(recents.filter { $0.path != path })
        if reopenPath == path { reopenPath = nil }
    }

    public func clear() {
        save([])
    }

    /// Whether a recent library's folder is reachable now; an unmounted volume or a removed folder is not.
    public static func isAvailable(_ path: String) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory.boolValue
    }

    /// One spelling per folder: standardized, symlinks resolved, no trailing slash.
    public static func normalizedPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func save(_ entries: [RecentLibrary]) {
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: Self.recentsKey) }
    }
}
