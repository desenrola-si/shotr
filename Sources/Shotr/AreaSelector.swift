import AppKit

struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
}

enum SelectorMode {
    case area
    case color
}

struct SelectionResult {
    let image: CGImage
    let globalRect: CGRect
}

/// Congela as telas e deixa o usuário arrastar um retângulo por cima da imagem congelada.
final class AreaSelector {
    static let shared = AreaSelector()

    private var windows: [OverlayWindow] = []
    private var completion: ((SelectionResult?) -> Void)?
    private var frozen: [FrozenScreen] = []
    private var windowRects: [(rect: CGRect, title: String)] = []
    private var isRunning = false
    private var colorCompletion: ((NSColor?) -> Void)?
    fileprivate var mode: SelectorMode = .area

    private init() {}

    var isActive: Bool { isRunning }

    func select(highlightWindows: Bool = true, completion: @escaping (SelectionResult?) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        mode = .area
        self.completion = completion

        Task { @MainActor in
            var shots: [FrozenScreen] = []
            for screen in NSScreen.screens {
                if let image = try? await ScreenCapturer.capture(screen: screen) {
                    shots.append(FrozenScreen(screen: screen, image: image))
                }
            }
            guard !shots.isEmpty else {
                self.finish(nil)
                return
            }
            self.frozen = shots
            self.windowRects = highlightWindows ? await Self.loadWindowRects() : []
            self.presentOverlays()
        }
    }

    func pickColor(completion: @escaping (NSColor?) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        mode = .color
        colorCompletion = completion
        Task { @MainActor in
            var shots: [FrozenScreen] = []
            for screen in NSScreen.screens {
                if let image = try? await ScreenCapturer.capture(screen: screen) {
                    shots.append(FrozenScreen(screen: screen, image: image))
                }
            }
            guard !shots.isEmpty else { return self.finish(nil) }
            self.frozen = shots
            self.windowRects = []
            self.presentOverlays()
        }
    }

    fileprivate func complete(color: NSColor) {
        let callback = colorCompletion
        colorCompletion = nil
        finish(nil)
        callback?(color)
    }

    private static func loadWindowRects() async -> [(rect: CGRect, title: String)] {
        guard let windows = try? await ScreenCapturer.onScreenWindows() else { return [] }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return windows.map { window in
            let frame = window.frame
            let rect = CGRect(x: frame.origin.x,
                              y: primaryMaxY - frame.origin.y - frame.height,
                              width: frame.width, height: frame.height)
            return (rect, window.title ?? window.owningApplication?.applicationName ?? "")
        }
    }

    private func presentOverlays() {
        NSApp.activate(ignoringOtherApps: true)
        for shot in frozen {
            let window = OverlayWindow(frozen: shot, windowRects: windowRects, selector: self)
            window.orderFrontRegardless()
            windows.append(window)
        }
        windows.first?.makeKey()
        NSCursor.crosshair.set()
    }

    fileprivate func complete(globalRect: CGRect) {
        guard globalRect.width >= 1, globalRect.height >= 1,
              let shot = frozen.first(where: { $0.screen.frame.intersects(globalRect) }) else {
            finish(nil)
            return
        }
        let pixelRect = shot.screen.pixelRect(fromGlobal: globalRect)
        guard let cropped = shot.image.cropping(to: pixelRect) else {
            finish(nil)
            return
        }
        Preferences.shared.lastArea = globalRect
        finish(SelectionResult(image: cropped, globalRect: globalRect))
    }

    fileprivate func cancel() {
        finish(nil)
    }

    private func finish(_ result: SelectionResult?) {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        frozen.removeAll()
        windowRects.removeAll()
        NSCursor.arrow.set()
        isRunning = false
        let callback = completion
        completion = nil
        let pendingColor = colorCompletion
        colorCompletion = nil
        callback?(result)
        pendingColor?(nil)
    }
}

// MARK: - Janela e view do overlay

