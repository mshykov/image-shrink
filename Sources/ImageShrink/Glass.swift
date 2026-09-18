import AppKit
import SwiftUI

// Liquid Glass (macOS 26) with a material fallback, so the app still builds and looks
// right on 13–15. Apple's guidance: glass belongs to the control layer floating above
// content — never glass on glass, and never behind text that has to stay readable.

@available(macOS 26.0, *)
private func makeGlass(tint: Color?, interactive: Bool) -> Glass {
    var glass = Glass.regular
    if let tint { glass = glass.tint(tint) }
    if interactive { glass = glass.interactive() }
    return glass
}

extension View {
    @ViewBuilder
    func liquidGlass(_ shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(makeGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// Lets the window material show through a Form or List.
    func clearScrollBackground() -> some View {
        scrollContentBackground(.hidden)
    }
}

/// Groups neighbouring glass elements so they blend into each other instead of stacking.
@ViewBuilder
func GlassGroup<Content: View>(spacing: CGFloat = 12,
                               @ViewBuilder content: @escaping () -> Content) -> some View {
    if #available(macOS 26.0, *) {
        GlassEffectContainer(spacing: spacing) { content() }
    } else {
        content()
    }
}

/// The window wash the glass refracts. `behindWindow` samples the desktop underneath.
struct WindowBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

extension NSWindow {
    /// Window chrome that lets the material and the glass controls read as one surface.
    func applyGlassChrome() {
        // No .fullSizeContentView: with it the scrolling form lays out under the titlebar
        // and comes out blank (verified with --snapshot). Transparent titlebar alone lets
        // the window material below run into it without a seam.
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
    }
}
