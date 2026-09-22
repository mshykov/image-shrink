// Fixtures for the cases a photo library eventually throws at the converter: a CMYK JPEG from
// a print workflow, a 16-bit TIFF from a scanner or a raw developer, and a panorama whose
// aspect ratio breaks naive resizing. Written in code so there is no binary art in the repo.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

/// Enough detail that the encoder cannot cheat: flat colour compresses to nothing and would
/// make every size assertion meaningless.
func paint(_ context: CGContext, width: Int, height: Int) {
    for row in 0..<60 {
        for column in 0..<60 {
            let x = CGFloat(column) * CGFloat(width) / 60
            let y = CGFloat(row) * CGFloat(height) / 60
            let hue = Double((row &* 7 &+ column &* 13) % 360) / 360
            context.setFillColor(NSColorLike(hue: hue))
            context.fillEllipse(in: CGRect(x: x, y: y,
                                           width: CGFloat(width) / 40,
                                           height: CGFloat(height) / 18))
        }
    }
}

/// A hue wheel without AppKit, so this stays a CoreGraphics-only tool.
func NSColorLike(hue: Double) -> CGColor {
    let sector = hue * 6
    let fraction = sector - sector.rounded(.down)
    let p = 0.15, q = 1 - 0.85 * fraction, t = 0.15 + 0.85 * fraction
    let rgb: (Double, Double, Double)
    switch Int(sector) % 6 {
    case 0: rgb = (1, t, p)
    case 1: rgb = (q, 1, p)
    case 2: rgb = (p, 1, t)
    case 3: rgb = (p, q, 1)
    case 4: rgb = (t, p, 1)
    default: rgb = (1, p, q)
    }
    return CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
}

func write(_ image: CGImage, to name: String, type: UTType, properties: CFDictionary? = nil) {
    let url = directory.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, type.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("could not create \(name)\n".utf8)); exit(1)
    }
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write(Data("could not write \(name)\n".utf8)); exit(1)
    }
    print(url.path)
}

// A CMYK JPEG — what comes back from a print shop, and a colour space JPEG encoders handle
// differently from RGB.
let cmykSize = 2400
if let cmyk = CGColorSpace(name: CGColorSpace.genericCMYK),
   let context = CGContext(data: nil, width: cmykSize, height: cmykSize, bitsPerComponent: 8,
                           bytesPerRow: 0, space: cmyk,
                           bitmapInfo: CGImageAlphaInfo.none.rawValue) {
    context.setFillColor(CGColor(colorSpace: cmyk, components: [0, 0, 0, 0.05])!)
    context.fill(CGRect(x: 0, y: 0, width: cmykSize, height: cmykSize))
    paint(context, width: cmykSize, height: cmykSize)
    if let image = context.makeImage() {
        write(image, to: "cmyk.jpg", type: .jpeg, properties:
              [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    }
}

// A 16-bit TIFF — scanners and raw developers produce these, and they are four times the bytes
// per pixel of anything else the app sees.
let deepSize = 1800
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
if let context = CGContext(data: nil, width: deepSize, height: deepSize, bitsPerComponent: 16,
                           bytesPerRow: 0, space: sRGB,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                               | CGBitmapInfo.byteOrder16Little.rawValue) {
    context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: deepSize, height: deepSize))
    paint(context, width: deepSize, height: deepSize)
    if let image = context.makeImage() {
        write(image, to: "deep.tiff", type: .tiff)
    }
}

// A grayscale JPEG — a scan, or a photo someone desaturated. It must stay grayscale: the
// format is understood everywhere, and turning it into RGB would triple the bytes for nothing.
if let gray = CGColorSpace(name: CGColorSpace.linearGray),
   let context = CGContext(data: nil, width: 1600, height: 1600, bitsPerComponent: 8,
                           bytesPerRow: 0, space: gray,
                           bitmapInfo: CGImageAlphaInfo.none.rawValue) {
    context.setFillColor(CGColor(gray: 0.15, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1600))
    for row in 0..<40 {
        for column in 0..<40 {
            context.setFillColor(CGColor(gray: Double((row &* 5 &+ column &* 11) % 100) / 100,
                                         alpha: 1))
            context.fillEllipse(in: CGRect(x: column * 40, y: row * 40, width: 34, height: 26))
        }
    }
    if let image = context.makeImage() {
        write(image, to: "gray.jpg", type: .jpeg, properties:
              [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    }
}

// A panorama: 8000 × 1400 is a shape that a square-ish downscale rule gets wrong.
if let context = CGContext(data: nil, width: 8000, height: 1400, bitsPerComponent: 8,
                           bytesPerRow: 0, space: sRGB,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.3, blue: 0.5, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8000, height: 1400))
    paint(context, width: 8000, height: 1400)
    if let image = context.makeImage() {
        write(image, to: "panorama.jpg", type: .jpeg, properties:
              [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    }
}
