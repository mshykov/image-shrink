import AppKit
import Foundation
import SwiftUI

/// Headless mode — the same engine the window uses, for scripts and tests.
enum CLI {
    static let usage = """
    Image Shrink — convert HEIC/JPEG/PNG to JPEG under a size limit.

      ImageShrink --cli [options] <files…>

    Options
      --target-mb <n>    size limit in MB (default 2)
      --max-dim <px>     limit the longest side (default: keep original)
      --dest <dir>       write into <dir> (default: next to the original)
      --subfolder        write into a "Converted" subfolder
      --suffix <text>    suffix used when the name is taken (default -small)
      --replace          move originals to the Trash after converting
      --strip            drop EXIF/GPS metadata
      --no-skip          re-encode even if the file is already under the limit
      --preset <id>      use a named preset (see --list-presets)
      --list-presets     print the presets, tab separated, for the installer
      --saved            start from the settings the app window last used
      --quiet            print only failures, and post a notification instead
      --notify           post a completion notification
      --selftest         drive the window's own model headlessly (used by scripts/smoke-test.sh)
      --cancel-after <s> with --selftest: stop the run after this many seconds
      --snapshot <png>   render the window to a PNG and exit (design review)
      --snapshot-run     convert first, so the snapshot shows the finished state
      --snapshot-settings  render the Settings window instead
      --snapshot-popover   render the settings popover instead
    """

    static func run(arguments: [String]) -> Int32 {
        // --saved goes through AppModel so there is one definition of what the settings are.
        var settings = arguments.contains("--saved")
            ? MainActor.assumeIsolated { AppModel().settings() }
            : ConversionSettings(targetBytes: 2_000_000, maxDimension: nil)
        // Settings can pin the instant action to a preset instead of the last used values.
        if arguments.contains("--saved"), let pinned = Preset.named(Settings.instantPreset) {
            settings = pinned.applied(to: settings)
        }
        var files: [URL] = []
        var quiet = false
        var selftest = false
        var cancelAfter: Double = 0
        var snapshot: String?
        var snapshotRun = false
        var snapshotSettings = false
        var snapshotPopover = false
        var index = 0

        func next(_ flag: String) -> String? {
            index += 1
            guard index < arguments.count else {
                FileHandle.standardError.write(Data("missing value for \(flag)\n".utf8))
                return nil
            }
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--cli":
                break
            case "--help", "-h":
                print(usage)
                return 0
            case "--target-mb":
                guard let value = next(argument), let mb = Double(value) else { return 2 }
                settings.targetBytes = Int(mb * 1_000_000)
            case "--max-dim":
                guard let value = next(argument), let px = Int(value) else { return 2 }
                settings.maxDimension = px > 0 ? px : nil
            case "--dest":
                guard let value = next(argument) else { return 2 }
                settings.destinationMode = .custom
                settings.customDestination = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            case "--subfolder":
                settings.destinationMode = .subfolder
            case "--suffix":
                guard let value = next(argument) else { return 2 }
                settings.suffix = value
            case "--replace":
                settings.replaceOriginals = true
            case "--strip":
                settings.stripMetadata = true
            case "--no-skip":
                settings.skipSmallEnough = false
            case "--saved":
                break
            case "--list-presets":
                for preset in Preset.all {
                    print("\(preset.id)\t\(preset.menuTitle)\t\(preset.detail)")
                }
                return 0
            case "--preset":
                guard let value = next(argument) else { return 2 }
                guard let preset = Preset.named(value) else {
                    FileHandle.standardError.write(Data("unknown preset \(value)\n".utf8))
                    return 2
                }
                settings = preset.applied(to: settings)
            case "--quiet":
                quiet = true
            case "--notify":
                break
            case "--selftest":
                selftest = true
            case "--cancel-after":
                guard let value = next(argument), let seconds = Double(value) else { return 2 }
                cancelAfter = seconds
            case "--snapshot":
                guard let value = next(argument) else { return 2 }
                snapshot = value
            case "--snapshot-run":
                snapshotRun = true
            case "--snapshot-settings":
                snapshotSettings = true
            case "--snapshot-popover":
                snapshotPopover = true
            default:
                if argument.hasPrefix("-") {
                    FileHandle.standardError.write(Data("unknown option \(argument)\n".utf8))
                    return 2
                }
                files.append(URL(fileURLWithPath: (argument as NSString).expandingTildeInPath))
            }
            index += 1
        }

        if let snapshot {
            return MainActor.assumeIsolated {
                render(to: snapshot, files: files, settings: settings,
                       convert: snapshotRun, settingsScreen: snapshotSettings,
                       popover: snapshotPopover)
            }
        }

        guard !files.isEmpty else {
            print(usage)
            return 2
        }

        if selftest {
            return MainActor.assumeIsolated {
                selfTest(files: files, settings: settings, cancelAfter: cancelAfter)
            }
        }

