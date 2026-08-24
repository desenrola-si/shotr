import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.iconset"
try? FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)

func drawIcon(side: CGFloat) -> Data? {
    guard let context = CGContext(data: nil, width: Int(side), height: Int(side),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    let inset = side * 0.06
    let body = rect.insetBy(dx: inset, dy: inset)

    let path = CGPath(roundedRect: body, cornerWidth: side * 0.22, cornerHeight: side * 0.22, transform: nil)
    context.saveGState()
    context.addPath(path)
    context.clip()
    let colors = [NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.19, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.09, alpha: 1).cgColor] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: [])
    }
    context.restoreGState()

    // Moldura de captura
    let frame = body.insetBy(dx: side * 0.20, dy: side * 0.20)
    let arm = frame.width * 0.32
    let lineWidth = side * 0.055
    context.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.62, blue: 1, alpha: 1).cgColor)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    let corners: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: frame.minX, y: frame.minY + arm), CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.minX + arm, y: frame.minY)),
        (CGPoint(x: frame.maxX - arm, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY + arm)),
        (CGPoint(x: frame.maxX, y: frame.maxY - arm), CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.maxX - arm, y: frame.maxY)),
        (CGPoint(x: frame.minX + arm, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY - arm))
    ]
    for (start, corner, end) in corners {
        context.beginPath()
        context.move(to: start)
        context.addLine(to: corner)
        context.addLine(to: end)
        context.strokePath()
    }

    // Ponto central
    context.setFillColor(NSColor.white.cgColor)
    let dot = side * 0.09
    context.fillEllipse(in: CGRect(x: frame.midX - dot / 2, y: frame.midY - dot / 2, width: dot, height: dot))

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

for size in sizes {
    if let data = drawIcon(side: CGFloat(size)) {
        try? data.write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size).png"))
    }
    if let data = drawIcon(side: CGFloat(size * 2)) {
        try? data.write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size)@2x.png"))
    }
}
print("iconset em \(output)")
