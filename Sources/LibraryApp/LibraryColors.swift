import AppKit
import SwiftUI

/// The app's two custom colors (screen specs, "Color and contrast"); everything else uses system colors.
extension Color {
    /// Item list, inspector, preview, and sheet content: the system control background in light mode, and
    /// `#121212` in dark mode for slightly higher contrast than the system `#1E1E1E`.
    static let contentBackground = Color(nsColor: .contentBackground)
}

extension NSColor {
    static let contentBackground = NSColor(name: "contentBackground") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, alpha: 1)
            : .controlBackgroundColor
    }
}
