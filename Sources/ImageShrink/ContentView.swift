import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            WindowBackground().ignoresSafeArea()

            if model.items.isEmpty {
                EmptyState()
            } else {
                PhotoGrid()
            }
        }
        .frame(minWidth: 560, minHeight: 540)
        .safeAreaInset(edge: .top, spacing: 0) { TopBar() }
        .safeAreaInset(edge: .bottom, spacing: 0) { ActionBar() }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            load(providers)
            return true
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }

    private func load(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { model.add(urls: [url]) }
            }
        }
    }
}

// MARK: - The pictures, which are the point of the window

struct PhotoGrid: View {
    @EnvironmentObject var model: AppModel

    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 190), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(model.items) { item in
                    PhotoCard(item: item)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .animation(.snappy(duration: 0.25), value: model.items.count)
        }
        .scrollContentBackground(.hidden)
    }
}

struct PhotoCard: View {
    let item: AppModel.Item
    @EnvironmentObject var model: AppModel
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .topTrailing) {
                preview
                if hovering && !model.isRunning && item.result == nil {
                    removeButton
                }
            }
            caption
        }
        .onHover { hovering = $0 }
        .task(id: item.url) { thumbnail = await Thumbnail.load(item.url, size: 420) }
    }

    private var preview: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .clipShape(shape)
        .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
        .overlay(alignment: .bottomTrailing) { badge }
        .overlay {
            if isWorking {
                ZStack {
                    shape.fill(.black.opacity(0.35))
                    ProgressView().controlSize(.small).tint(.white)
                }
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }

    private var isWorking: Bool { model.isRunning && item.result == nil }

    @ViewBuilder
    private var badge: some View {
        if let status = item.result?.status {
            let icon: (String, Color) = {
                switch status {
                case .converted: return ("checkmark.circle.fill", .green)
                case .skipped: return ("minus.circle.fill", .secondary)
                case .failed: return ("exclamationmark.triangle.fill", .orange)
                }
            }()
            Image(systemName: icon.0)
                .font(.system(size: 17))
                .foregroundStyle(.white, icon.1)
                .padding(7)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var removeButton: some View {
        Button { model.remove(item) } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(.white, .black.opacity(0.5))
        }
        .buttonStyle(.plain)
        .padding(6)
        .help("Remove from the list")
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.result?.output?.lastPathComponent ?? item.url.lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 5) {
                Text(Format.bytes(item.bytes))
                    .foregroundStyle(.secondary)
                if let new = item.result?.newBytes, new != item.bytes {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(Format.bytes(new))
                        .foregroundStyle(new < item.bytes ? Color.green : Color.orange)
                }
            }
            .font(.caption)
            .monospacedDigit()

            switch item.result?.status {
            case .converted:
                if let new = item.result?.newBytes, item.bytes > 0 {
                    SizeBar(fraction: min(1, Double(new) / Double(item.bytes)))
                }
            case .skipped(let reason):
                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            case .failed(let reason):
                Text(reason).font(.caption).foregroundStyle(.orange).lineLimit(1)
            case nil:
                EmptyView()
            }
        }
    }
}

/// How much of the original is left, drawn rather than spelled out.
struct SizeBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(fraction <= 1 ? Color.green : Color.orange)
                    .frame(width: max(3, geometry.size.width * fraction))
            }
        }
        .frame(height: 3)
    }
}

struct EmptyState: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.stack")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Drop images here")
                .font(.title3.weight(.medium))
            Text("HEIC, JPEG or PNG — they come out as JPEG under the limit you pick")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 380)
        .padding(40)
    }
}