private final class OverlayWindow: NSWindow {
    init(frozen: FrozenScreen, windowRects: [(rect: CGRect, title: String)], selector: AreaSelector) {
        super.init(contentRect: frozen.screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        level = .init(Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        hasShadow = false
        setFrame(frozen.screen.frame, display: true)
        contentView = OverlayView(frozen: frozen, windowRects: windowRects, selector: selector)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class OverlayView: NSView {
    private let frozen: FrozenScreen
    private let windowRects: [(rect: CGRect, title: String)]
    private unowned let selector: AreaSelector

    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?
    private var mouseLocation: CGPoint = .zero
    private var isDragging = false
    private var trackingArea: NSTrackingArea?

    init(frozen: FrozenScreen, windowRects: [(rect: CGRect, title: String)], selector: AreaSelector) {
        self.frozen = frozen
        self.windowRects = windowRects
        self.selector = selector
        super.init(frame: CGRect(origin: .zero, size: frozen.screen.frame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // Coordenadas locais → globais
    private func global(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + frozen.screen.frame.minX, y: point.y + frozen.screen.frame.minY)
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -frozen.screen.frame.minX, dy: -frozen.screen.frame.minY)
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else { return nil }
        return CGRect(x: min(startPoint.x, currentPoint.x),
                      y: min(startPoint.y, currentPoint.y),
                      width: abs(currentPoint.x - startPoint.x),
                      height: abs(currentPoint.y - startPoint.y))
    }

    private var hoveredWindowRect: CGRect? {
        guard !isDragging else { return nil }
        let point = global(mouseLocation)
        let candidates = windowRects.filter { $0.rect.contains(point) }
        return candidates.min { $0.rect.area < $1.rect.area }.map { local($0.rect) }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard selector.mode == .area else { return }
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        mouseLocation = currentPoint ?? .zero
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouseLocation = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        currentPoint = convert(event.locationInWindow, from: nil)
        if selector.mode == .color {
            let scale = frozen.screen.backingScaleFactor
            let point = currentPoint ?? mouseLocation
            let pixel = CGPoint(x: point.x * scale, y: (bounds.height - point.y) * scale)
            selector.complete(color: frozen.image.color(atPixel: pixel) ?? .black)
            return
        }
        guard let rect = selectionRect else { return selector.cancel() }
        if rect.width < 4 || rect.height < 4 {
            if let hovered = hoveredWindowRect ?? windowRects
                .filter({ $0.rect.contains(global(mouseLocation)) })
                .min(by: { $0.rect.area < $1.rect.area })?.rect.offsetBy(dx: -frozen.screen.frame.minX,
                                                                        dy: -frozen.screen.frame.minY) {
                selector.complete(globalRect: hovered.offsetBy(dx: frozen.screen.frame.minX,
                                                               dy: frozen.screen.frame.minY))
                return
            }
            selector.cancel()
            return
        }
        selector.complete(globalRect: rect.offsetBy(dx: frozen.screen.frame.minX, dy: frozen.screen.frame.minY))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            selector.cancel()
        case 36, 76: // Enter
            if let rect = selectionRect, rect.width > 4, rect.height > 4 {
                selector.complete(globalRect: rect.offsetBy(dx: frozen.screen.frame.minX,
                                                            dy: frozen.screen.frame.minY))
            } else {
                selector.cancel()
            }
        case 49: // Espaço — captura a tela inteira
            selector.complete(globalRect: frozen.screen.frame)
        default:
            break
        }
    }

    // MARK: Desenho

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(frozen.image, in: bounds)

        let highlight = selectionRect ?? hoveredWindowRect

        context.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        if let highlight {
            context.addRect(bounds)
            context.addRect(highlight)
            context.fillPath(using: .evenOdd)
        } else {
            context.fill(bounds)
        }

        if let highlight {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.stroke(highlight.insetBy(dx: -0.5, dy: -0.5))
            drawSizeLabel(for: highlight, in: context)
        }

        if !isDragging {
            drawCrosshair(in: context)
            drawMagnifier(in: context)
        }
        drawHint(in: context)
    }

    private func drawCrosshair(in context: CGContext) {
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(1)
        context.beginPath()
        context.move(to: CGPoint(x: mouseLocation.x + 0.5, y: 0))
        context.addLine(to: CGPoint(x: mouseLocation.x + 0.5, y: bounds.height))
        context.move(to: CGPoint(x: 0, y: mouseLocation.y + 0.5))
        context.addLine(to: CGPoint(x: bounds.width, y: mouseLocation.y + 0.5))
        context.strokePath()
    }

    private func drawSizeLabel(for rect: CGRect, in context: CGContext) {
        let scale = frozen.screen.backingScaleFactor
        let text = "\(Int(rect.width * scale)) × \(Int(rect.height * scale))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        var origin = CGPoint(x: rect.minX, y: rect.maxY + 8)
        if origin.y + size.height + 8 > bounds.height { origin.y = rect.minY - size.height - 14 }
        let box = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 6)
        context.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        context.fill(box)
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
    }

    private func drawMagnifier(in context: CGContext) {
        let zoom: CGFloat = 8
        let sampleSide: CGFloat = 15 // pixels amostrados
        let scale = frozen.screen.backingScaleFactor
        let pixelPoint = CGPoint(x: mouseLocation.x * scale, y: (bounds.height - mouseLocation.y) * scale)
        let sampleRect = CGRect(x: pixelPoint.x - sampleSide / 2, y: pixelPoint.y - sampleSide / 2,
                                width: sampleSide, height: sampleSide)
        guard let sample = frozen.image.cropping(to: sampleRect) else { return }

        let side = sampleSide * zoom
        var origin = CGPoint(x: mouseLocation.x + 18, y: mouseLocation.y - side - 18)
        if origin.x + side > bounds.width - 8 { origin.x = mouseLocation.x - side - 18 }
        if origin.y < 8 { origin.y = mouseLocation.y + 18 }
        let frame = CGRect(origin: origin, size: CGSize(width: side, height: side))

        context.saveGState()
        context.interpolationQuality = .none
        context.draw(sample, in: frame)
        context.restoreGState()

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1)
        context.stroke(frame)
        let center = CGRect(x: frame.midX - zoom / 2, y: frame.midY - zoom / 2, width: zoom, height: zoom)
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.stroke(center)

        if let color = frozen.image.color(atPixel: pixelPoint) {
            let hex = color.hexString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let box = CGRect(x: frame.minX, y: frame.minY - 20, width: frame.width, height: 18)
            context.setFillColor(NSColor.black.withAlphaComponent(0.8).cgColor)
            context.fill(box)
            (hex as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
        }
    }

    private func drawHint(in context: CGContext) {
        guard selectionRect == nil else { return }
        let text = selector.mode == .color
            ? "Clique para copiar a cor do pixel · Esc cancela"
            : "Arraste para selecionar · clique numa janela · Espaço = tela inteira · Esc cancela"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9)
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(x: (bounds.width - size.width) / 2 - 14,
                         y: bounds.height * 0.08,
                         width: size.width + 28, height: size.height + 14)
        let path = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.7).setFill()
        path.fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 14, y: box.minY + 7), withAttributes: attributes)
    }
}

extension CGRect {
    var area: CGFloat { width * height }
}

extension CGImage {
    func color(atPixel point: CGPoint) -> NSColor? {
        guard let cropped = cropping(to: CGRect(x: point.x, y: point.y, width: 1, height: 1)) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cropped)
        return rep.colorAt(x: 0, y: 0)
    }
}

extension NSColor {
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
