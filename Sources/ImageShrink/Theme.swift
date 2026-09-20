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
    static let saved = Color(red: 0.204, green: 0.780, blue: 0.349)
    /// A file that could not reach the limit. Never a failure tone.
    static let attention = Color(red: 1.0, green: 0.624, blue: 0.039)
    /// Reserved for moving originals to Trash. Nothing else.
    static let destructive = Color(red: 1.0, green: 0.271, blue: 0.227)

    /// The prototype's number: the capsule slides in 220 ms and every row re-estimates in
    /// place, with no spinner and no reload. A timing curve rather than a spring — a spring
    /// puts most of the travel in the first third, which reads as a jump (measured: the
    /// capsule had arrived by 100 ms).
    static let limitChange = Animation.easeInOut(duration: 0.22)
    /// Numbers and bars settling after an estimate changes, a touch behind the capsule.
    static let numbers = Animation.easeInOut(duration: 0.26)

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
        content.background(fill, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }

    private var fill: Color {
        if contrast == .increased {
            return scheme == .dark ? Color(white: 0.16) : Color(white: 0.98)
        }
        return scheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.65)
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