// MARK: - Bars

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 12) {
            if model.isFinished {
                summary
            } else {
                Picker("", selection: presetBinding) {
                    Text("500 KB").tag(0.5)
                    Text("1 MB").tag(1.0)
                    Text("2 MB").tag(2.0)
                    Text("5 MB").tag(5.0)
                    Text(isPreset ? "Custom"
                         : model.targetMB.formatted(.number.precision(.fractionLength(0...2))) + " MB")
                        .tag(-1.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(model.isRunning)

                Text(settingsLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("All settings")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsPopover().environmentObject(model)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.savedBytes > 0 ? "Saved \(Format.bytes(model.savedBytes))" : "Done")
                    .font(.headline)
                Text("\(Format.bytes(model.convertedBytes)) → \(Format.bytes(model.producedBytes))"
                     + (percent > 0 ? " · \(percent)% smaller" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if failures > 0 {
                Label("\(failures) failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var percent: Int {
        guard model.convertedBytes > 0 else { return 0 }
        return Int((Double(model.savedBytes) / Double(model.convertedBytes) * 100).rounded())
    }

    private var failures: Int { model.results.filter(\.isFailure).count }

    private var settingsLine: String {
        var parts: [String] = []
        if model.maxDimension > 0 { parts.append("\(model.maxDimension) px") }
        switch model.destinationMode {
        case .sameFolder: break
        case .subfolder: parts.append("Converted/")
        case .custom: parts.append(model.customDestination?.lastPathComponent ?? "chosen folder")
        }
        if model.replaceOriginals { parts.append("originals to Trash") }
        if model.stripMetadata { parts.append("no metadata") }
        return parts.joined(separator: " · ")
    }

    private var isPreset: Bool {
        [0.5, 1.0, 2.0, 5.0].contains { abs($0 - model.targetMB) < 0.001 }
    }

    /// −1 means the number in the field is not one of the presets.
    private var presetBinding: Binding<Double> {
        Binding {
            [0.5, 1.0, 2.0, 5.0].first { abs($0 - model.targetMB) < 0.001 } ?? -1
        } set: { value in
            if value > 0 { model.targetMB = value }
        }
    }
}

struct ActionBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            GlassGroup(spacing: 14) {
                HStack(spacing: 10) {
                    Button("Add Files\u{2026}") { openPanel() }
                        .glassButton()
                    if !model.items.isEmpty && !model.isRunning {
                        Button(model.isFinished ? "Clear" : "Remove All") { model.clear() }
                            .glassButton()
                    }

                    Spacer(minLength: 12)

                    if model.isRunning {
                        ProgressView(value: Double(model.done), total: Double(max(1, model.items.count)))
                            .progressViewStyle(.linear)
                            .frame(width: 110)
                        Text("\(model.done)/\(model.items.count)")
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    if model.isFinished {
                        Button("Show in Finder") { reveal() }
                            .glassButton(prominent: true)
                            .keyboardShortcut(.defaultAction)
                            .disabled(model.results.allSatisfy { $0.output == nil })
                    } else {
                        Button(convertTitle) { model.convert() }
                            .glassButton(prominent: true)
                            .keyboardShortcut(.defaultAction)
                            .disabled(model.pending.isEmpty || model.isRunning)
                    }
                }
            }
            ShortcutHint()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var convertTitle: String {
        let count = model.pending.count
        return count > 1 ? "Convert \(count) Images" : "Convert"
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { model.add(urls: panel.urls) }
    }

    private func reveal() {
        let urls = model.results.compactMap(\.output)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

/// The instant Quick Action has no interface of its own, so this is where anyone
/// finds out it exists.
struct ShortcutHint: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "keyboard")
            Text("In Finder: \u{2303}\u{2318}J converts the selection with these settings, "
                 + "without opening this window")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings, one click away rather than filling the window

struct SettingsPopover: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Maximum file size") {
                LabeledContent("Limit") {
                    HStack(spacing: 6) {
                        TextField("", value: $model.targetMB,
                                  format: .number.precision(.fractionLength(0...2)))
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                        Text("MB").foregroundStyle(.secondary)
                        Stepper("", value: $model.targetMB, in: 0.1...50, step: 0.5).labelsHidden()
                    }
                }
            }

            Section("Longest side") {
                Picker("", selection: $model.maxDimension) {
                    Text("Original").tag(0)
                    Text("4096").tag(4096)
                    Text("2560").tag(2560)
                    Text("1920").tag(1920)
                    Text("1280").tag(1280)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Save to") {
                Picker("", selection: $model.destinationMode) {
                    Text("Same folder").tag(DestinationMode.sameFolder)
                    Text("\u{201C}Converted\u{201D}").tag(DestinationMode.subfolder)
                    Text("Chosen folder").tag(DestinationMode.custom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: model.destinationMode) { mode in
                    if mode == .custom && model.customDestination == nil { chooseFolder() }
                }

                if model.destinationMode == .custom {
                    LabeledContent("Folder") {
                        HStack(spacing: 8) {
                            Text(model.customDestination?.path ?? "Not chosen")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Button("Change\u{2026}") { chooseFolder() }.buttonStyle(.link)
                        }
                    }
                }
            }

            Section {
                Toggle("Skip files already under the limit", isOn: $model.skipSmallEnough)
                Toggle("Keep original date created and modified", isOn: $model.keepDates)
                Toggle("Remove metadata (EXIF, GPS)", isOn: $model.stripMetadata)
                Toggle("Move originals to Trash after converting", isOn: $model.replaceOriginals)
                LabeledContent("Suffix (empty: the file\u{2019}s own size)") {
                    TextField("automatic", text: $model.suffix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 430)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK { model.customDestination = panel.url }
    }
}
