import FactorioData
import Foundation
import Testing

@testable import LibraryApp
@_spi(Testing) @testable import LibraryCore

private struct SettingsFixture {
    let parent: URL
    let suite: String
    let defaults: UserDefaults

    init() throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fb-native-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        suite = "local.fb.library.tests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: parent)
    }
}

@MainActor
@Suite("Asset settings", .serialized)
struct AssetSettingsTests {
    @Test("SET-1, SET-4: a chosen release is verified, remembered, and re-verified at the next launch")
    func chooseAndRelaunch() async throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanup() }
        let release = try AppTestAssetRelease(in: fixture.parent)
        let settings = AssetSettings(defaults: fixture.defaults)
        #expect(settings.state == .none)
        guard case .failure(let none) = settings.availability(for: nil) else {
            Issue.record("no release should be unavailable")
            return
        }
        #expect(none.title == "No asset release is configured")
        await settings.choose(release.root, library: nil)
        guard case .verified(let url, let name, let version, _) = settings.state else {
            Issue.record("\(settings.state)")
            return
        }
        #expect(url == release.root && name == "test-release" && version == "2.1.24")
        #expect(settings.choiceFailure == nil && settings.revision == 1 && settings.verifiedURL == release.root)

        let relaunched = AssetSettings(defaults: fixture.defaults)
        guard case .checking = relaunched.state else {
            Issue.record("\(relaunched.state)")
            return
        }
        await relaunched.verifySaved()
        guard case .verified = relaunched.state else {
            Issue.record("\(relaunched.state)")
            return
        }

        try FileManager.default.removeItem(at: release.root)
        let missing = AssetSettings(defaults: fixture.defaults)
        await missing.verifySaved()
        guard case .problem(_, let message) = missing.state else {
            Issue.record("\(missing.state)")
            return
        }
        #expect(message.title == "The asset release folder is missing")
    }

    @Test("SET-2: an invalid folder is refused with its reason and the previous release stays")
    func invalidKeepsPrevious() async throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanup() }
        let release = try AppTestAssetRelease(in: fixture.parent)
        let settings = AssetSettings(defaults: fixture.defaults)
        await settings.choose(release.root, library: nil)
        let raw = fixture.parent.appendingPathComponent("Raw sprites")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: false)
        try Data("not a release".utf8).write(to: raw.appendingPathComponent("atlas.webp"))
        await settings.choose(raw, library: nil)
        #expect(
            settings.choiceFailure?.title == "This folder isn't a usable asset release",
            "\(String(describing: settings.choiceFailure))")
        #expect(settings.verifiedURL == release.root && settings.revision == 1)
        #expect(
            fixture.defaults.string(forKey: AssetSettings.pathKey) == RecentLibraryStore.normalizedPath(release.root))
    }

    @Test("SET-3: a release inside the library, or containing it, is refused and never used")
    func overlap() async throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanup() }
        let library = fixture.parent.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: false)
        let inside = try AppTestAssetRelease(in: library, name: "Assets")
        let settings = AssetSettings(defaults: fixture.defaults)
        await settings.choose(inside.root, library: library)
        #expect(settings.choiceFailure == AssetSettings.overlapMessage && settings.state == .none)
        await settings.choose(inside.root, library: nil)
        guard case .failure(let refused) = settings.availability(for: library) else {
            Issue.record("an overlapping release was offered")
            return
        }
        #expect(refused == AssetSettings.overlapMessage)
        guard case .success = settings.availability(for: fixture.parent.appendingPathComponent("Elsewhere")) else {
            Issue.record("a separate library could not use the release")
            return
        }
        #expect(AssetSettings.overlaps(fixture.parent, library))
        #expect(!AssetSettings.overlaps(library, fixture.parent.appendingPathComponent("Elsewhere")))
    }

    @Test("SET-5, SET-5a, SET-6: the prototype map loads once per release; changing or clearing the release resets it")
    func prototypeMapOnce() async throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanup() }
        let first = try AppTestAssetRelease(in: fixture.parent, name: "First")
        let second = try AppTestAssetRelease(in: fixture.parent, name: "Second")
        let settings = AssetSettings(defaults: fixture.defaults)
        await settings.choose(first.root, library: nil)
        let loaded = await settings.prototypeMap()
        guard case .success = loaded, case .success = await settings.prototypeMap() else {
            Issue.record("the map did not load: \(loaded)")
            return
        }
        #expect(settings.mapLoads == 1)
        await settings.choose(second.root, library: nil)
        _ = await settings.prototypeMap()
        #expect(settings.mapLoads == 2 && settings.revision == 2)
        settings.clear()
        #expect(settings.state == .none && settings.revision == 3)
        #expect(fixture.defaults.string(forKey: AssetSettings.pathKey) == nil)
        guard case .failure(let message) = await settings.prototypeMap() else {
            Issue.record("a cleared release still gave a map")
            return
        }
        #expect(message.title == "No asset release is configured")
    }

    @Test("STA-6: a release whose prototype map is unsuitable verifies but cannot give statistics")
    func unsuitableMap() async throws {
        let fixture = try SettingsFixture()
        defer { fixture.cleanup() }
        let release = try AppTestAssetRelease(in: fixture.parent, mapLoads: false)
        let settings = AssetSettings(defaults: fixture.defaults)
        await settings.choose(release.root, library: nil)
        let result = await settings.prototypeMap()
        guard case .verified = settings.state, case .failure(let message) = result else {
            Issue.record("\(settings.state) \(result)")
            return
        }
        #expect(message.title == "The selected asset release can't provide statistics")
    }
}
