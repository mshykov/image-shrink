import AppKit
import CoreGraphics
import ImageIO

/// Small previews for the file list. Seeing the photos is half the reason to open the window.
enum Thumbnail {
    /// Wrapper so the decoded image can cross actor boundaries without a Sendable warning.
    private struct Box: @unchecked Sendable {
        let image: NSImage?
    }

    static func load(_ url: URL, size: Int = 96) async -> NSImage? {
        await Task.detached(priority: .utility) { Box(image: make(url, size: size)) }.value.image
    }

    private static func make(_ url: URL, size: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Upright, unlike the conversion path: this one is for display only.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceShouldCache: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
