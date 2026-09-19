import AppKit
import UserNotifications

/// Shared stop signal. `concurrentPerform` cannot be interrupted mid-file, so the workers
/// check this before picking up the next one — an in-flight image always finishes.
final class Cancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }
}

/// A bar across the Dock icon, so a long batch is legible with the window hidden.
@MainActor
enum DockProgress {
    private static var view: DockProgressView?

    static func show(_ fraction: Double) {
        // There is no NSApplication in the CLI paths, and NSApp traps when unwrapped.
        guard let tile = NSApp?.dockTile else { return }
        if view == nil {
            let progress = DockProgressView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
            view = progress
            tile.contentView = progress
        }
        view?.fraction = max(0, min(1, fraction))
        tile.display()
    }

    static func clear() {
        view = nil
        guard let tile = NSApp?.dockTile else { return }
        tile.contentView = nil
        tile.display()
    }
}

private final class DockProgressView: NSView {
    var fraction: Double = 0

    override func draw(_ dirtyRect: NSRect) {
        NSApp?.applicationIconImage?.draw(in: bounds)

        let height = bounds.height * 0.10
        let inset = bounds.width * 0.14
        let track = NSRect(x: inset, y: bounds.height * 0.09,
                           width: bounds.width - inset * 2, height: height)
        let radius = height / 2

        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        var filled = track
        filled.size.width = max(height, track.width * fraction)
        NSColor.white.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}

/// Completion notice for the runs that have no window to look at.
enum Notifier {
    static var isEnabled: Bool {
        Settings.defaults.object(forKey: Settings.notifyKey) as? Bool ?? true
    }

    /// Unbundled runs (the binary straight from build/) have no notification identity.
    static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    static func post(title: String, body: String, waitForDelivery: Bool = false) {
        guard isEnabled, isBundled else { return }
        let center = UNUserNotificationCenter.current()
        let group = DispatchGroup()
        group.enter()

        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return group.leave() }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
            center.add(request) { _ in group.leave() }
        }

        if waitForDelivery {
            _ = group.wait(timeout: .now() + 3)
        }
    }
}

/// The audible half of "it finished" for runs with no window.
enum Feedback {
    static func play(success: Bool) {
        guard Settings.soundOnFinish, let sound = NSSound(named: success ? "Pop" : "Basso") else { return }
        sound.play()
        // A command-line run would exit before the sound is heard.
        Thread.sleep(forTimeInterval: 0.6)
    }
}


/// Totals gathered from the concurrent workers of a window-less run.
final class RunTotals: @unchecked Sendable {
    private let lock = NSLock()
    private var before = 0
    private var after = 0
    private var converted = 0
    private var failures = 0
    private var firstFailure: String?
    private var finished = false

    var isComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func add(_ result: FileResult) {
        lock.lock()
        defer { lock.unlock() }
        before += result.originalBytes
        after += result.newBytes ?? result.originalBytes
        if case .failed(let reason) = result.status {
            failures += 1
            if firstFailure == nil {
                firstFailure = "\(result.source.lastPathComponent): \(reason)"
            }
        } else {
            converted += 1
        }
    }

    func complete() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    func snapshot() -> (before: Int, after: Int, converted: Int, failures: Int, firstFailure: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (before, after, converted, failures, firstFailure)
    }
}
