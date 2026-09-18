import Foundation

/// Hands out output names to the parallel workers. Checking the disk alone is not enough:
/// two files converted at the same time both see a free name and one overwrites the other.
final class NameReserver: @unchecked Sendable {
    private let lock = NSLock()
    private var taken: Set<String> = []
    private let ambiguousBases: Set<String>

    /// Knowing the whole batch up front is what makes the names deterministic: when two
    /// sources share a base name, both get their format in the name rather than whichever
    /// worker finished first keeping the plain one.
    init(sources: [URL] = []) {
        var counts: [String: Int] = [:]
        for source in sources {
            counts[source.deletingPathExtension().lastPathComponent.lowercased(), default: 0] += 1
        }
        ambiguousBases = Set(counts.filter { $0.value > 1 }.map(\.key))
    }

    func needsSourceKind(_ base: String) -> Bool {
        ambiguousBases.contains(base.lowercased())
    }

    /// Walks the candidates until one is free on disk and unclaimed, then claims it.
    /// `ignoreExisting` is for replacing originals, where the file on disk is the point.
    func claimFirstFree(ignoreExisting: Bool = false,
                        candidate: (Int) -> URL,
                        blocked: (URL) -> Bool = { _ in false }) -> URL {
        lock.lock()
        defer { lock.unlock() }
        for index in 0..<1000 {
            let url = candidate(index)
            let key = url.standardizedFileURL.path
            guard !taken.contains(key), !blocked(url),
                  ignoreExisting || !FileManager.default.fileExists(atPath: url.path) else { continue }
            taken.insert(key)
            return url
        }
        let fallback = candidate(0).deletingPathExtension()
            .appendingPathExtension("\(UUID().uuidString.prefix(8)).jpg")
        taken.insert(fallback.standardizedFileURL.path)
        return fallback
    }
}
