// Draws the 1200×630 card that Reddit, Hacker News, Slack and X show when the link is posted.
// Takes the app icon PNG the build already produces, so there is one piece of source art.
import AppKit

let iconPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let size = NSSize(width: 1200, height: 630)

let image = NSImage(size: size)
image.lockFocus()

let context = NSGraphicsContext.current!.cgContext
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let background = CGGradient(colorsSpace: sRGB, colors: [
    CGColor(srgbRed: 0.09, green: 0.10, blue: 0.13, alpha: 1),
    CGColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1),
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: size.height),
                           end: CGPoint(x: size.width, y: 0), options: [])

// A wash of the icon's own blue, so the card is not a flat rectangle.
let wash = CGGradient(colorsSpace: sRGB, colors: [
    CGColor(srgbRed: 0.35, green: 0.58, blue: 1.0, alpha: 0.22),
    CGColor(srgbRed: 0.35, green: 0.58, blue: 1.0, alpha: 0.0),
] as CFArray, locations: [0, 1])!
context.drawRadialGradient(wash, startCenter: CGPoint(x: 150, y: 520), startRadius: 0,
                           endCenter: CGPoint(x: 150, y: 520), endRadius: 620, options: [])

if let icon = NSImage(contentsOfFile: iconPath) {
    icon.draw(in: NSRect(x: 96, y: 330, width: 200, height: 200))
}

func write(_ text: String, x: CGFloat, y: CGFloat, size fontSize: CGFloat,
           weight: NSFont.Weight, alpha: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
    ]
    NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: x, y: y))
}

write("Image Shrink", x: 96, y: 236, size: 76, weight: .semibold, alpha: 1)
write("Press \u{2303}\u{2318}J on a Finder selection — a JPEG under the size", x: 96, y: 170,
      size: 36, weight: .regular, alpha: 0.78)
write("limit you pick. Nothing leaves your Mac.", x: 96, y: 120, size: 36, weight: .regular, alpha: 0.78)
write("macOS 13+  ·  Apple silicon and Intel  ·  free and open source", x: 96, y: 56,
      size: 24, weight: .medium, alpha: 0.5)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not render the card\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print(outputPath)
