import AppKit

enum StatusBarIcon {
    private static var cache: [Int: NSImage] = [:]

    static func image(dayNumber: Int) -> NSImage {
        if let cached = cache[dayNumber] { return cached }
        let pointSize = NSSize(width: 20, height: 18)
        let img = NSImage(size: pointSize)
        for scale in [1, 2] {
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(pointSize.width) * scale,
                pixelsHigh: Int(pointSize.height) * scale,
                bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ) else { continue }
            rep.size = pointSize
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            drawGlyph(size: pointSize, day: dayNumber)
            NSGraphicsContext.restoreGraphicsState()
            img.addRepresentation(rep)
        }
        img.isTemplate = true
        cache[dayNumber] = img
        return img
    }

    /// Filled rounded-square badge with the day number knocked out,
    /// matching the reference artwork (solid squircle, transparent digits).
    private static func drawGlyph(size: NSSize, day: Int) {
        guard let ctx = NSGraphicsContext.current else { return }
        let rect = NSRect(origin: .zero, size: size)

        let badgeRect = rect.insetBy(dx: 1.25, dy: 1.25)
        let badge = NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5)
        NSColor.black.setFill()
        badge.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.8, weight: .bold),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ]
        let text = "\(day)" as NSString
        let textSize = text.size(withAttributes: attrs)

        ctx.compositingOperation = .destinationOut
        text.draw(
            at: CGPoint(x: rect.midX - textSize.width / 2,
                        y: rect.midY - textSize.height / 2 + 0.3),
            withAttributes: attrs
        )
        ctx.compositingOperation = .sourceOver
    }
}
