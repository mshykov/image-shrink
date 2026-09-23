import AppKit
import SwiftUI

/// Click, press the keys, done — the way a shortcut is set in every Mac app that has one.
struct ShortcutField: View {
    @State private var shortcut = Shortcut.current
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button { isRecording ? stop() : start() } label: {
            Group {
                if isRecording {
                    Text("Press keys\u{2026}").foregroundStyle(.secondary)
                } else if let shortcut {
                    HStack(spacing: 3) {
                        ForEach(shortcut.caps, id: \.self) { KeyCap($0) }
                    }
                } else {
                    Text("Record shortcut").foregroundStyle(.secondary)
                }
            }
            .font(Theme.control)
            .lineLimit(1)
            .frame(minWidth: 110)
            .padding(.horizontal, Theme.snug)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .fill(Color.primary.opacity(isRecording ? 0.16 : 0.10)))
            .overlay {
                if isRecording {
                    RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(FlatButton())
        .help(shortcut == nil ? "Record a shortcut" : "Change the shortcut")
        .accessibilityLabel(shortcut.map { "Shortcut \($0.display), click to change" }
                            ?? "Record a shortcut")
        .onDisappear { stop() }
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil }
            // Escape leaves it alone; delete clears it.
            if event.keyCode == 53 { stop(); return nil }
            if event.keyCode == 51 || event.keyCode == 117 {
                Shortcut.set(nil)
                shortcut = nil
                stop()
                return nil
            }
            if let recorded = Shortcut.from(event) {
                Shortcut.set(recorded)
                shortcut = recorded
                stop()
            }
            return nil    // swallow the keys while recording
        }
    }

    private func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
