// Renders a noisy, photo-like image so JPEG compression has real work to do.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 4032, height = 3024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

var generator = SystemRandomNumberGenerator()
for _ in 0..<4000 {
    context.setFillColor(red: .random(in: 0...1, using: &generator),
                         green: .random(in: 0...1, using: &generator),
                         blue: .random(in: 0...1, using: &generator), alpha: 0.6)
    let size = Double.random(in: 20...600, using: &generator)
    context.fillEllipse(in: CGRect(x: .random(in: 0...Double(width), using: &generator),
                                   y: .random(in: 0...Double(height), using: &generator),
                                   width: size, height: size))
}
for _ in 0..<200_000 {
    context.setFillColor(gray: .random(in: 0...1, using: &generator), alpha: 0.5)
    context.fill(CGRect(x: .random(in: 0...Double(width), using: &generator),
                        y: .random(in: 0...Double(height), using: &generator), width: 3, height: 3))
}

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
// Orientation 6 = rotated 90°, so the pipeline gets an EXIF tag to carry over.
CGImageDestinationAddImage(destination, image, [
    kCGImageDestinationLossyCompressionQuality: 1.0,
    kCGImagePropertyOrientation: 6,
    kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "image-shrink test"],
] as CFDictionary)
CGImageDestinationFinalize(destination)
print(output.path)
