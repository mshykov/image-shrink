import AppKit
import SwiftUI

/// The whole interface for a conversion that never opens a window: a floating panel under
/// the menu bar that reports progress and then gets out of the way.
@MainActor
final class ConversionHUD {
    enum Phase: Equatable {
        case converting
        case finished(before: Int, after: Int)
        case incomplete(converted: Int, message: String)
    }

    @MainActor
    final class State: ObservableObject {
        @Published var total: Int
        @Published var done = 0
        @Published var phase: Phase = .converting
        @Published var currentName = ""
        var outputs: [URL] = []
        var onStop: (() -> Void)?
        var onShow: (() -> Void)?

        init(total: Int) { self.total = total }
    }

    private let state: State
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?
    /// Long enough to read, short enough not to be in the way.
    private let lingerSeconds = 6.0

    init(total: Int, onStop: (() -> Void)? = nil) {
        state = State(total: total)
        state.onStop = onStop
        state.onShow = { [weak self] in
            guard let self, !self.state.outputs.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(self.state.outputs)
        }
    }

    func show() {
        guard panel == nil else { return }
        let hosting = NSHostingView(rootView: HUDView(state: state))
        hosting.frame = NSRect(x: 0, y: 0, width: 440, height: 78)

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        position(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func advance(done: Int, latest: URL?) {
        state.done = done
        if let latest {
            state.outputs.append(latest)
            state.currentName = latest.lastPathComponent
        }
    }

    func working(on name: String) {
        state.currentName = name
    }

    func finish(before: Int, after: Int) {
        state.phase = .finished(before: before, after: after)
        state.done = state.total
        scheduleDismissal()
    }

    func incomplete(converted: Int, message: String) {
        state.phase = .incomplete(converted: converted, message: message)
        scheduleDismissal(after: lingerSeconds * 2)
    }

    func dismiss() {
        dismissal?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    private func scheduleDismissal(after seconds: Double? = nil) {
        dismissal?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (seconds ?? lingerSeconds), execute: work)
    }

    /// Top right, under the menu bar, above every window — where the design puts it.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(x: frame.maxX - size.width - 16,
                                     y: frame.maxY - size.height - 8))
    }
}

private struct HUDView: View {
    @ObservedObject var state: ConversionHUD.State

    var body: some View {
        HStack(spacing: Theme.normal) {
            badge
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.rowTitle)
                Text(detail)
                    .font(Theme.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.snug)
            action
        }
        .padding(.horizontal, Theme.wide)
        .padding(.vertical, Theme.normal)
        .frame(width: 440, height: 78)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch state.phase {
        case .converting:
            ProgressView(value: Double(state.done), total: Double(max(1, state.total)))
                .progressViewStyle(.circular)
                .controlSize(.small)
                .frame(width: 28, height: 28)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white, Theme.saved)
        case .incomplete:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white, Theme.attention)
        }
    }

    private var title: String {
        switch state.phase {
        case .converting:
            return "Converting ^[\(state.total) image](inflect: true) \u{2014} \(state.done) of \(state.total)"
        case .finished:
            return "^[\(state.total) image](inflect: true) ready"
        case .incomplete(let converted, _):
            return "\(converted) of \(state.total) converted"
        }
    }

    private var detail: String {
        switch state.phase {
        case .converting:
            return state.currentName.isEmpty ? "Working\u{2026}" : state.currentName
        case .finished(let before, let after):
            let saved = max(0, before - after)
            return "\(Format.bytes(before)) \u{2192} \(Format.bytes(after))"
                 + (saved > 0 ? " \u{00B7} saved \(Format.bytes(saved))" : "")
        case .incomplete(_, let message):
            return message
        }
    }

    @ViewBuilder
    private var action: some View {
        switch state.phase {
        case .converting:
            if state.onStop != nil {
                Button { state.onStop?() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 11))
                }
                .buttonStyle(SecondaryButton(compact: true))
                .accessibilityLabel("Stop")
            }
        case .finished:
            Button("Show") { state.onShow?() }
                .buttonStyle(SecondaryButton())
        case .incomplete:
            EmptyView()
        }
    }
}
