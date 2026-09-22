import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            WindowBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar()
                    .padding(.horizontal, Theme.wide)
                    .padding(.top, Theme.snug)
                    .padding(.bottom, Theme.normal)

                Group {
                    if model.items.isEmpty {
                        EmptyState()
                    } else {
                        FileList()
                    }
                }
                .padding(.horizontal, Theme.wide)

                // No disabled primary button: with an empty queue there is no footer at all.
                if !model.items.isEmpty {
                    Footer()
                        .padding(.horizontal, Theme.wide)
                        .padding(.vertical, Theme.normal)
                }
            }
            .padding(.bottom, model.items.isEmpty ? Theme.wide : 0)
        }
        .frame(minWidth: 680, minHeight: 520)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            load(providers)
            return true
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: Theme.windowRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isTargeted)
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

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: Theme.normal) {
            LimitPicker()

            if model.isCustomLimit && !model.isRunning {
                LimitField()
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .leading)))
            }

            Spacer(minLength: Theme.normal)

            if model.isRunning {
                Text("Settings are locked while converting")
                    .font(Theme.control)
                    .foregroundStyle(Theme.caption(contrast))
            } else {
                Label(model.destinationSummary, systemImage: "folder")
                    .font(Theme.control)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }
        }
        .disabled(model.isRunning)
        .opacity(model.isRunning ? 0.5 : 1)
        .animation(reduceMotion ? nil : Theme.limitChange, value: model.isCustomLimit)
        .animation(reduceMotion ? nil : Theme.limitChange, value: model.isRunning)
    }
}

/// The one accent on the screen, alongside the primary button.
///
/// The selected capsule is a single view that slides between the pills, positioned from the
/// frames they report. `matchedGeometryEffect` was tried first and does not animate here —
/// frame captures showed it already at its destination 50 ms in, whether the animation was a
/// modifier or an explicit transaction.
struct LimitPicker: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frames: [Double: CGRect] = [:]

    private static let space = "limit-pills"
    private let choices: [(label: String, value: Double)] = [
        ("500 KB", 0.5), ("1 MB", 1), ("2 MB", 2), ("5 MB", 5),
    ]

    private var selectedValue: Double {
        model.isCustomLimit ? -1 : model.targetMB
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(choices, id: \.value) { choice in
                button(choice.label, value: choice.value, selected: model.isPreset(choice.value))
            }
            button("Custom", value: -1, selected: model.isCustomLimit)
        }
        .padding(3)
        .coordinateSpace(name: Self.space)
        .background(alignment: .topLeading) {
            if let frame = frames[selectedValue] {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .animation(reduceMotion ? nil : Theme.limitChange, value: frame)
            }
        }
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .fixedSize()
        .onPreferenceChange(PillFrames.self) { frames = $0 }
    }

    private func apply(_ value: Double) {
        withAnimation(reduceMotion ? nil : Theme.limitChange) {
            model.targetMB = value < 0 ? 2.5 : value
        }
    }

    private func button(_ label: String, value: Double, selected: Bool) -> some View {
        Button { if !selected { apply(value) } } label: {
            Text(label)
                .font(Theme.control)
                .tabularNumbers()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, Theme.normal)
                .padding(.vertical, Theme.tight)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: PillFrames.self,
                                               value: [value: proxy.frame(in: .named(Self.space))])
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Limit \(label)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Where each pill sits, so one capsule can travel between them.
private struct PillFrames: PreferenceKey {
    static var defaultValue: [Double: CGRect] = [:]
    static func reduce(value: inout [Double: CGRect], nextValue: () -> [Double: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct LimitField: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: Theme.tight) {
            Text("Limit").font(Theme.control).foregroundStyle(.secondary)
            TextField("Limit", value: $model.targetMB,
                      format: .number.precision(.fractionLength(0...2)))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .tabularNumbers()
            Text("MB").font(Theme.control).foregroundStyle(.secondary)
            Stepper("Limit", value: $model.targetMB, in: 0.1...50, step: 0.5).labelsHidden()
        }
        .padding(.horizontal, Theme.snug)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .fixedSize()
    }
}

// MARK: - The list

struct FileList: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        FileRow(item: item, alternate: index.isMultiple(of: 2) == false)
                        if item.id != model.items.last?.id {
                            Divider().opacity(0.35).padding(.leading, 64)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .contentPanel()
    }

    private var header: some View {
        HStack {
            if model.isFinished {
                Label("\(model.done) images converted", systemImage: "checkmark")
                    .font(Theme.control)
                    .foregroundStyle(Theme.saved)
            } else {
                Text("^[\(model.items.count) image](inflect: true)")
                    .font(Theme.control)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(hint)
                .font(Theme.meta)
                .foregroundStyle(Theme.caption(contrast))
        }
        .padding(.horizontal, Theme.wide)
        .padding(.vertical, Theme.snug)
        .background(model.isFinished ? Theme.saved.opacity(0.10) : Color.clear)
    }

    private var hint: String {
        if model.isRunning { return "Originals stay untouched until every file is written" }
        if model.isFinished {
            return model.replaceOriginals
                ? "Originals moved to Trash"
                : "Originals kept \u{00B7} nothing was moved to Trash"
        }
        return model.isEstimating ? "Estimating\u{2026}" : "Estimates update as you change the limit"
    }
}

