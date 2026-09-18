import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum DestinationMode: String, CaseIterable, Sendable {
    case sameFolder, subfolder, custom
}

struct ConversionSettings: Sendable {
    var targetBytes: Int
    /// Longest side in pixels; nil keeps the original resolution.
    var maxDimension: Int?
    var destinationMode: DestinationMode = .sameFolder
    var customDestination: URL?
    var subfolderName = "Converted"
    var replaceOriginals = false
    /// Empty means derive it from the limit: "-2MB", "-500KB".
    var suffix = ""
    var stripMetadata = false
    var keepDates = true
    var skipSmallEnough = true

    /// Below this the picture starts to look bad, so downscaling takes over.
    var minQuality = 0.30
}

extension ConversionSettings {
    /// "-2MB", "-1.5MB", "-500KB" — the number in the name is the limit it was made for.
    var resolvedSuffix: String {
        let trimmed = suffix.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty else { return trimmed }
        return Self.automaticSuffix(for: targetBytes)
    }

    static func automaticSuffix(for bytes: Int) -> String {
        if bytes < 1_000_000 { return "-\(max(1, bytes / 1000))KB" }
        let megabytes = Double(bytes) / 1_000_000
        let text = megabytes == megabytes.rounded()
            ? String(Int(megabytes))
            : String(format: "%.1f", megabytes)
        return "-\(text)MB"
    }
}

struct FileResult: Identifiable, Sendable {
    enum Status: Sendable {
        case converted
        case skipped(String)
        case failed(String)
    }

    let id = UUID()
    var source: URL
    var output: URL?
    var originalBytes: Int
    var newBytes: Int?
    var quality: Double?
    var pixelSize: CGSize?
    var status: Status

    var isFailure: Bool { if case .failed = status { return true }; return false }
}

enum Converter {

