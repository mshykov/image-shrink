import AppKit
import SwiftUI

/// The design system: three glass layers, one accent, five text sizes, concentric radii.
/// Everything visual reads its numbers from here.
enum Theme {
    // Geometry — window 16 → panel 14 → row 12 → field 8, so corners stay concentric.
    static let windowRadius: CGFloat = 16
    static let panelRadius: CGFloat = 14
    static let rowRadius: CGFloat = 12
    static let fieldRadius: CGFloat = 8

    // Spacing runs 6 · 10 · 12 · 16 · 24.
    static let tight: CGFloat = 6
    static let snug: CGFloat = 10
    static let normal: CGFloat = 12
    static let wide: CGFloat = 16
    static let loose: CGFloat = 24

    /// Only on numbers that went down, and on finished rows.
    static let saved = dynamic(dark: (0.204, 0.780, 0.349), light: (0.141, 0.541, 0.239))
    /// A file that could not reach the limit. Never a failure tone.
    static let attention = dynamic(dark: (1.0, 0.624, 0.039), light: (0.706, 0.396, 0.0))
    /// Reserved for moving originals to Trash. Nothing else.
    static let destructive = dynamic(dark: (1.0, 0.271, 0.227), light: (0.843, 0.0, 0.082))

    /// The prototype's colours are the dark-mode ones; on white they lose too much contrast,
    /// so each has the darker sibling macOS itself uses in the light appearance.
    private static func dynamic(dark: (Double, Double, Double),
                                light: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }

    /// The prototype's number: the capsule slides in 220 ms and every row re-estimates in
    /// place, with no spinner and no reload. A timing curve rather than a spring — a spring
    /// puts most of the travel in the first third, which reads as a jump (measured: the
    /// capsule had arrived by 100 ms).
    static let limitChange = Animation.easeInOut(duration: 0.22)
    /// Numbers and bars settling after an estimate changes, a touch behind the capsule.
    static let numbers = Animation.easeInOut(duration: 0.26)

    /// The third text tier. The system sets three — 95 / 62 / 52 % — and 52 % is the floor;
    /// SwiftUI's `.tertiary` sits below it and captions stop reading, most visibly on white.
    /// 52 % measures 3.3:1 — where macOS puts its own dim labels, and under WCAG AA — so
    /// Increase Contrast lifts the tier, the way the content panel already lightens.
    static func caption(_ contrast: ColorSchemeContrast) -> Color {
        Color.primary.opacity(contrast == .increased ? 0.60 : 0.52)
    }

    // Type — size / weight pairs, all system font so the app follows the user's text size.
    static let display = Font.system(size: 24, weight: .semibold)
    static let action = Font.system(size: 13, weight: .semibold)
    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let control = Font.system(size: 12.5, weight: .medium)
    static let meta = Font.system(size: 11.5, weight: .regular)
}

/// L2 · content panel. A flat fill, never glass: glass must not sit on glass.
struct ContentPanel: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        content
            .background(fill, in: shape)
            .overlay {
                if scheme == .light {
                    shape.strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                }
            }
    }

    private var fill: Color {
        if contrast == .increased {
            return scheme == .dark ? Color(white: 0.16) : Color(white: 1.0)
        }
        // On white the panel needs to be lighter than the window, not a wash over it.
        return scheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.92)
    }
}

extension View {
    func contentPanel() -> some View { modifier(ContentPanel()) }

    /// Whole strings fade into each other instead of swapping in one frame.
    @ViewBuilder
    func crossfadeText() -> some View {
        if #available(macOS 14.0, *) {
            contentTransition(.opacity)
        } else {
            self
        }
    }

    /// Digits roll instead of snapping, where the system can do it.
    @ViewBuilder
    func numericTransition() -> some View {
        if #available(macOS 14.0, *) {
            contentTransition(.numericText())
        } else {
            self
        }
    }

    /// Numbers stop jittering while they update.
    func tabularNumbers() -> some View { monospacedDigit() }
}
