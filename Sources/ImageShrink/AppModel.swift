import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {

    /// One row. It carries its own estimate, its own live stage and its own result, so the
    /// list can show each file's state the moment it changes.
    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        let bytes: Int
        var curve: SizeCurve?
        var estimate: Estimate?
        var stage: Converter.Stage?
        var result: FileResult?

        var pixels: CGSize? { result?.pixelSize ?? curve?.pixels }
        var isDone: Bool { result != nil }
        var format: String { url.pathExtension.uppercased() }
    }

    @Published var items: [Item] = []
    @Published var isRunning = false
    @Published var isEstimating = false

    // Conversion settings — changing one re-estimates every row in place.
    @Published var targetMB: Double = Defaults.double("targetMB", 2) { didSet { reestimate() } }
    @Published var maxDimension: Int = Defaults.int("maxDimension", 0) { didSet { estimateAll(force: true) } }
    @Published var destinationMode = Defaults.destinationMode()
    @Published var customDestination: URL? = Defaults.existingURL("customDestination")
    @Published var replaceOriginals = Defaults.bool("replaceOriginals", false)
    @Published var suffix = Defaults.suffix()
    @Published var stripMetadata = Defaults.bool("stripMetadata", false) { didSet { reestimate() } }
    @Published var keepDates = Defaults.bool("keepDates", true)
    @Published var skipSmallEnough = Defaults.bool("skipSmallEnough", true) { didSet { reestimate() } }

    private var cancellation: Cancellation?
    private var runStarted: Date?
    private var runTotal = 0

    // MARK: - Derived

    static let presetLimits: [Double] = [0.5, 1, 2, 5]

    var targetBytes: Int { Int(targetMB * 1_000_000) }
    func isPreset(_ value: Double) -> Bool { abs(targetMB - value) < 0.001 }
    var isCustomLimit: Bool { !Self.presetLimits.contains(where: isPreset) }
    var totalBytes: Int { items.reduce(0) { $0 + $1.bytes } }
    var pending: [Item] { items.filter { !$0.isDone } }
    var results: [FileResult] { items.compactMap(\.result) }
    var done: Int { results.count }
    var isFinished: Bool { !items.isEmpty && pending.isEmpty }

    /// What the whole queue is expected to weigh once converted.
    var estimatedTotal: Int {
        items.reduce(0) { $0 + ($1.estimate?.bytes ?? $1.bytes) }
    }

    var producedBytes: Int { results.reduce(0) { $0 + ($1.newBytes ?? $1.originalBytes) } }
    var convertedBytes: Int { results.reduce(0) { $0 + $1.originalBytes } }
    var savedBytes: Int {
        results.reduce(0) { total, result in
            guard let new = result.newBytes else { return total }
            return total + max(0, result.originalBytes - new)
        }
    }

    /// "2 files are resized, 2 are only converted to JPEG"
    var plan: String {
        let shrinking = items.filter { item in
            guard let estimate = item.estimate else { return false }
            return estimate.bytes < item.bytes
        }.count
        let untouched = items.count - shrinking
        var parts: [String] = []
        if shrinking > 0 { parts.append("\(shrinking) \(shrinking == 1 ? "file is" : "files are") resized") }
        if untouched > 0 { parts.append("\(untouched) \(parts.isEmpty ? "are" : "are") only converted to JPEG") }
        return parts.joined(separator: ", ")
    }

    var destinationSummary: String {
        switch destinationMode {
        case .sameFolder: return "Saved next to the originals"
        case .subfolder: return "Saved in a \u{201C}Converted\u{201D} subfolder"
        case .custom: return "Saved in \(customDestination?.lastPathComponent ?? "a chosen folder")"
        }
    }

    var remainingSeconds: Int? {
        guard isRunning, let started = runStarted, done > 0, runTotal > done else { return nil }
        let perFile = Date().timeIntervalSince(started) / Double(done)
        return max(1, Int((perFile * Double(runTotal - done)).rounded()))
    }

    /// Replacing a JPEG in place leaves nothing to put back.
    var canUndo: Bool {
        isFinished && !results.isEmpty && results.allSatisfy { result in
            result.output?.standardizedFileURL != result.source.standardizedFileURL
        }
    }

    // MARK: - Queue

    func add(urls: [URL]) {
        let images = urls.filter(Self.isImage)
        Log.write("queued \(images.count) of \(urls.count) file(s): "
                  + images.map(\.lastPathComponent).joined(separator: ", "))
        guard !images.isEmpty else { return }
        let known = Set(items.map(\.url.standardizedFileURL))
        items += images
            .filter { !known.contains($0.standardizedFileURL) }
            .map { Item(url: $0, bytes: Converter.byteSize(of: $0)) }
        estimateAll()
    }

    func remove(_ item: Item) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items = []
    }

    func settings() -> ConversionSettings {
        ConversionSettings(
            targetBytes: targetBytes,
            maxDimension: maxDimension > 0 ? maxDimension : nil,
            destinationMode: destinationMode,
            customDestination: customDestination,
            replaceOriginals: replaceOriginals,
            suffix: suffix.trimmingCharacters(in: .whitespaces),
            stripMetadata: stripMetadata,
            keepDates: keepDates,
            skipSmallEnough: skipSmallEnough)
    }

    // MARK: - Estimates

    /// Measures each file's size-versus-quality curve. Only needed once per resolution.
    func estimateAll(force: Bool = false) {
        let cap = maxDimension > 0 ? maxDimension : nil
        let stale = items.filter { force || $0.curve == nil || $0.curve?.maxDimension != cap }
        guard !stale.isEmpty else { return reestimate() }

        isEstimating = true
        let ids = stale.map(\.id)
        let urls = stale.map(\.url)

        Task.detached(priority: .utility) { [self] in
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                let curve = Estimator.curve(for: urls[index], maxDimension: cap)
                Task { @MainActor in self.apply(curve, to: ids[index]) }
            }
            await MainActor.run {
                self.isEstimating = false
                self.reestimate()
            }
        }
    }

    /// Instant: the curves are already measured, this is interpolation.
    func reestimate() {
        let settings = settings()
        for index in items.indices {
            guard let curve = items[index].curve else { continue }
            items[index].estimate = Estimator.estimate(curve, settings: settings)
        }
    }

    private func apply(_ curve: SizeCurve?, to id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }), let curve else { return }
        items[index].curve = curve
        items[index].estimate = Estimator.estimate(curve, settings: settings())
    }

    // MARK: - Converting

    func convert() {
        let queue = pending
        guard !queue.isEmpty, !isRunning else { return }
        save()
        let settings = settings()
        let urls = queue.map(\.url)
        let ids = queue.map(\.id)
        Log.write("converting \(urls.count) file(s) → \(settings.targetBytes / 1000) KB limit")

        isRunning = true
        runTotal = urls.count
        runStarted = Date()
        let cancellation = Cancellation()
        self.cancellation = cancellation
        DockProgress.show(0)

        Task.detached(priority: .userInitiated) { [self] in
            let reserver = NameReserver(sources: urls)
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                guard !cancellation.isCancelled else { return }
                let id = ids[index]
                let result = Converter.convert(url: urls[index], settings: settings,
                                               reserver: reserver) { stage in
                    Task { @MainActor in self.stage(stage, for: id) }
                }
                if case .failed(let reason) = result.status {
                    Log.write("failed \(urls[index].lastPathComponent): \(reason)")
                }
                Task { @MainActor in self.apply(result, to: id) }
            }
            let stopped = cancellation.isCancelled
            Log.write(stopped ? "cancelled" : "finished \(urls.count) file(s)")
            await MainActor.run { self.finish(cancelled: stopped) }
        }
    }

    /// Stops after the images already in flight; whatever is left stays pending.
    func cancel() {
        cancellation?.cancel()
    }

    /// Puts the converted files in the Trash and brings any trashed originals back.
    func undo() {
        let manager = FileManager.default
        for item in items {
            guard let result = item.result else { continue }
            if let output = result.output {
                try? manager.trashItem(at: output, resultingItemURL: nil)
            }
            if let trashed = result.trashedOriginal {
                try? manager.moveItem(at: trashed, to: result.source)
            }
        }
        Log.write("undid \(results.count) file(s)")
        for index in items.indices {
            items[index].result = nil
            items[index].stage = nil
        }
        reestimate()
    }

    private func stage(_ stage: Converter.Stage, for id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].stage = stage
    }

    private func apply(_ result: FileResult, to id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].result = result
        items[index].stage = nil
        if runTotal > 0 { DockProgress.show(Double(done) / Double(runTotal)) }
    }

    private func finish(cancelled: Bool) {
        isRunning = false
        cancellation = nil
        runTotal = 0
        runStarted = nil
        for index in items.indices { items[index].stage = nil }
        DockProgress.clear()
        guard !cancelled, NSApp?.isActive == false else { return }
        Notifier.post(title: "Images converted", body: summaryLine)
    }

    var summaryLine: String {
        let count = results.count
        let images = count == 1 ? "1 image" : "\(count) images"
        return savedBytes > 0 ? "\(images) · saved \(Format.bytes(savedBytes))" : images
    }

    // MARK: - Storage

    /// Back to the shipped defaults, without touching the queue.
    func resetSettings() {
        targetMB = 2
        maxDimension = 0
        destinationMode = .sameFolder
        customDestination = nil
        replaceOriginals = false
        suffix = ""
        stripMetadata = false
        keepDates = true
        skipSmallEnough = true
        save()
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(targetMB, forKey: "targetMB")
        defaults.set(maxDimension, forKey: "maxDimension")
        defaults.set(destinationMode.rawValue, forKey: "destinationMode")
        defaults.set(customDestination?.path, forKey: "customDestination")
        defaults.set(replaceOriginals, forKey: "replaceOriginals")
        defaults.set(suffix, forKey: "suffix")
        defaults.set(stripMetadata, forKey: "stripMetadata")
        defaults.set(keepDates, forKey: "keepDates")
        defaults.set(skipSmallEnough, forKey: "skipSmallEnough")
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image)
    }
}

enum Defaults {
    static func double(_ key: String, _ fallback: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? fallback
    }
    static func int(_ key: String, _ fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
    static func bool(_ key: String, _ fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }
    static func string(_ key: String, _ fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }

    /// "-small" was the old fixed default; treat it as "derive it from the limit".
    static func suffix() -> String {
        let stored = string("suffix", "")
        return stored == "-small" ? "" : stored
    }

    static func existingURL(_ key: String) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key),
              FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Falls back to the same folder when the folder that was chosen last time is gone.
    static func destinationMode() -> DestinationMode {
        let mode = DestinationMode(rawValue: string("destinationMode", DestinationMode.sameFolder.rawValue))
        if mode == .custom && existingURL("customDestination") == nil { return .sameFolder }
        return mode ?? .sameFolder
    }
}

enum Format {
    static func bytes(_ value: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = value < 1_000_000 ? [.useKB] : [.useMB]
        return formatter.string(fromByteCount: Int64(value))
    }

    static func pixels(_ size: CGSize?) -> String {
        guard let size, size.width > 0 else { return "" }
        return "\(Int(size.width)) × \(Int(size.height))"
    }
}
