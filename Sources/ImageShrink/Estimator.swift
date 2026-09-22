import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What a file will come out as, worked out before the user commits to it.
struct Estimate: Sendable {
    enum Outcome: Sendable {
        /// Already a JPEG under the limit, and the settings say leave those alone.
        case untouched
        case reencoded(quality: Double)
        /// Even the lowest usable quality overshoots, so the pixels have to go.
        case resized
    }

    var bytes: Int
    var outcome: Outcome
    var pixels: CGSize

    var isSmaller: Bool { false }
}

/// Size as a function of quality, measured once per file at full size.
///
/// A downscaled proxy was tried first and predicts between 0.4× and 1.4× of the truth
/// depending on how smooth the picture is — useless for a number shown to the user.
/// Three full-size encodes cost 0.1–0.6 s per file, land within a few per cent, and only
/// have to be redone when the resolution setting changes; changing the limit is then
/// interpolation, which is instant.
struct SizeCurve: Sendable {
    var samples: [(quality: Double, bytes: Int)]
    var pixels: CGSize
    var sourceBytes: Int
    var isJPEG: Bool
    /// The resolution cap this curve was measured at, so a change can invalidate it.
    var maxDimension: Int?
}

enum Estimator {
    static let sampledQualities = [0.35, 0.60, 0.85, 0.92]

    static func curve(for url: URL, maxDimension: Int?) -> SizeCurve? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = properties[kCGImagePropertyPixelWidth] as? Double ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Double ?? 0
        guard width > 0, height > 0 else { return nil }

        var options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        if let cap = maxDimension, Double(cap) < max(width, height) {
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
            options[kCGImageSourceCreateThumbnailWithTransform] = false
            options[kCGImageSourceThumbnailMaxPixelSize] = cap
        }

        let decodedImage: CGImage?
        if options[kCGImageSourceThumbnailMaxPixelSize] != nil {
            decodedImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            decodedImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        }
        guard let decoded = decodedImage else { return nil }
        // The same preparation the converter applies, or the samples describe an image nobody
        // is going to encode: a CMYK original measured as CMYK, a transparent PNG as RGBA.
        let image = Converter.prepareForJPEG(decoded)

        let samples = sampledQualities.compactMap { quality -> (Double, Int)? in
            guard let bytes = encodedSize(image, quality: quality) else { return nil }
            return (quality, bytes)
        }
        guard samples.count == sampledQualities.count else { return nil }

        return SizeCurve(samples: samples,
                         pixels: CGSize(width: image.width, height: image.height),
                         sourceBytes: Converter.byteSize(of: url),
                         isJPEG: (CGImageSourceGetType(source) as String?) == UTType.jpeg.identifier,
                         maxDimension: maxDimension)
    }

    /// Mirrors the converter's rules, including never handing back a bigger file.
    static func estimate(_ curve: SizeCurve, settings: ConversionSettings) -> Estimate {
        let resizeRequested = settings.maxDimension != nil
        if settings.skipSmallEnough, curve.isJPEG, curve.sourceBytes <= settings.targetBytes,
           !resizeRequested, !settings.stripMetadata {
            return Estimate(bytes: curve.sourceBytes, outcome: .untouched, pixels: curve.pixels)
        }

        let ceiling = min(settings.targetBytes, curve.sourceBytes)
        if let hit = quality(in: curve, fitting: ceiling), hit.quality >= 0.50 {
            return Estimate(bytes: hit.bytes, outcome: .reencoded(quality: hit.quality),
                            pixels: curve.pixels)
        }
        if let hit = quality(in: curve, fitting: settings.targetBytes), hit.quality >= 0.30 {
            return Estimate(bytes: hit.bytes, outcome: .reencoded(quality: hit.quality),
                            pixels: curve.pixels)
        }
        // Below the quality floor the converter shrinks the picture and lands on the limit.
        return Estimate(bytes: settings.targetBytes, outcome: .resized, pixels: curve.pixels)
    }

    /// log(bytes) is near enough linear in quality between neighbouring samples.
    private static func quality(in curve: SizeCurve, fitting target: Int) -> (quality: Double, bytes: Int)? {
        let samples = curve.samples.sorted { $0.quality < $1.quality }
        guard let lowest = samples.first, let highest = samples.last else { return nil }
        if target >= highest.bytes { return (highest.quality, highest.bytes) }
        if target < lowest.bytes { return nil }

        for (low, high) in zip(samples, samples.dropFirst())
        where target >= low.bytes && target <= high.bytes {
            let span = log(Double(high.bytes)) - log(Double(low.bytes))
            guard span > 0 else { return (low.quality, low.bytes) }
            let position = (log(Double(target)) - log(Double(low.bytes))) / span
            return (low.quality + position * (high.quality - low.quality), target)
        }
        return (lowest.quality, lowest.bytes)
    }

    private static func encodedSize(_ image: CGImage, quality: Double) -> Int? {
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer.length
    }
}