    static func convert(url: URL, settings: ConversionSettings,
                        reserver: NameReserver) -> FileResult {
        let originalBytes = byteSize(of: url)
        var result = FileResult(source: url, originalBytes: originalBytes, status: .converted)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else {
            result.status = .failed("could not read image")
            return result
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let fullSize = pixelSize(from: properties)
        let isJPEG = (CGImageSourceGetType(source) as String?) == UTType.jpeg.identifier

        let needsResize = settings.maxDimension.map { Double($0) < max(fullSize.width, fullSize.height) } ?? false
        if settings.skipSmallEnough, isJPEG, originalBytes <= settings.targetBytes,
           !needsResize, !settings.stripMetadata {
            return passThrough(url: url, settings: settings, result: result,
                               pixels: fullSize, reserver: reserver)
        }

        do {
            let directory = try destinationDirectory(for: url, settings: settings)
            let output = outputURL(for: url, in: directory, settings: settings, reserver: reserver)

            guard let encoded = encodeToTarget(source: source, properties: properties,
                                               fullSize: fullSize, originalBytes: originalBytes,
                                               settings: settings) else {
                result.status = .failed("could not compress under the limit")
                return result
            }

            try write(encoded.data, to: output, replacing: url, settings: settings)

            result.output = output
            result.newBytes = encoded.data.count
            result.quality = encoded.quality
            result.pixelSize = encoded.pixels
            result.status = .converted
        } catch {
            result.status = .failed(error.localizedDescription)
        }
        return result
    }

    // MARK: - Encoding

    private struct Encoded {
        var data: Data
        var quality: Double
        var pixels: CGSize
    }

    /// Drops quality first, then resolution, until the file fits the target.
    private static func encodeToTarget(source: CGImageSource, properties: [CFString: Any],
                                       fullSize: CGSize, originalBytes: Int,
                                       settings: ConversionSettings) -> Encoded? {
        let outputProperties = self.outputProperties(from: properties, strip: settings.stripMetadata)
        var maxPixel = Int(max(fullSize.width, fullSize.height).rounded())
        if let limit = settings.maxDimension { maxPixel = min(maxPixel, limit) }
        var fallback: Encoded?

        // HEIC stores the same photo in about half the bytes of a JPEG, so re-encoding a
        // small HEIC at high quality sails under the limit while ending up bigger than the
        // file it came from. Aim for the original's size too — but with a higher quality
        // floor, because not inflating is worth less than a picture that still looks right.
        let noInflation = min(settings.targetBytes, originalBytes)

        for _ in 0..<8 {
            guard let image = makeImage(source, maxPixel: maxPixel, fullSize: fullSize) else { return fallback }
            let flat = flattenIfNeeded(image)
            let pixels = CGSize(width: flat.width, height: flat.height)

            if noInflation < settings.targetBytes,
               let hit = searchQuality(flat, properties: outputProperties,
                                       target: noInflation, minQuality: noInflationFloor) {
                return Encoded(data: hit.0, quality: hit.1, pixels: pixels)
            }
            if let hit = searchQuality(flat, properties: outputProperties,
                                       target: settings.targetBytes, minQuality: settings.minQuality) {
                return Encoded(data: hit.0, quality: hit.1, pixels: pixels)
            }
            // Even the lowest quality overshoots: remember it and shrink the pixels.
            if let floorData = encode(flat, quality: settings.minQuality, properties: outputProperties) {
                fallback = Encoded(data: floorData, quality: settings.minQuality, pixels: pixels)
                let ratio = Double(settings.targetBytes) / Double(floorData.count)
                let next = Int(Double(maxPixel) * min(0.9, max(0.45, sqrt(ratio) * 0.97)))
                if next < 320 { return fallback }
                maxPixel = next
            } else {
                return fallback
            }
        }
        return fallback
    }

    /// Below this, matching the original's size costs more than the extra bytes are worth.
    private static let noInflationFloor = 0.60

    /// Binary search for the highest quality that still fits.
    private static func searchQuality(_ image: CGImage, properties: [CFString: Any],
                                      target: Int, minQuality: Double) -> (Data, Double)? {
        var high = 0.92
        if let data = encode(image, quality: high, properties: properties), data.count <= target {
            return (data, high)
        }
        var low = minQuality
        guard let floorData = encode(image, quality: low, properties: properties),
              floorData.count <= target else { return nil }

        var best = (floorData, low)
        for _ in 0..<6 {
            let mid = (low + high) / 2
            guard let data = encode(image, quality: mid, properties: properties) else { break }
            if data.count <= target {
                best = (data, mid)
                low = mid
                if Double(data.count) > 0.97 * Double(target) { break }
            } else {
                high = mid
            }
        }
        return best
    }

    private static func encode(_ image: CGImage, quality: Double, properties: [CFString: Any]) -> Data? {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        var options = properties
        options[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }

    // MARK: - Decoding

    private static func makeImage(_ source: CGImageSource, maxPixel: Int, fullSize: CGSize) -> CGImage? {
        var options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        if Double(maxPixel) < max(fullSize.width, fullSize.height) {
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
            // Keep the pixels in their stored orientation so the EXIF tag stays valid.
            options[kCGImageSourceCreateThumbnailWithTransform] = false
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixel
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
    }

    /// JPEG has no alpha channel, so transparency is composited onto white.
    private static func flattenIfNeeded(_ image: CGImage) -> CGImage {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return image
        default:
            break
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return image }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }

    private static func outputProperties(from source: [CFString: Any], strip: Bool) -> [CFString: Any] {
        // Orientation survives stripping — without it the picture displays rotated.
        var out: [CFString: Any] = [:]
        if let orientation = source[kCGImagePropertyOrientation] {
            out[kCGImagePropertyOrientation] = orientation
        }
        guard !strip else { return out }

        let carried: [CFString] = [
            kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight,
            kCGImagePropertyExifDictionary, kCGImagePropertyExifAuxDictionary,
            kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary,
            kCGImagePropertyIPTCDictionary,
        ]
        for key in carried where source[key] != nil { out[key] = source[key] }
        return out
    }

    private static func pixelSize(from properties: [CFString: Any]) -> CGSize {
        let width = properties[kCGImagePropertyPixelWidth] as? Double ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Double ?? 0
        return CGSize(width: width, height: height)
    }

    // MARK: - Files

    static func destinationDirectory(for source: URL, settings: ConversionSettings) throws -> URL {
        let parent = source.deletingLastPathComponent()
        switch settings.destinationMode {
        case .sameFolder:
            return parent
        case .subfolder:
            let directory = parent.appendingPathComponent(settings.subfolderName, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        case .custom:
            guard let directory = settings.customDestination else { return parent }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }
    }

    static func outputURL(for source: URL, in directory: URL, settings: ConversionSettings,
                          reserver: NameReserver) -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let suffix = settings.resolvedSuffix
        let plain = directory.appendingPathComponent(base + ".jpg")

        // Converting a JPEG onto itself is only allowed when the user asked to replace originals.
        let isSource = plain.standardizedFileURL == source.standardizedFileURL
        if isSource && settings.replaceOriginals { return reserver.take(plain) }

        return reserver.claimFirstFree { index in
            switch index {
            case 0: return plain
            case 1: return directory.appendingPathComponent(base + suffix + ".jpg")
            default: return directory.appendingPathComponent("\(base)\(suffix)-\(index).jpg")
            }
        } blocked: { candidate in
            candidate.standardizedFileURL == source.standardizedFileURL
        }
    }

    private static func write(_ data: Data, to output: URL, replacing source: URL,
                              settings: ConversionSettings) throws {
        let manager = FileManager.default
        let dates = settings.keepDates ? fileDates(of: source) : nil

        if output.standardizedFileURL == source.standardizedFileURL {
            let temporary = output.deletingLastPathComponent()
                .appendingPathComponent(".imageshrink-\(UUID().uuidString).jpg")
            try data.write(to: temporary, options: .atomic)
            apply(dates, to: temporary)
            _ = try manager.replaceItemAt(output, withItemAt: temporary)
            return
        }

        try data.write(to: output, options: .atomic)
        apply(dates, to: output)
        if settings.replaceOriginals {
            try? manager.trashItem(at: source, resultingItemURL: nil)
        }
    }

    /// Already small enough: nothing to compress, just honour the destination choice.
    private static func passThrough(url: URL, settings: ConversionSettings, result: FileResult,
                                    pixels: CGSize, reserver: NameReserver) -> FileResult {
        var result = result
        result.pixelSize = pixels
        guard settings.destinationMode != .sameFolder else {
            result.status = .skipped("already under the limit")
            return result
        }
        do {
            let directory = try destinationDirectory(for: url, settings: settings)
            let output = outputURL(for: url, in: directory, settings: settings, reserver: reserver)
            try FileManager.default.copyItem(at: url, to: output)
            apply(settings.keepDates ? fileDates(of: url) : nil, to: output)
            result.output = output
            result.newBytes = result.originalBytes
            result.status = .skipped("copied, already under the limit")
        } catch {
            result.status = .failed(error.localizedDescription)
        }
        return result
    }

    private static func fileDates(of url: URL) -> (Date?, Date?) {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return (values?.creationDate, values?.contentModificationDate)
    }

    private static func apply(_ dates: (Date?, Date?)?, to url: URL) {
        guard let dates else { return }
        var attributes: [FileAttributeKey: Any] = [:]
        if let creation = dates.0 { attributes[.creationDate] = creation }
        if let modification = dates.1 { attributes[.modificationDate] = modification }
        guard !attributes.isEmpty else { return }
        try? FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }

    static func byteSize(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }
}
