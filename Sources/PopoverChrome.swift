import Cocoa

// MARK: - Popover chrome
//
// A popover ships with its own blurred backing. Left in place, every glass card
// inside the panel samples *that* blur instead of the desktop, and the material
// collapses into flat grey — which is exactly what "not real Liquid Glass"
// looks like. Stripping the backing leaves one glass layer, the cards, sitting
// directly over the wallpaper, which is how system Liquid Glass surfaces read.

enum PopoverChrome {

    /// Removes the popover's own opaque backing so the panel's glass refracts
    /// the desktop directly. Safe to call repeatedly; a no-op if the private
    /// view shape ever changes.
    static func makeTransparent(_ popover: NSPopover) {
        guard let window = popover.contentViewController?.view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        guard let frame = window.contentView?.superview else { return }
        frame.wantsLayer = true
        frame.layer?.backgroundColor = NSColor.clear.cgColor

        // On macOS 26 the backing is an NSGlassView; on earlier systems an
        // NSVisualEffectView. Neutralise whichever is present.
        for view in descendants(of: frame) {
            if let effect = view as? NSVisualEffectView {
                effect.state = .inactive
                effect.isHidden = true
            } else if String(describing: type(of: view)).contains("GlassView") {
                view.isHidden = true
            }
        }
    }

    static func dump(_ popover: NSPopover) -> String {
        guard let window = popover.contentViewController?.view.window,
              let frame = window.contentView?.superview else { return "<no window>" }
        var out = ""
        func walk(_ v: NSView, _ depth: Int) {
            out += String(repeating: "  ", count: depth)
                + "\(type(of: v)) frame=\(v.frame) layer=\(v.layer.map { "\($0.backgroundColor.map(String.init(describing:)) ?? "nil")" } ?? "none")\n"
            v.subviews.forEach { walk($0, depth + 1) }
        }
        walk(frame, 0)
        return out
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
