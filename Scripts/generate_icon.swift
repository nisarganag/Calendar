import AppKit

func renderIcon(_ px: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(px), pixelsHigh: Int(px),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!

    // Background rounded rect with gradient
    let inset = px * 0.09
    let rect = CGRect(x: inset, y: inset, width: px - inset * 2, height: px - inset * 2)
    let radius = (px - inset * 2) * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    ctx.cgContext.saveGState()
    ctx.cgContext.addPath(path.cgPath)
    ctx.cgContext.clip()
    let colors = [
        CGColor(red: 0.38, green: 0.36, blue: 0.98, alpha: 1),
        CGColor(red: 0.20, green: 0.60, blue: 1.00, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    let start = CGPoint(x: rect.minX, y: rect.maxY)
    let end = CGPoint(x: rect.maxX, y: rect.minY)
    ctx.cgContext.drawLinearGradient(gradient, start: start, end: end, options: [])
    ctx.cgContext.restoreGState()

    // Top white header strip
    let stripHeight = rect.height * 0.24
    let stripRect = CGRect(x: rect.minX, y: rect.maxY - stripHeight, width: rect.width, height: stripHeight)
    let stripPath = NSBezierPath(roundedRect: stripRect, xRadius: radius, yRadius: radius)
    stripPath.append(NSBezierPath(rect: CGRect(x: rect.minX, y: stripRect.minY, width: rect.width, height: stripHeight)))
    NSColor.white.withAlphaComponent(0.22).setFill()
    stripPath.fill()

    // Two binder rings
    for fx in [0.30, 0.70] {
        let ringX = rect.minX + rect.width * CGFloat(fx)
        let ringY = rect.maxY - stripHeight
        let ringOuter = NSBezierPath(
            roundedRect: CGRect(x: ringX - px*0.028, y: ringY - px*0.010, width: px*0.056, height: px*0.075),
            xRadius: px*0.028, yRadius: px*0.028
        )
        NSColor.white.withAlphaComponent(0.95).setFill()
        ringOuter.fill()
    }

    // Day number "22"
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: rect.height * 0.46, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ]
    let textRect = CGRect(x: rect.minX, y: rect.minY + rect.height * 0.10, width: rect.width, height: rect.height * 0.62)
    ("22" as NSString).draw(in: textRect, withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fileManager = FileManager.default
let outDir = "build/AppIcon.iconset"
try? fileManager.removeItem(atPath: outDir)
try! fileManager.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for size in sizes {
    let rep = renderIcon(CGFloat(size.px))
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(size.name)"))
}
print("iconset written to \(outDir)")