struct FileRow: View {
    let item: AppModel.Item
    let alternate: Bool
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.normal) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(Theme.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .crossfadeText()
            }
            Spacer(minLength: Theme.normal)
            trailing
        }
        .padding(.horizontal, Theme.wide)
        .padding(.vertical, Theme.snug)
        .background(rowBackground)
        .overlay(alignment: .bottom) {
            if isWorking {
                ProgressView(value: passFraction)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
                    .tint(Color.accentColor)
            }
        }
        .onHover { hovering = $0 }
        .task(id: item.url) { thumbnail = await Thumbnail.load(item.url, size: 120) }
        .animation(reduceMotion ? nil : Theme.numbers, value: item.estimate?.bytes)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: item.isDone)
    }

    private var icon: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
        return Group {
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFill()
            } else {
                shape.fill(Color.primary.opacity(0.07))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5) }
    }

    private var isWorking: Bool { item.stage != nil }

    private var passFraction: Double {
        guard case .searching(let pass, let total)? = item.stage else { return 0.15 }
        return Double(pass) / Double(total)
    }

    private var title: String {
        item.result?.output?.lastPathComponent ?? item.url.lastPathComponent
    }

    private var subtitle: String {
        if let stage = item.stage {
            switch stage {
            case .reading: return "Reading"
            case .searching(let pass, let total):
                return "Searching for the largest quality that fits "
                     + "\(Format.bytes(model.targetBytes)) \u{2014} pass \(pass) of \(total)"
            case .resizing: return "Too big at every quality \u{2014} reducing the pixels"
            case .writing: return "Writing"
            }
        }
        if model.isRunning && !item.isDone { return "Waiting" }

        if let result = item.result {
            switch result.status {
            case .converted:
                var parts = ["from \(item.url.lastPathComponent)"]
                if let saved = result.newBytes.map({ item.bytes - $0 }), saved > 0 {
                    parts.append("saved \(Format.bytes(saved))")
                }
                if let quality = result.quality { parts.append("quality \(Int(quality * 100)) %") }
                return parts.joined(separator: " \u{00B7} ")
            case .skipped(let reason): return reason
            case .failed(let reason): return reason
            }
        }

        var parts: [String] = []
        if let pixels = item.pixels { parts.append(Format.pixels(pixels)) }
        parts.append(item.format)
        switch item.estimate?.outcome {
        case .untouched: parts.append("already under the limit")
        case .reencoded(let quality): parts.append("quality \(Int(quality * 100)) %")
        case .resized: parts.append("resized to fit")
        case nil: parts.append(model.isEstimating ? "estimating\u{2026}" : "")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    @ViewBuilder
    private var trailing: some View {
        if let result = item.result {
            HStack(spacing: Theme.snug) {
                if hovering, result.output != nil {
                    Button("Show") { reveal(result.output) }
                        .buttonStyle(SecondaryButton(compact: true))
                }
                Text(Format.bytes(result.newBytes ?? item.bytes))
                    .font(Theme.rowTitle)
                    .tabularNumbers()
                Image(systemName: statusIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(.white, statusTint)
            }
        } else {
            HStack(spacing: Theme.snug) {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: Theme.tight) {
                        Text(Format.bytes(item.bytes))
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(estimateLabel)
                            .fontWeight(.semibold)
                            .foregroundStyle(estimateTint)
                            .numericTransition()
                    }
                    .font(Theme.meta)
                    .tabularNumbers()

                    SizeBar(fraction: fraction, shrinks: shrinks, grows: grows)
                        .frame(width: 118)
                }
                if hovering && !model.isRunning {
                    Button {
                        model.remove(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.url.lastPathComponent)")
                }
            }
        }
    }

    private var estimateLabel: String {
        guard let estimate = item.estimate else { return "\u{2026}" }
        switch estimate.outcome {
        case .untouched: return Format.bytes(estimate.bytes)
        default: return "~\(Format.bytes(estimate.bytes))"
        }
    }

    private var grows: Bool {
        guard let estimate = item.estimate else { return false }
        return estimate.bytes > item.bytes
    }

    private var estimateTint: Color {
        if shrinks { return Theme.saved }
        return grows ? Theme.attention : .primary
    }

    private var shrinks: Bool {
        guard let estimate = item.estimate else { return false }
        return estimate.bytes < item.bytes
    }

    private var fraction: Double {
        guard item.bytes > 0, let estimate = item.estimate else { return 0 }
        return min(1, Double(estimate.bytes) / Double(item.bytes))
    }

    private var statusIcon: String {
        switch item.result?.status {
        case .converted: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        case nil: return "circle"
        }
    }

    private var statusTint: Color {
        switch item.result?.status {
        case .converted: return Theme.saved
        case .skipped: return .secondary
        case .failed: return Theme.attention
        case nil: return .secondary
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isWorking {
            Color.accentColor.opacity(0.12)
        } else if alternate {
            Color.primary.opacity(0.025)
        } else {
            Color.clear
        }
    }

    private func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct SizeBar: View {
    let fraction: Double
    var shrinks: Bool = true
    var grows: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(shrinks ? Theme.saved : (grows ? Theme.attention : Color.secondary))
                    .frame(width: max(2, geometry.size.width * min(1, fraction)))
                    .animation(reduceMotion ? nil : Theme.numbers, value: fraction)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

// MARK: - Empty state

struct EmptyState: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.wide) {
            Spacer()
            VStack(spacing: Theme.normal) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 96, height: 96)
                    .overlay {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                Text("Drop images here").font(Theme.display)
                Text("HEIC, JPEG and PNG come out as JPEG under \(Format.bytes(model.targetBytes)), "
                     + (model.maxDimension > 0
                        ? "at most \(model.maxDimension) px on the longest side."
                        : "at their original dimensions."))
                    .font(Theme.control)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .crossfadeText()
                    .animation(reduceMotion ? nil : Theme.numbers, value: model.targetBytes)
                Button("Choose Files\u{2026}") { openPanel(model) }
                    .buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
            ShortcutBanner()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The window is the exception, not the product — say so where it is unmissable.
struct ShortcutBanner: View {
    var body: some View {
        HStack(spacing: Theme.normal) {
            RoundedRectangle(cornerRadius: Theme.fieldRadius, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .frame(width: 34, height: 34)
                .overlay { Image(systemName: "keyboard").foregroundStyle(.secondary) }

            VStack(alignment: .leading, spacing: 3) {
                Text("You don\u{2019}t need this window").font(Theme.rowTitle)
                Text("Convert what is selected in Finder with these settings, no window.")
                    .font(Theme.meta)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.normal)
            ShortcutField()
        }
        .padding(Theme.normal)
        .contentPanel()
    }
}

struct KeyCap: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .frame(minWidth: 18)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.10)))
    }
}

