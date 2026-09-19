import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The menu bar is the app's real home: most conversions start in Finder or here and never
/// open a window. Dropping images on the icon converts them with the saved settings.
@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let model: AppModel
    private let onOpenWindow: () -> Void

    init(model: AppModel, onOpenWindow: @escaping () -> Void) {
        self.model = model
        self.onOpenWindow = onOpenWindow
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.down.right.and.arrow.up.left.square",
                                     accessibilityDescription: "Image Shrink")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        item.button?.registerForDraggedTypes([.fileURL])
        if let button = item.button {
            DropTarget.attach(to: button) { [weak self] urls in
                self?.convertDropped(urls)
            }
        }
        statusItem = item
    }

    @objc private func togglePanel(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(sender)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = AppDelegate.sizedController(MenuBarPanel(
            model: model,
            openWindow: { [weak self] in
                self?.popover?.performClose(nil)
                self?.onOpenWindow()
            },
            dropped: { [weak self] urls in self?.convertDropped(urls) }), popover: popover)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
    }

    /// Dropped images never open a window — same promise as the Finder shortcut.
    private func convertDropped(_ urls: [URL]) {
        let images = urls.filter(AppModel.isImage)
        guard !images.isEmpty else { return }
        let settings = model.settings()
        let hud = ConversionHUD(total: images.count)
        hud.show()

        Task.detached(priority: .userInitiated) {
            let reserver = NameReserver(sources: images)
            let counter = Counter()
            var before = 0, after = 0
            let lock = NSLock()

            DispatchQueue.concurrentPerform(iterations: images.count) { index in
                let result = Converter.convert(url: images[index], settings: settings,
                                               reserver: reserver)
                let done = counter.increment()
                lock.lock()
                before += result.originalBytes
                after += result.newBytes ?? result.originalBytes
                let outputs = result.output
                lock.unlock()
                Task { @MainActor in hud.advance(done: done, latest: outputs) }
            }

            let totals = (before, after)
            await MainActor.run {
                History.add(count: images.count, before: totals.0, after: totals.1)
                hud.finish(before: totals.0, after: totals.1)
                Feedback.play(success: true)
            }
        }
    }
}

/// Small thread-safe tally for the concurrent workers.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

/// Lets an AppKit control accept image drops without subclassing it everywhere.
final class DropTarget: NSObject, NSDraggingDestination {
    private static var targets: [DropTarget] = []
    private let handler: ([URL]) -> Void

    private init(handler: @escaping ([URL]) -> Void) {
        self.handler = handler
    }

    static func attach(to view: NSView, handler: @escaping ([URL]) -> Void) {
        let target = DropTarget(handler: handler)
        targets.append(target)     // the view does not retain its dragging destination
        view.registerForDraggedTypes([.fileURL])
        objc_setAssociatedObject(view, "imageshrink.drop", target, .OBJC_ASSOCIATION_RETAIN)
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: nil) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        handler(urls)
        return true
    }
}
