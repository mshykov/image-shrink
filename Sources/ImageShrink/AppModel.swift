import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {

    /// One row per picture, carrying its own result — the grid renders straight from this,
    /// and each card updates the moment its own file is finished rather than at the end.
    struct Item: Identifiable, Sendable {
        let id = UUID()
        let url: URL
        let bytes: Int
        var result: FileResult?
    }

    @Published var items: [Item] = []
    @Published var isRunning = false

    // Settings — restored from the previous run so the sheet opens pre-filled.
    @Published var targetMB: Double = Defaults.double("targetMB", 2)
    @Published var maxDimension: Int = Defaults.int("maxDimension", 0)
    @Published var destinationMode = Defaults.destinationMode()
    @Published var customDestination: URL? = Defaults.existingURL("customDestination")
    @Published var replaceOriginals = Defaults.bool("replaceOriginals", false)
    @Published var suffix = Defaults.suffix()
    @Published var stripMetadata = Defaults.bool("stripMetadata", false)
    @Published var keepDates = Defaults.bool("keepDates", true)
    @Published var skipSmallEnough = Defaults.bool("skipSmallEnough", true)

    var targetBytes: Int { Int(targetMB * 1_000_000) }
    var totalBytes: Int { items.reduce(0) { $0 + $1.bytes } }
    var pending: [Item] { items.filter { $0.result == nil } }
    var results: [FileResult] { items.compactMap(\.result) }
    var done: Int { results.count }
    var isFinished: Bool { !items.isEmpty && pending.isEmpty }

    var savedBytes: Int {
        results.reduce(0) { total, result in
            guard let new = result.newBytes else { return total }
            return total + max(0, result.originalBytes - new)
        }
    }

    var producedBytes: Int {
        results.reduce(0) { $0 + ($1.newBytes ?? $1.originalBytes) }
    }

    var convertedBytes: Int {
        results.reduce(0) { $0 + $1.originalBytes }
    }

    func add(urls: [URL]) {
        let images = urls.filter(Self.isImage)
        Log.write("queued \(images.count) of \(urls.count) file(s): \(images.map(\.lastPathComponent).joined(separator: ", "))")
        guard !images.isEmpty else { return }
        let known = Set(items.map(\.url.standardizedFileURL))
        items += images
            .filter { !known.contains($0.standardizedFileURL) }
            .map { Item(url: $0, bytes: Converter.byteSize(of: $0)) }
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

    func convert() {
        let queue = pending
        guard !queue.isEmpty, !isRunning else { return }
        save()
        let settings = settings()
        let urls = queue.map(\.url)
        let ids = queue.map(\.id)
        Log.write("converting \(urls.count) file(s) → \(settings.targetBytes / 1000) KB limit")
        isRunning = true

        Task.detached(priority: .userInitiated) { [self] in
            let reserver = NameReserver(sources: urls)
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                let result = Converter.convert(url: urls[index], settings: settings, reserver: reserver)
                if case .failed(let reason) = result.status {
                    Log.write("failed \(urls[index].lastPathComponent): \(reason)")
                }
                Task { @MainActor in self.apply(result, to: ids[index]) }
            }
            Log.write("finished \(urls.count) file(s)")
            await MainActor.run { self.isRunning = false }
        }
    }

    private func apply(_ result: FileResult, to id: Item.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].result = result
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
        return "\(Int(size.width))×\(Int(size.height))"
    }
}