// MARK: - Footer

struct Footer: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.normal) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(Theme.rowTitle).tabularNumbers().numericTransition()
                Text(detail).font(Theme.meta).foregroundStyle(.secondary).tabularNumbers()
                    .crossfadeText()
            }
            .animation(reduceMotion ? nil : Theme.numbers, value: model.estimatedTotal)
            Spacer(minLength: Theme.wide)

            if model.isRunning {
                Button("Stop") { model.cancel() }
                    .buttonStyle(SecondaryButton())
                    .keyboardShortcut(.cancelAction)
                ProgressBadge(fraction: Double(model.done) / Double(max(1, model.items.count)))
            } else if model.isFinished {
                if model.canUndo {
                    Button("Undo") { model.undo() }
                        .buttonStyle(SecondaryButton())
                }
                Button("Show in Finder") { revealAll() }
                    .buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Clear") { model.clear() }
                    .buttonStyle(SecondaryButton())
                Button(model.pending.count > 1 ? "Convert \(model.pending.count) Images" : "Convert") {
                    model.convert()
                }
                .buttonStyle(PrimaryButton())
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var headline: String {
        if model.isRunning { return "Converting \(model.done + 1) of \(model.items.count)" }
        if model.isFinished {
            return "\(Format.bytes(model.convertedBytes)) \u{2192} \(Format.bytes(model.producedBytes))"
        }
        return "\(Format.bytes(model.totalBytes)) \u{2192} about \(Format.bytes(model.estimatedTotal))"
    }

    private var detail: String {
        if model.isRunning {
            guard let seconds = model.remainingSeconds else { return "Working\u{2026}" }
            return "About \(seconds) second\(seconds == 1 ? "" : "s") left"
        }
        if model.isFinished {
            let failed = model.results.filter(\.isFailure).count
            if failed > 0 { return "\(failed) could not reach the limit" }
            return "\(Format.bytes(model.savedBytes)) saved \u{00B7} every file fits "
                 + Format.bytes(model.targetBytes)
        }
        return model.plan
    }

    private func revealAll() {
        let urls = model.results.compactMap(\.output)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

struct ProgressBadge: View {
    let fraction: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.10))
            Capsule().fill(Color.accentColor).frame(width: max(20, 160 * fraction))
            Text("\(Int(fraction * 100)) %")
                .font(Theme.control)
                .tabularNumbers()
                .foregroundStyle(.white)
                .padding(.leading, Theme.normal)
        }
        .frame(width: 160, height: 28)
    }
}

// MARK: - Buttons

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.action)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.wide)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.accentColor))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButton: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? Theme.meta : Theme.action)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.primary)
            .padding(.horizontal, compact ? Theme.snug : Theme.wide)
            .padding(.vertical, compact ? 3 : 7)
            .background(Capsule().fill(Color.primary.opacity(0.10)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

@MainActor
func openPanel(_ model: AppModel) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.image]
    if panel.runModal() == .OK { model.add(urls: panel.urls) }
}
