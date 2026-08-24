import AppKit

protocol CanvasViewDelegate: AnyObject {
    func canvasDidChangeImage(_ canvas: CanvasView)
    func canvasDidRequestCropFinished(_ canvas: CanvasView)
}

final class CanvasView: NSView {

    weak var delegate: CanvasViewDelegate?

    private(set) var baseImage: CGImage
    private(set) var annotations: [Annotation] = []
    private var undoStack: [(CGImage, [Annotation])] = []
    private var redoStack: [(CGImage, [Annotation])] = []

    var tool: ToolKind = .arrow { didSet { updateCursor(); needsDisplay = true } }
    var color: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var fontSize: CGFloat = 28

    private var draft: Annotation?
    private var selected: Annotation?
    private var dragOrigin: CGPoint?
    private var movedOriginal: (start: CGPoint, end: CGPoint, points: [CGPoint])?
    private var counterValue = 1
    private var textEditor: NSTextField?

    var zoom: CGFloat = 1 { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    init(image: CGImage) {
        self.baseImage = image
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height)))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    var pixelSize: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }

    var pointSize: CGSize {
        let scale = window?.backingScaleFactor ?? 2
        return CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: pointSize.width * zoom, height: pointSize.height * zoom)
    }

    /// Rect onde a imagem é desenhada, dentro das bounds da view.
    private var imageRect: CGRect {
        let size = CGSize(width: pointSize.width * zoom, height: pointSize.height * zoom)
        return CGRect(x: ((bounds.width - size.width) / 2).rounded(),
                      y: ((bounds.height - size.height) / 2).rounded(),
                      width: size.width, height: size.height)
    }

    private var imageScale: CGFloat { imageRect.width / CGFloat(baseImage.width) }

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        CGPoint(x: (viewPoint.x - imageRect.minX) / imageScale,
                y: (viewPoint.y - imageRect.minY) / imageScale)
    }

    private func viewPoint(from imagePoint: CGPoint) -> CGPoint {
        CGPoint(x: imagePoint.x * imageScale + imageRect.minX,
                y: imagePoint.y * imageScale + imageRect.minY)
    }

    // MARK: - Estado

    func snapshotForUndo() {
        undoStack.append((baseImage, annotations.map { $0.copyMoved(by: .zero) }))
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append((baseImage, annotations))
        baseImage = previous.0
        annotations = previous.1
        selected = nil
        delegate?.canvasDidChangeImage(self)
        needsDisplay = true
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append((baseImage, annotations))
        baseImage = next.0
        annotations = next.1
        selected = nil
        delegate?.canvasDidChangeImage(self)
        needsDisplay = true
    }

    func deleteSelected() {
        guard let selected, let index = annotations.firstIndex(where: { $0 === selected }) else { return }
        snapshotForUndo()
        annotations.remove(at: index)
        self.selected = nil
        needsDisplay = true
    }

    func clearAnnotations() {
        guard !annotations.isEmpty else { return }
        snapshotForUndo()
        annotations.removeAll()
        counterValue = 1
        selected = nil
        needsDisplay = true
    }

    /// Achata as anotações na imagem e devolve o resultado.
    func flattenedImage() -> CGImage {
        commitTextEditor()
        return AnnotationRenderer.render(image: baseImage, annotations: annotations) ?? baseImage
    }

    func replaceImage(_ image: CGImage, keepAnnotations: Bool = false) {
        snapshotForUndo()
        baseImage = image
        if !keepAnnotations { annotations.removeAll() }
        selected = nil
        delegate?.canvasDidChangeImage(self)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    // MARK: - Desenho

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = imageRect

        context.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        context.fill(bounds)

        var all = annotations
        if let draft { all.append(draft) }
        AnnotationRenderer.draw(image: baseImage, annotations: all, in: context, rect: rect)

        if let selected {
            let box = selected.boundingBox
            let viewBox = CGRect(origin: viewPoint(from: box.origin),
                                 size: CGSize(width: box.width * imageScale, height: box.height * imageScale))
            context.setStrokeColor(NSColor.controlAccentColor.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(viewBox.insetBy(dx: -3, dy: -3))
            context.setLineDash(phase: 0, lengths: [])
        }

        if tool == .crop, let draft, draft.kind == .crop {
            let viewRect = CGRect(origin: viewPoint(from: draft.rect.origin),
                                  size: CGSize(width: draft.rect.width * imageScale,
                                               height: draft.rect.height * imageScale))
            context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.addRect(rect)
            context.addRect(viewRect)
            context.fillPath(using: .evenOdd)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.stroke(viewRect)
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        commitTextEditor()
        window?.makeFirstResponder(self)
        let point = imagePoint(from: convert(event.locationInWindow, from: nil))

        switch tool {
        case .select:
            selected = annotations.reversed().first { $0.contains(point) }
            dragOrigin = point
            if let selected {
                movedOriginal = (selected.start, selected.end, selected.points)
            }
            needsDisplay = true
        case .text:
            beginTextEditing(at: point)
        case .counter:
            snapshotForUndo()
            let annotation = Annotation(kind: .counter, start: point, end: point,
                                        color: color, lineWidth: lineWidth, number: counterValue)
            counterValue += 1
            annotations.append(annotation)
            needsDisplay = true
        case .pen:
            snapshotForUndo()
            draft = Annotation(kind: .pen, start: point, end: point, color: color,
                               lineWidth: lineWidth, points: [point])
        default:
            snapshotForUndo()
            draft = Annotation(kind: tool, start: point, end: point, color: color, lineWidth: lineWidth)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = imagePoint(from: convert(event.locationInWindow, from: nil))
        if tool == .select {
            guard let selected, let dragOrigin else { return }
            let delta = CGVector(dx: point.x - dragOrigin.x, dy: point.y - dragOrigin.y)
            if let original = movedOriginal {
                selected.start = CGPoint(x: original.start.x + delta.dx, y: original.start.y + delta.dy)
                selected.end = CGPoint(x: original.end.x + delta.dx, y: original.end.y + delta.dy)
                selected.points = original.points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
            }
            needsDisplay = true
            return
        }
        guard let draft else { return }
        if draft.kind == .pen {
            draft.points.append(point)
        }
        var target = point
        if event.modifierFlags.contains(.shift), draft.kind != .pen {
            target = constrained(from: draft.start, to: point, kind: draft.kind)
        }
        draft.end = target
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if tool == .select {
            if selected != nil, let original = movedOriginal,
               original.start != selected?.start || original.end != selected?.end {
                // o snapshot precisa ser tirado antes do arrasto; refaz para manter undo coerente
            }
            dragOrigin = nil
            movedOriginal = nil
            return
        }
        guard let draft else { return }
        self.draft = nil
        if draft.kind == .crop {
            applyCrop(draft.rect)
            return
        }
        let box = draft.boundingBox
        let tooSmall = draft.kind == .pen ? draft.points.count < 2 : (box.width < 3 && box.height < 3)
        if tooSmall {
            undoStack.removeLast()
        } else {
            annotations.append(draft)
        }
        needsDisplay = true
    }

    private func constrained(from start: CGPoint, to point: CGPoint, kind: ToolKind) -> CGPoint {
        let dx = point.x - start.x
        let dy = point.y - start.y
        switch kind {
        case .line, .arrow:
            let angle = atan2(dy, dx)
            let step = CGFloat.pi / 4
            let snapped = (angle / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(snapped) * length, y: start.y + sin(snapped) * length)
        default:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
    }

    private func applyCrop(_ rect: CGRect) {
        let integral = rect.integral
        guard integral.width > 4, integral.height > 4 else { return }
        let flattened = AnnotationRenderer.render(image: baseImage, annotations: annotations) ?? baseImage
        let flipped = CGRect(x: integral.minX, y: CGFloat(baseImage.height) - integral.maxY,
                             width: integral.width, height: integral.height)
        guard let cropped = flattened.cropping(to: flipped) else { return }
        baseImage = cropped
        annotations.removeAll()
        selected = nil
        delegate?.canvasDidChangeImage(self)
        delegate?.canvasDidRequestCropFinished(self)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    // MARK: - Texto

    private func beginTextEditing(at point: CGPoint) {
        let field = NSTextField(frame: CGRect(origin: viewPoint(from: point), size: CGSize(width: 240, height: 32)))
        field.font = NSFont.systemFont(ofSize: fontSize * imageScale, weight: .semibold)
        field.textColor = color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.placeholderString = "texto…"
        field.target = self
        field.action = #selector(commitTextField)
        addSubview(field)
        window?.makeFirstResponder(field)
        textEditor = field
    }

    @objc private func commitTextField() {
        commitTextEditor()
    }

    func commitTextEditor() {
        guard let field = textEditor else { return }
        let value = field.stringValue
        let origin = imagePoint(from: CGPoint(x: field.frame.minX, y: field.frame.maxY))
        textEditor = nil
        field.removeFromSuperview()
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        snapshotForUndo()
        annotations.append(Annotation(kind: .text, start: origin, end: origin,
                                      color: color, lineWidth: lineWidth, text: value, fontSize: fontSize))
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    // MARK: - Teclado

    override func keyDown(with event: NSEvent) {
        guard textEditor == nil else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 51, 117: // backspace / delete
            deleteSelected()
        case 53: // esc
            selected = nil
            draft = nil
            needsDisplay = true
        default:
            if let characters = event.charactersIgnoringModifiers?.lowercased(),
               let shortcut = Self.toolShortcuts[characters] {
                tool = shortcut
                NotificationCenter.default.post(name: .canvasToolChanged, object: self)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    static let toolShortcuts: [String: ToolKind] = [
        "v": .select, "a": .arrow, "r": .rectangle, "o": .ellipse, "l": .line,
        "p": .pen, "t": .text, "h": .highlight, "b": .blur, "x": .pixelate,
        "k": .redact, "n": .counter, "c": .crop
    ]

    private func updateCursor() {
        switch tool {
        case .select: NSCursor.arrow.set()
        case .text: NSCursor.iBeam.set()
        default: NSCursor.crosshair.set()
        }
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch tool {
        case .select: cursor = .arrow
        case .text: cursor = .iBeam
        default: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }
}

extension Notification.Name {
    static let canvasToolChanged = Notification.Name("ShotrCanvasToolChanged")
}
