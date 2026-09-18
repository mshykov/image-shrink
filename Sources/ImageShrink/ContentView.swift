import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.results.isEmpty {
                setup
            } else {
                ResultsView()
            }
        }
        .frame(minWidth: 520, minHeight: 520)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            load(providers)
            return true
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Image Shrink").font(.title2.weight(.semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var subtitle: String {
        if model.files.isEmpty { return "Drop images here, or add them below" }
        let count = model.files.count
        return "\(count) image\(count == 1 ? "" : "s") · \(Format.bytes(model.totalBytes)) → JPEG"
    }

    // MARK: - Setup

    private var setup: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fileList
                    targetSection
                    resolutionSection
                    destinationSection
                    optionsSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.files.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(.tertiary)
                    .frame(height: 80)
                    .overlay {
                        Text("Drag HEIC, JPEG or PNG files here")
                            .foregroundStyle(.secondary)
                    }
            } else {
                ForEach(model.files.prefix(6), id: \.self) { url in
                    HStack(spacing: 8) {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Format.bytes(Converter.byteSize(of: url)))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                }
                if model.files.count > 6 {
                    Text("and \(model.files.count - 6) more")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var targetSection: some View {
        section("Maximum file size", icon: "scalemass") {
            HStack(spacing: 10) {
                TextField("", value: $model.targetMB, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("MB")
                Stepper("", value: $model.targetMB, in: 0.1...50, step: 0.5).labelsHidden()
                Spacer()
                ForEach([0.5, 1.0, 2.0, 5.0], id: \.self) { preset in
                    Button(preset < 1 ? "500 KB" : "\(Int(preset)) MB") { model.targetMB = preset }
                        .buttonStyle(.bordered)
                        .tint(abs(model.targetMB - preset) < 0.001 ? .accentColor : nil)
                }
            }
        }
    }

    private var resolutionSection: some View {
        section("Longest side", icon: "aspectratio") {
            Picker("", selection: $model.maxDimension) {
                Text("Original").tag(0)
                Text("4096 px").tag(4096)
                Text("2560 px").tag(2560)
                Text("1920 px").tag(1920)
                Text("1280 px").tag(1280)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var destinationSection: some View {
        section("Save to", icon: "folder") {
            VStack(alignment: .leading, spacing: 8) {
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
                    HStack(spacing: 8) {
                        Text(model.customDestination?.path ?? "No folder chosen")
                            .font(.callout).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.head)
                        Button("Change\u{2026}") { chooseFolder() }.buttonStyle(.link)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, icon: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var optionsSection: some View {
        DisclosureGroup("More options") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Move originals to Trash after converting", isOn: $model.replaceOriginals)
                HStack {
                    Text("Suffix when the name is taken")
                    TextField("", text: $model.suffix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                Toggle("Skip files already under the limit", isOn: $model.skipSmallEnough)
                Toggle("Keep original date created / modified", isOn: $model.keepDates)
                Toggle("Remove metadata (EXIF, GPS)", isOn: $model.stripMetadata)
            }
            .padding(.top, 6)
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Button("Add Files…") { openPanel() }
            if !model.files.isEmpty {
                Button("Clear") { model.clear() }
            }
            Spacer()
            if model.isRunning {
                ProgressView(value: Double(model.done), total: Double(max(1, model.files.count)))
                    .frame(width: 120)
                Text("\(model.done) / \(model.files.count)")
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            Button(model.files.count > 1 ? "Convert \(model.files.count) Images" : "Convert") {
                model.convert()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.files.isEmpty || model.isRunning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Actions

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { model.add(urls: panel.urls) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK { model.customDestination = panel.url }
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

struct ResultsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.results) { result in
                        row(result)
                    }
                }
                .padding(20)
            }
            Divider()
            HStack {
                Text(summary).font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") { reveal() }
                    .disabled(model.results.allSatisfy { $0.output == nil })
                Button("Done") { model.clear() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func row(_ result: FileResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(result))
                .foregroundStyle(tint(result))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.output?.lastPathComponent ?? result.source.lastPathComponent)
                    .lineLimit(1).truncationMode(.middle)
                Text(detail(result))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func icon(_ result: FileResult) -> String {
        switch result.status {
        case .converted: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func tint(_ result: FileResult) -> Color {
        switch result.status {
        case .converted: return .green
        case .skipped: return .secondary
        case .failed: return .orange
        }
    }

    private func detail(_ result: FileResult) -> String {
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

    private var summary: String {
        let converted = model.results.filter { if case .converted = $0.status { return true }; return false }.count
        let failed = model.results.filter(\.isFailure).count
        var text = "\(converted) converted"
        if failed > 0 { text += ", \(failed) failed" }
        if model.savedBytes > 0 { text += " · saved \(Format.bytes(model.savedBytes))" }
        return text
    }

    private func reveal() {
        let urls = model.results.compactMap(\.output)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
