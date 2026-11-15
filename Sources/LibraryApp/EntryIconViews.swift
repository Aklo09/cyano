import CoreGraphics
import LibraryCore
import PreviewRenderer
import SwiftUI

extension EnvironmentValues {
    /// Icons from the configured release, or nil without a usable one (spec ICN-3, ICN-10).
    @Entry var iconCatalog: IconCatalog? = nil
}

/// Where the game draws an entry's icons on its square symbol, following fpsr's blueprint layout
/// (`tools/vendor/fpsr/packages/renderer/src/blueprint-icons.ts`): one icon is 48/64 of the tile, centred; two to
/// four are 28/64 each, packed in slot order into a 2 × 2 grid with a 4/64 gap (spec ICN-2).
public enum EntryIconLayout {
    /// Frames for `count` icons (1 to 4) on a square tile of side `tile`, top-left origin, in slot order.
    public static func frames(count: Int, tile: CGFloat) -> [CGRect] {
        let unit = tile / 64
        guard count > 1 else {
            return count == 1 ? [CGRect(x: 8 * unit, y: 8 * unit, width: 48 * unit, height: 48 * unit)] : []
        }
        let size = 28 * unit
        let near = 16 * unit - size / 2
        let far = 48 * unit - size / 2
        let middle = 32 * unit - size / 2
        let origins: [CGPoint] =
            switch min(count, 4) {
            case 2: [CGPoint(x: near, y: middle), CGPoint(x: far, y: middle)]
            case 3: [CGPoint(x: near, y: near), CGPoint(x: far, y: near), CGPoint(x: near, y: far)]
            default:
                [
                    CGPoint(x: near, y: near), CGPoint(x: far, y: near), CGPoint(x: near, y: far),
                    CGPoint(x: far, y: far),
                ]
            }
        return origins.map { CGRect(origin: $0, size: CGSize(width: size, height: size)) }
    }

    /// What VoiceOver reads for an entry's icons, for example "iron plate, rare; copper cable" (screen specs,
    /// "Accessibility"); empty without icons.
    public static func spokenNames(_ icons: [EntryIcon]) -> String {
        icons.map { icon in
            var words = icon.name.replacingOccurrences(of: "-", with: " ")
            if let quality = icon.quality, quality != "normal" { words += ", " + quality }
            return words
        }
        .joined(separator: "; ")
    }
}

/// One icon from the release with its quality badge in the bottom-left corner, at half its size.
private struct SignalIcon: View {
    let image: CGImage
    let badge: CGImage?
    let size: CGFloat

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .overlay(alignment: .bottomLeading) {
                if let badge {
                    Image(decorative: badge, scale: 1).resizable().interpolation(.high)
                        .frame(width: size / 2, height: size / 2)
                }
            }
    }
}

/// A list row's leading symbols: the kind symbol, then the entry icons in stored order at text height; icons the
/// release lacks are left out (spec ICN-1, ICN-3, ICN-4). Hidden from VoiceOver; the row's label names the icons.
struct EntryIconStrip: View {
    let kind: ItemKind
    let icons: [EntryIcon]
    /// The icons' height; the list makes every row tall enough for it.
    let size: CGFloat
    @Environment(\.iconCatalog) private var catalog

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: kind.symbol)
            if let catalog {
                ForEach(Array(icons.enumerated()), id: \.offset) { _, icon in
                    if let reference = IconReference(signalType: icon.type, name: icon.name),
                        let image = catalog.image(for: reference)
                    {
                        SignalIcon(image: image, badge: catalog.qualityBadge(icon.quality), size: size)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The inspector header's symbol: the entry icons as the game arranges them, or the kind symbol when the entry has
/// none, no release is configured, or none of its icons is in the release (spec ICN-2 to ICN-4).
struct EntryIconTile: View {
    let kind: ItemKind
    let icons: [EntryIcon]
    let side: CGFloat
    @Environment(\.iconCatalog) private var catalog

    var body: some View {
        let images = icons.prefix(4).map { icon -> (CGImage, CGImage?)? in
            guard let catalog, let reference = IconReference(signalType: icon.type, name: icon.name),
                let image = catalog.image(for: reference)
            else { return nil }
            return (image, catalog.qualityBadge(icon.quality))
        }
        ZStack(alignment: .topLeading) {
            if images.contains(where: { $0 != nil }) {
                let frames = EntryIconLayout.frames(count: images.count, tile: side)
                ForEach(Array(zip(frames, images).enumerated()), id: \.offset) { _, pair in
                    // A slot whose icon the release lacks stays empty (ICN-4).
                    if let (image, badge) = pair.1 {
                        SignalIcon(image: image, badge: badge, size: pair.0.width)
                            .offset(x: pair.0.minX, y: pair.0.minY)
                    }
                }
            } else {
                Image(systemName: kind.symbol)
                    .resizable()
                    .scaledToFit()
                    .padding(side / 8)
                    .frame(width: side, height: side)
            }
        }
        .frame(width: side, height: side, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}
