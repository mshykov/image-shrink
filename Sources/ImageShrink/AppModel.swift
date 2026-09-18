import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {

    @Published var files: [URL] = []
    @Published var results: [FileResult] = []
    @Published var isRunning = false
    @Published var done = 0

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
    var totalBytes: Int { files.reduce(0) { $0 + Converter.byteSize(of: $1) } }
    var savedBytes: Int {
        results.reduce(0) { total, result in
            guard let new = result.newBytes else { return total }
            return total + max(0, result.originalBytes - new)
        }
    }

    func add(urls: [URL]) {
        let images = urls.filter(Self.isImage)
        Log.write("queued \(images.count) of \(urls.count) file(s): \(images.map(\.lastPathComponent).joined(separator: ", "))")
        guard !images.isEmpty else { return }
        if !results.isEmpty { results = []; done = 0 }
        let known = Set(files.map(\.standardizedFileURL))
        files += images.filter { !known.contains($0.standardizedFileURL) }
    }

    func clear() {
        files = []
        results = []
        done = 0
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
        guard !files.isEmpty, !isRunning else { return }
        save()
        let settings = settings()
        let urls = files
        Log.write("converting \(urls.count) file(s) → \(settings.targetBytes / 1000) KB limit")
        isRunning = true
        results = []
        done = 0

        Task.detached(priority: .userInitiated) { [self] in
            let batch = Batch(count: urls.count)
            let reserver = NameReserver(sources: urls)
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                let result = Converter.convert(url: urls[index], settings: settings, reserver: reserver)
                if case .failed(let reason) = result.status {
                    Log.write("failed \(urls[index].lastPathComponent): \(reason)")
                }
                let finished = batch.store(result, at: index)
                Task { @MainActor in self.done = finished }
            }
            let finished = batch.ordered()
            Log.write("finished \(finished.count) file(s)")
            await MainActor.run {
                self.results = finished
                self.done = finished.count
                self.isRunning = false
            }
        }
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

/// Collects results from the concurrent workers.
private final class Batch: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [FileResult?]
    private var finished = 0

    init(count: Int) { slots = Array(repeating: nil, count: count) }

    func store(_ result: FileResult, at index: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        slots[index] = result
        finished += 1
        return finished
    }

    func ordered() -> [FileResult] {
        lock.lock()
        defer { lock.unlock() }
        return slots.compactMap { $0 }
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
