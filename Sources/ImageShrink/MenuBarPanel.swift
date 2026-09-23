import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// L3 · floating. The panel behind the menu bar icon: pick a limit, drop images, see what
/// was converted lately, and only then, if you must, open the window.
struct MenuBarPanel: View {
    @ObservedObject var model: AppModel
    let openWindow: () -> Void
    let dropped: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.normal) {
            HStack {
                Text("Image Shrink").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { openSettings() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Settings")
            }

            LimitPicker().environmentObject(model)

            dropZone

            if !History.recent.isEmpty {
                history
            }

            HStack(spacing: Theme.snug) {
                Button("Open Window") { openWindow() }
                    .buttonStyle(SecondaryButton())
                    .frame(maxWidth: .infinity)
                Button("Quit") { NSApp?.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(Theme.meta)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.wide)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .foregroundStyle(isTargeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            .frame(height: 84)
            .overlay {
                VStack(spacing: Theme.tight) {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                    Text("Drop images or a folder on the menu bar icon")
                        .font(Theme.meta)
                        .foregroundStyle(.secondary)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                load(providers)
                return true
            }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: Theme.tight) {
            Text(History.groupTitle(for: History.recent[0].date))
                .font(Theme.meta)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(History.recent.prefix(4)) { batch in
                    HStack {
                        Text("^[\(batch.count) image](inflect: true)").font(Theme.control)
                        Spacer()
                        Text("\(Format.bytes(batch.before)) \u{2192} \(Format.bytes(batch.after))")
                            .font(Theme.meta)
                            .foregroundStyle(.secondary)
                            .tabularNumbers()
                    }
                    .padding(.horizontal, Theme.snug)
                    .padding(.vertical, Theme.tight)
                    if batch.id != History.recent.prefix(4).last?.id {
                        Divider().opacity(0.3)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(Color.primary.opacity(0.06)))
        }
    }

    private func load(_ providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                urls.append(url)
            }
        }
        group.notify(queue: .main) { dropped(urls) }
    }

    private func openSettings() {
        NSApp?.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
    }
}
