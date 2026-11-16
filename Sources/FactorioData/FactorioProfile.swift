/// Initial qualification profile, matching the existing prepared private assets.
public struct FactorioProfile: Codable, Equatable, Sendable {
    public let gameVersion: String
    public let mods: [String]
    public let assetSchema: Int
    public let prototypeMapSchema: Int

    public static let initial = FactorioProfile(
        gameVersion: "2.1.24",
        mods: ["base", "elevated-rails", "quality", "recycler", "space-age"],
        assetSchema: 2,
        prototypeMapSchema: 2
    )
}
