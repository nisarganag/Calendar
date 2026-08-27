import SwiftUI
import AppKit

// MARK: - Design tokens
//
// The panel has no colour theme. Glass is left untinted so it shows whatever is
// actually behind it — wallpaper, a window, a video — and keeps changing as that
// changes. Tinting the material replaces real transmission with a wash, which is
// the thing that stops glass reading as glass.
//
// So the only "colour" here is ink: the label colour, and its inverse for the one
// chip that has to be findable in a glance. Everything else is transparency,
// weight, and the material's own specular edge.

enum Cal {

    // MARK: Ink

    /// Fill for the today chip — near-white in dark, near-black in light. The
    /// highest-contrast achromatic value available, so today is unmistakable
    /// without borrowing a hue.
    static let ink = adaptive(dark: 0xF4F7F9, light: 0x14181C)

    /// Text and glyphs sitting on top of `ink`.
    static let inkContrast = adaptive(dark: 0x0A0E12, light: 0xFFFFFF)

    /// Neutral near-black, used only for shadow and the underside of a specular
    /// edge. Never a fill.
    static let abyss = adaptive(dark: 0x000000, light: 0x0C1014)

    // MARK: Metrics

    static let panelWidth: CGFloat = 328
    static let cellHeight: CGFloat = 33
    static let cellRadius: CGFloat = 11
    static let cardRadius: CGFloat = 20

    // MARK: Type
    //
    // Rounded display for anything a person reads as a word, system text for
    // body copy, and a wide-tracked uppercase utility face for labels. Every
    // number is monospaced: in a seven-column grid, proportional digits make the
    // ones column visibly ragged, and the grid is the whole point of a calendar.

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func digits(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func utility(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    // MARK: Helpers

    /// Builds a colour that resolves differently in light and dark appearances,
    /// so ink stays legible against untinted glass in both.
    static func adaptive(dark: UInt32, light: UInt32) -> Color {
        adaptive(dark: dark, darkAlpha: 1, light: light, lightAlpha: 1)
    }

    static func adaptive(dark: UInt32, darkAlpha: Double,
                         light: UInt32, lightAlpha: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light,
                           alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: CGFloat(alpha)
        )
    }
}
