// A PNG with a transparent background, for the test that JPEG gets white instead.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let context = CGContext(data: nil, width: 1200, height: 900, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.clear(CGRect(x: 0, y: 0, width: 1200, height: 900))
context.setFillColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1)
context.fillEllipse(in: CGRect(x: 300, y: 200, width: 600, height: 500))

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
CGImageDestinationFinalize(destination)
