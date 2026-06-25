import AppKit

/// A transparent full-screen overlay that lets the user drag a selection
/// rectangle, like the macOS screenshot tool. Returns the rect in the main
/// display's coordinate space (points, **top-left** origin) — the convention
/// `SCStreamConfiguration.sourceRect` / `ScreenRecorder` expect — or nil if the
/// user pressed Escape / made a zero-size selection.
@MainActor
enum RegionSelectOverlay {
    static func selectRegion() async -> CGRect? {
        await withCheckedContinuation { (cont: CheckedContinuation<CGRect?, Never>) in
            guard let screen = NSScreen.main else { cont.resume(returning: nil); return }
            let window = SelectionWindow(screen: screen) { rect in
                cont.resume(returning: rect)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

/// Borderless, transparent, screen-sized window hosting the drag-select view.
private final class SelectionWindow: NSWindow {
    private var onFinish: ((CGRect?) -> Void)?
    private var didFinish = false

    init(screen: NSScreen, onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.18)
        level = .screenSaver
        ignoresMouseEvents = false
        hasShadow = false
        let view = SelectionView(screen: screen) { [weak self] rect in
            self?.finish(rect)
        }
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }

    func finish(_ rect: CGRect?) {
        guard !didFinish else { return }
        didFinish = true
        let cb = onFinish
        onFinish = nil
        orderOut(nil)
        cb?(rect)
    }
}

/// The drag-select content view. Coordinates are flipped (top-left origin) so the
/// drawn rect maps directly to ScreenCaptureKit's `sourceRect`.
private final class SelectionView: NSView {
    private let screen: NSScreen
    private let onFinish: (CGRect?) -> Void
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero

    init(screen: NSScreen, onFinish: @escaping (CGRect?) -> Void) {
        self.screen = screen
        self.onFinish = onFinish
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(x: min(start.x, p.x), y: min(start.y, p.y),
                             width: abs(p.x - start.x), height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { startPoint = nil }
        guard currentRect.width >= 8, currentRect.height >= 8 else { onFinish(nil); return }
        onFinish(currentRect)  // already top-left origin (view is flipped)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } // Escape
    }

    override func draw(_ dirtyRect: NSRect) {
        guard currentRect != .zero else { return }
        NSColor.white.withAlphaComponent(0.08).setFill()
        currentRect.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: currentRect)
        path.lineWidth = 2
        path.stroke()
    }
}
