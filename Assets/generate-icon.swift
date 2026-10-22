import AppKit
import CoreGraphics

// A reproducible native vector icon, rendered at every standard macOS icon size.
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                           bytesPerRow: size * 4, space: space,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    let tile = CGPath(roundedRect: CGRect(x: 80, y: 80, width: 864, height: 864),
                      cornerWidth: 194, cornerHeight: 194, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 32, color: color(0x170A22, 0.28))
    context.addPath(tile); context.setFillColor(color(0x25183D)); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(tile); context.clip()
    let sky = CGGradient(colorsSpace: space,
                         colors: [color(0x201836), color(0x6C2853), color(0xD36B50)] as CFArray,
                         locations: [0, 0.65, 1])!
    context.drawLinearGradient(sky, start: CGPoint(x: 512, y: 944), end: CGPoint(x: 512, y: 80), options: [])
    let glow = CGGradient(colorsSpace: space,
                          colors: [color(0xFF9B4C, 0.72), color(0xFF5A40, 0)] as CFArray, locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 508), startRadius: 30,
                               endCenter: CGPoint(x: 512, y: 508), endRadius: 450, options: [])
    context.saveGState()
    context.addEllipse(in: CGRect(x: 272, y: 314, width: 480, height: 480)); context.clip()
    let sun = CGGradient(colorsSpace: space,
                         colors: [color(0xFFE7A0), color(0xFFB35B), color(0xFF6250)] as CFArray,
                         locations: [0, 0.55, 1])!
    context.drawLinearGradient(sun, start: CGPoint(x: 512, y: 794), end: CGPoint(x: 512, y: 314), options: [])
    context.restoreGState()
    // The horizon cuts the disc cleanly; short reflections retain the sunset silhouette at small sizes.
    context.setFillColor(color(0x34203C))
    context.fill(CGRect(x: 80, y: 80, width: 864, height: 380))
    for (index, width) in [CGFloat(420), 316, 210].enumerated() {
        let y = CGFloat(383 - index * 65)
        let reflection = CGPath(roundedRect: CGRect(x: 512 - width / 2, y: y, width: width, height: 23),
                               cornerWidth: 12, cornerHeight: 12, transform: nil)
        context.addPath(reflection); context.setFillColor(color(0xFFAD6A, CGFloat(0.85 - Double(index) * 0.18)))
        context.fillPath()
    }
    context.restoreGState()
    context.addPath(tile); context.setStrokeColor(color(0xFFFFFF, 0.13)); context.setLineWidth(2); context.strokePath()
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    let data = bitmap.representation(using: .png, properties: [:])!
    var names: [String] = []
    if [16, 32, 128, 256, 512].contains(size) { names.append("icon_\(size)x\(size).png") }
    if [32, 64, 256, 512, 1024].contains(size) { names.append("icon_\(size/2)x\(size/2)@2x.png") }
    for name in names { try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name)) }
}
