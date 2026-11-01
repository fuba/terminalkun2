import AppKit
import Foundation

// The icon source uses absolute M/L/C/Z paths only; reject unsupported commands.
final class SVGPaths: NSObject, XMLParserDelegate {
    var paths: [(String, String)] = []
    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if element == "path", let d = attributes["d"], let fill = attributes["fill"] { paths.append((d, fill)) }
    }
}
func makePath(_ source: String) -> CGPath {
    let spaced = source.replacingOccurrences(of: "([MLCZ])", with: " $1 ", options: .regularExpression)
    let tokens = spaced.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
    let path = CGMutablePath()
    var index = 0
    func number() -> CGFloat {
        guard index < tokens.count, let value = Double(tokens[index]) else { fatalError("Invalid SVG number") }
        index += 1; return value
    }
    while index < tokens.count {
        let command = tokens[index]; index += 1
        switch command {
        case "M": path.move(to: CGPoint(x: number(), y: number()))
        case "L": path.addLine(to: CGPoint(x: number(), y: number()))
        case "C":
            let first = CGPoint(x: number(), y: number()), second = CGPoint(x: number(), y: number()), end = CGPoint(x: number(), y: number())
            path.addCurve(to: end, control1: first, control2: second)
        case "Z": path.closeSubpath()
        default: fatalError("Unsupported SVG command: \(command)")
        }
    }
    return path
}
guard CommandLine.arguments.count == 3 else { fatalError("Usage: make-icon.swift input.svg output.iconset") }
let parser = XMLParser(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))!
let delegate = SVGPaths(); parser.delegate = delegate
guard parser.parse(), !delegate.paths.isEmpty else { fatalError("Invalid SVG") }
let output = URL(fileURLWithPath: CommandLine.arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [1024] {
    for scale in [1] {
        let pixels = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        let context = graphics.cgContext
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: CGFloat(pixels) / 1024, y: -CGFloat(pixels) / 1024)
        for (source, hex) in delegate.paths {
            let value = UInt32(hex.dropFirst(), radix: 16)!
            context.setFillColor(CGColor(srgbRed: CGFloat(value >> 16 & 255) / 255, green: CGFloat(value >> 8 & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1))
            context.addPath(makePath(source)); context.fillPath()
        }
        let name = "AppIcon.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
