import Foundation

/// Hands out output names to the parallel workers. Checking the disk alone is not enough:
/// two files converted at the same time both see a free name and one overwrites the other.
final class NameReserver: @unchecked Sendable {
    private let lock = NSLock()
    private var taken: Set<String> = []

    /// Claims an exact name, even if a file is already there (replacing in place).
    func take(_ url: URL) -> URL {
        lock.lock()
        defer { lock.unlock() }
        taken.insert(url.standardizedFileURL.path)
        return url
    }

    /// Walks the candidates until one is free on disk and unclaimed, then claims it.
    func claimFirstFree(candidate: (Int) -> URL, blocked: (URL) -> Bool = { _ in false }) -> URL {
        lock.lock()
        defer { lock.unlock() }
        for index in 0..<1000 {
            let url = candidate(index)
            let key = url.standardizedFileURL.path
            guard !taken.contains(key), !blocked(url),
                  !FileManager.default.fileExists(atPath: url.path) else { continue }
            taken.insert(key)
            return url
        }
        let fallback = candidate(0).deletingPathExtension()
            .appendingPathExtension("\(UUID().uuidString.prefix(8)).jpg")
        taken.insert(fallback.standardizedFileURL.path)
        return fallback
    }
}