        var failures = 0
        var savedBytes = 0
        let notify = arguments.contains("--notify")
        let reserver = NameReserver(sources: files)
        for url in files {
            let result = Converter.convert(url: url, settings: settings, reserver: reserver)
            switch result.status {
            case .converted:
                savedBytes += max(0, result.originalBytes - (result.newBytes ?? result.originalBytes))
                guard !quiet else { break }
                let quality = result.quality.map { " q\(Int($0 * 100))" } ?? ""
                let pixels = Format.pixels(result.pixelSize)
                print("""
                \(url.lastPathComponent): \(Format.bytes(result.originalBytes)) → \
                \(Format.bytes(result.newBytes ?? 0)) (\(pixels)\(quality)) → \
                \(result.output?.path ?? "")
                """)
            case .skipped(let reason):
                if !quiet { print("\(url.lastPathComponent): \(reason)") }
            case .failed(let reason):
                failures += 1
                FileHandle.standardError.write(Data("\(url.lastPathComponent): \(reason)\n".utf8))
            }
        }
        if quiet || notify {
            Feedback.play(success: failures == 0)
            let converted = files.count - failures
            let saved = savedBytes
            var body = converted == 1 ? "1 image" : "\(converted) images"
            if saved > 0 { body += " · saved \(Format.bytes(saved))" }
            if failures > 0 { body += " · \(failures) failed" }
            Notifier.post(title: failures > 0 ? "Converted with errors" : "Images converted",
                          body: body, waitForDelivery: true)
        }
        return failures > 0 ? 1 : 0
    }

    /// Renders the real window offscreen. Glass samples what is behind it, so the capture
    /// shows layout and typography rather than the final translucency.
    @MainActor
    private static func render(to path: String, files: [URL], settings: ConversionSettings,
                               convert: Bool, settingsScreen: Bool = false,
                               popover: Bool = false) -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel()
        model.targetMB = Double(settings.targetBytes) / 1_000_000
        model.destinationMode = settings.destinationMode
        model.customDestination = settings.customDestination
        model.add(urls: files)
        if convert { model.convert() }

        let hosting: NSView
        if settingsScreen {
            hosting = NSHostingView(rootView: SettingsView())
        } else if popover {
            hosting = NSHostingView(rootView: SettingsPopover().environmentObject(model))
        } else {
            hosting = NSHostingView(rootView: ContentView().environmentObject(model))
        }
        hosting.frame = NSRect(x: 0, y: 0, width: settingsScreen ? 460 : 560, height: 680)
        if settingsScreen || popover {
            hosting.layoutSubtreeIfNeeded()
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        }
        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Image Shrink"
        window.applyGlassChrome()
        window.contentView = hosting
        window.orderFrontRegardless()

        let deadline = Date().addingTimeInterval(convert ? 60 : 1.5)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            if convert && !model.isRunning && model.isFinished { break }
        }
        // Let the finished state settle before capturing.
        let settle = Date().addingTimeInterval(1.0)
        while Date() < settle {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        // cacheDisplay misses layer-composited content (scroll views, materials); rendering
        // the layer tree catches it.
        let scale = 2.0
        let width = Int(hosting.bounds.width * scale), height = Int(hosting.bounds.height * scale)
        guard let layer = hosting.layer,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1 }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        layer.render(in: context)
        guard let image = context.makeImage() else { return 1 }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return 1 }
        try? data.write(to: URL(fileURLWithPath: path))
        print("snapshot: \(path)")
        return 0
    }

    /// Runs the exact path the Convert button takes, without a window.
    @MainActor
    private static func selfTest(files: [URL], settings: ConversionSettings,
                                 cancelAfter: Double = 0) -> Int32 {
        let model = AppModel()
        model.targetMB = Double(settings.targetBytes) / 1_000_000
        model.maxDimension = settings.maxDimension ?? 0
        model.destinationMode = settings.destinationMode
        model.customDestination = settings.customDestination
        model.suffix = settings.suffix
        model.stripMetadata = settings.stripMetadata
        model.skipSmallEnough = settings.skipSmallEnough
        model.add(urls: files)

        guard model.items.count == files.count else {
            print("selftest: model accepted \(model.items.count) of \(files.count) files")
            return 1
        }
        model.convert()
        if cancelAfter > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + cancelAfter) { model.cancel() }
        }
        let deadline = Date().addingTimeInterval(120)
        while model.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        // The last results arrive on the main actor just after the run ends.
        let settle = Date().addingTimeInterval(0.4)
        while Date() < settle {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        for result in model.results {
            let name = result.output?.lastPathComponent ?? result.source.lastPathComponent
            print("selftest: \(name) \(Format.bytes(result.originalBytes)) → "
                  + "\(result.newBytes.map(Format.bytes) ?? "—") \(Format.pixels(result.pixelSize))")
        }
        let failures = model.results.filter(\.isFailure).count
        print("selftest: \(model.results.count) result(s), \(failures) failure(s), "
              + "\(model.pending.count) still pending, saved \(Format.bytes(model.savedBytes))")
        if cancelAfter > 0 {
            // A cancelled run must stop cleanly: not running, and some work left undone.
            return !model.isRunning && !model.pending.isEmpty ? 0 : 1
        }
        return failures == 0 && model.results.count == files.count ? 0 : 1
    }
}
