// Draws the app icon at every size the iconset needs. Vector-only, so no source art to keep.
// Shape and finish follow the macOS 26 icon style: an Apple-style squircle, a diagonal
// colour wash, and one specular highlight reading as glass.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// Apple's rounded-rect corners are a superellipse, not an arc — n≈5 matches the icon grid.
func squircle(in rect: CGRect, n: Double = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let steps = 720
    for step in 0...steps {
        let theta = 2 * Double.pi * Double(step) / Double(steps)
        let cosine = cos(theta), sine = sin(theta)
        let x = a * copysign(pow(abs(cosine), 2 / n), cosine)
        let y = b * copysign(pow(abs(sine), 2 / n), sine)
        let point = CGPoint(x: center.x + x, y: center.y + y)
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func rounded(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func draw(size: CGFloat) -> CGImage {
    let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                            bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    let inset = size * 0.08
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = squircle(in: plate)

    context.saveGState()
    context.addPath(shape)
    context.clip()

    let gradient = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(srgbRed: 0.35, green: 0.58, blue: 1.00, alpha: 1),
        CGColor(srgbRed: 0.47, green: 0.28, blue: 0.95, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size),
                               end: CGPoint(x: size, y: 0), options: [])

    // Specular highlight — the one cue that reads as glass at every size.
    let highlight = CGGradient(colorsSpace: sRGB, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.30),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(highlight,
                               startCenter: CGPoint(x: plate.minX + plate.width * 0.28,
                                                    y: plate.maxY - plate.height * 0.10),
                               startRadius: 0,
                               endCenter: CGPoint(x: plate.minX + plate.width * 0.30,
                                                  y: plate.maxY - plate.height * 0.12),
                               endRadius: plate.width * 0.75, options: [])
    context.restoreGState()

    // Photo frame with a mountain and a sun.
    let frame = CGRect(x: size * 0.235, y: size * 0.30, width: size * 0.53, height: size * 0.40)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.setLineWidth(size * 0.045)
    context.addPath(rounded(frame, radius: size * 0.06))
    context.strokePath()

    context.saveGState()
    context.addPath(rounded(frame.insetBy(dx: size * 0.022, dy: size * 0.022), radius: size * 0.04))
    context.clip()
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
    context.move(to: CGPoint(x: frame.minX, y: frame.minY + size * 0.03))
    context.addLine(to: CGPoint(x: frame.minX + frame.width * 0.38, y: frame.minY + frame.height * 0.62))
    context.addLine(to: CGPoint(x: frame.minX + frame.width * 0.72, y: frame.minY + size * 0.03))
    context.closePath()
    context.fillPath()
    context.fillEllipse(in: CGRect(x: frame.minX + frame.width * 0.66, y: frame.minY + frame.height * 0.62,
                                   width: size * 0.07, height: size * 0.07))
    context.restoreGState()

    // Badge with a down arrow: the picture gets smaller.
    let badgeSize = size * 0.30
    let badge = CGRect(x: size - inset - badgeSize * 1.18, y: inset + badgeSize * 0.16,
                       width: badgeSize, height: badgeSize)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.02,
                      color: CGColor(srgbRed: 0.10, green: 0.06, blue: 0.30, alpha: 0.35))
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fillEllipse(in: badge)
    context.restoreGState()

    context.setStrokeColor(CGColor(srgbRed: 0.42, green: 0.36, blue: 0.96, alpha: 1))
    context.setLineWidth(size * 0.038)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let centerX = badge.midX
    context.move(to: CGPoint(x: centerX, y: badge.midY + badgeSize * 0.24))
    context.addLine(to: CGPoint(x: centerX, y: badge.midY - badgeSize * 0.20))
    context.strokePath()
    context.move(to: CGPoint(x: centerX - badgeSize * 0.17, y: badge.midY - badgeSize * 0.02))
    context.addLine(to: CGPoint(x: centerX, y: badge.midY - badgeSize * 0.21))
    context.addLine(to: CGPoint(x: centerX + badgeSize * 0.17, y: badge.midY - badgeSize * 0.02))
    context.strokePath()

    // Glass rim.
    context.addPath(shape)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
    context.setLineWidth(max(1, size * 0.006))
    context.strokePath()

    return context.makeImage()!
}

func write(_ image: CGImage, named name: String) {
    let url = outputDirectory.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

for base in [16, 32, 128, 256, 512] {
    write(draw(size: CGFloat(base)), named: "icon_\(base)x\(base).png")
    write(draw(size: CGFloat(base * 2)), named: "icon_\(base)x\(base)@2x.png")
}
print(outputDirectory.path)
