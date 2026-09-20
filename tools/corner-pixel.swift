// Prints the colour a few pixels in from the top-left, for the alpha-flattening test.
import AppKit

let image = NSImage(contentsOfFile: CommandLine.arguments[1])!
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let colour = rep.colorAt(x: 2, y: 2)!
print(Int(colour.redComponent * 255), Int(colour.greenComponent * 255), Int(colour.blueComponent * 255))
