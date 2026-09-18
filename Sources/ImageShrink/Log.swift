import Foundation

/// A Quick Action that silently does nothing is hard to diagnose, so the app keeps its own trail.
enum Log {
    static let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/ImageShrink.log")

    private static let lock = NSLock()
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        let line = "\(stamp.string(from: Date()))  \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let manager = FileManager.default
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            // Keep the file from growing forever.
            if (try? handle.seekToEnd()) ?? 0 > 256_000 {
                try? handle.truncate(atOffset: 0)
            }
            try? handle.write(contentsOf: data)
        } else {
            try? manager.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
            try? data.write(to: url)
        }
    }
}
