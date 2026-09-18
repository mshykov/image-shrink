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
      --saved            start from the settings the app window last used
      --quiet            print only failures
      --selftest         drive the window's own model headlessly (used by scripts/smoke-test.sh)
      --snapshot <png>   render the window to a PNG and exit (design review)
      --snapshot-run     convert first, so the snapshot shows the finished state
    """

    static func run(arguments: [String]) -> Int32 {
        // --saved goes through AppModel so there is one definition of what the settings are.
        var settings = arguments.contains("--saved")
            ? MainActor.assumeIsolated { AppModel().settings() }
            : ConversionSettings(targetBytes: 2_000_000, maxDimension: nil)
        var files: [URL] = []
        var quiet = false
        var selftest = false
        var snapshot: String?
        var snapshotRun = false
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
            case "--quiet":
                quiet = true
            case "--selftest":
                selftest = true
            case "--snapshot":
                guard let value = next(argument) else { return 2 }
                snapshot = value
            case "--snapshot-run":
                snapshotRun = true
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
                render(to: snapshot, files: files, settings: settings, convert: snapshotRun)
            }
        }

        guard !files.isEmpty else {
            print(usage)
            return 2
        }

        if selftest {
            return MainActor.assumeIsolated { selfTest(files: files, settings: settings) }
        }

        var failures = 0
        let reserver = NameReserver(sources: files)
        for url in files {
            let result = Converter.convert(url: url, settings: settings, reserver: reserver)
            switch result.status {
            case .converted:
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
        return failures > 0 ? 1 : 0
    }

    /// Renders the real window offscreen. Glass samples what is behind it, so the capture
    /// shows layout and typography rather than the final translucency.
    @MainActor
    private static func render(to path: String, files: [URL], settings: ConversionSettings,
                               convert: Bool) -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let model = AppModel()
        model.targetMB = Double(settings.targetBytes) / 1_000_000
        model.destinationMode = settings.destinationMode
        model.customDestination = settings.customDestination
        model.add(urls: files)
        if convert { model.convert() }

        let hosting = NSHostingView(rootView: ContentView().environmentObject(model))
        hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 680)
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
    private static func selfTest(files: [URL], settings: ConversionSettings) -> Int32 {
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
        let deadline = Date().addingTimeInterval(120)
        while model.isRunning && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        for result in model.results {
            let name = result.output?.lastPathComponent ?? result.source.lastPathComponent
            print("selftest: \(name) \(Format.bytes(result.originalBytes)) → "
                  + "\(result.newBytes.map(Format.bytes) ?? "—") \(Format.pixels(result.pixelSize))")
        }
        let failures = model.results.filter(\.isFailure).count
        print("selftest: \(model.results.count) result(s), \(failures) failure(s), "
              + "saved \(Format.bytes(model.savedBytes))")
        return failures == 0 && model.results.count == files.count ? 0 : 1
    }
}
