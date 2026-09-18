import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            WindowBackground().ignoresSafeArea()

            if model.results.isEmpty {
                SetupView()
            } else {
                ResultsView()
            }
        }
        .frame(minWidth: 540, minHeight: 600)
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
                    .transition(.opacity)
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

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                if model.files.isEmpty {
                    DropZone()
                } else {
                    ForEach(model.files.prefix(7), id: \.self) { url in
                        FileRow(url: url)
                    }
                    if model.files.count > 7 {
                        Text("and \(model.files.count - 7) more")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack {
                    Text(model.files.isEmpty ? "Images" : "^[\(model.files.count) image](inflect: true)")
                    Spacer()
                    if !model.files.isEmpty {
                        Text("\(Format.bytes(model.totalBytes)) → JPEG")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Maximum file size") {
                Picker("", selection: presetBinding) {
                    Text("500 KB").tag(0.5)
                    Text("1 MB").tag(1.0)
                    Text("2 MB").tag(2.0)
                    Text("5 MB").tag(5.0)
                    Text("Custom").tag(-1.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

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
                    Text("\u{201C}Converted\u{201D} subfolder").tag(DestinationMode.subfolder)
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
                DisclosureGroup("More options") {
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
        }
        .formStyle(.grouped)
        .clearScrollBackground()
        .safeAreaInset(edge: .bottom) { ActionBar() }
    }

    /// −1 means the number in the field is not one of the presets.
    private var presetBinding: Binding<Double> {
        Binding {
            [0.5, 1.0, 2.0, 5.0].first { abs($0 - model.targetMB) < 0.001 } ?? -1
        } set: { value in
            if value > 0 { model.targetMB = value }
        }
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

struct DropZone: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
            .foregroundStyle(.tertiary)
            .frame(height: 96)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Drop HEIC, JPEG or PNG files here")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
    }
}

struct FileRow: View {
    let url: URL
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            preview
            Text(url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(Format.bytes(Converter.byteSize(of: url)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .task(id: url) { thumbnail = await Thumbnail.load(url) }
    }

    @ViewBuilder
    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { Image(systemName: "photo").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(width: 34, height: 26)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
    }
}

// MARK: - Action bars

struct ActionBar: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            GlassGroup(spacing: 14) {
            HStack(spacing: 10) {
                Button("Add Files\u{2026}") { openPanel() }
                    .glassButton()
                if !model.files.isEmpty && !model.isRunning {
                    Button("Clear") { model.clear() }
                        .glassButton()
                }

                Spacer(minLength: 12)

                if model.isRunning {
                    ProgressView(value: Double(model.done), total: Double(max(1, model.files.count)))
                        .progressViewStyle(.linear)
                        .frame(width: 110)
                    Text("\(model.done)/\(model.files.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button(model.files.count > 1 ? "Convert \(model.files.count) Images" : "Convert") {
                    model.convert()
                }
                .glassButton(prominent: true)
                .keyboardShortcut(.defaultAction)
                .disabled(model.files.isEmpty || model.isRunning)
            }
            }
            ShortcutHint()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { model.add(urls: panel.urls) }
    }
}

// MARK: - Results

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

struct ResultsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(model.results) { result in
                    ResultRow(result: result)
                }
            } header: {
                HStack {
                    Text("Done")
                    Spacer()
                    if model.savedBytes > 0 {
                        Text("saved \(Format.bytes(model.savedBytes))")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .clearScrollBackground()
        .safeAreaInset(edge: .bottom) {
            GlassGroup(spacing: 14) {
                HStack(spacing: 10) {
                    Button("Show in Finder") { reveal() }
                        .glassButton()
                        .disabled(model.results.allSatisfy { $0.output == nil })
                    Spacer(minLength: 12)
                    Button("Done") { model.clear() }
                        .glassButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func reveal() {
        let urls = model.results.compactMap(\.output)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

struct ResultRow: View {
    let result: FileResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.output?.lastPathComponent ?? result.source.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        switch result.status {
        case .converted: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch result.status {
        case .converted: return .green
        case .skipped: return .secondary
        case .failed: return .orange
        }
    }

    private var detail: String {
        switch result.status {
        case .converted:
            var parts = ["\(Format.bytes(result.originalBytes)) → \(Format.bytes(result.newBytes ?? 0))"]
            if let pixels = result.pixelSize { parts.append(Format.pixels(pixels)) }
            if let quality = result.quality { parts.append("quality \(Int(quality * 100))") }
            return parts.joined(separator: " · ")
        case .skipped(let reason):
            return "\(Format.bytes(result.originalBytes)) · \(reason)"
        case .failed(let reason):
            return reason
        }
    }
}
