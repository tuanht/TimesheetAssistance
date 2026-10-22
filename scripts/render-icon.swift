import AppKit

// Renders Design/AppIcon.svg into the AppIcon.appiconset PNGs and Contents.json.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let svgURL = root.appendingPathComponent("Design/AppIcon.svg")
let outDir = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

guard let svg = NSImage(contentsOf: svgURL), svg.isValid else {
    FileHandle.standardError.write(Data("cannot load \(svgURL.path)\n".utf8))
    exit(1)
}
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func writePNG(pixels: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { throw CocoaError(.fileWriteUnknown) }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    svg.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
             from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try writePNG(pixels: base * scale, to: outDir.appendingPathComponent(name))
        images.append([
            "idiom": "mac", "size": "\(base)x\(base)",
            "scale": "\(scale)x", "filename": name,
        ])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(
    withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("wrote \(images.count) icons to \(outDir.path)")
