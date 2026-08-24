import AppKit

/// Campo que grava uma combinação de teclas, no estilo dos campos de atalho do sistema.
final class KeyRecorderField: NSView {

    var onChange: ((HotKey?) -> Void)?

    private(set) var hotKey: HotKey?
    private var isRecording = false {
        didSet { needsDisplay = true }
    }

    private let clearButton = NSButton(title: "", target: nil, action: nil)
    private var monitor: Any?

    init(hotKey: HotKey?) {
        self.hotKey = hotKey
        super.init(frame: CGRect(x: 0, y: 0, width: 150, height: 24))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 150).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        buildClearButton()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func buildClearButton() {
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Limpar")
        clearButton.isBordered = false
        clearButton.target = self
        clearButton.action = #selector(clear)
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)
        NSLayoutConstraint.activate([
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    func update(hotKey: HotKey?) {
        self.hotKey = hotKey
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            guard event.type == .keyDown else { return nil }

            if event.keyCode == 53 { // Esc cancela a gravação
                self.stopRecording()
                return nil
            }
            guard let recorded = HotKey(event: event) else {
                NSSound.beep()
                return nil
            }
            self.hotKey = recorded
            self.stopRecording()
            self.onChange?(recorded)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        needsDisplay = true
    }

    @objc private func clear() {
        hotKey = nil
        stopRecording()
        onChange?(nil)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            text = "digite o atalho…"
            color = .controlAccentColor
        } else if let hotKey {
            text = hotKey.displayString
            color = .labelColor
        } else {
            text = "sem atalho"
            color = .tertiaryLabelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: isRecording ? .regular : .medium),
            .foregroundColor: color
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: 10, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        clearButton.isHidden = hotKey == nil || isRecording
    }
}
