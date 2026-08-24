import AppKit

final class EditorWindowController: NSWindowController, CanvasViewDelegate, NSWindowDelegate {

    private let canvas: CanvasView
    private var toolButtons: [ToolKind: NSButton] = [:]
    private let statusLabel = NSTextField(labelWithString: "")
    private let colorWell = NSColorWell()
    private let widthSlider = NSSlider()

    private static var openEditors: [EditorWindowController] = []

    static func present(image: CGImage, title: String = "Shotr") {
        let controller = EditorWindowController(image: image, title: title)
        openEditors.append(controller)
        controller.showWindow(nil)
        AppEnvironment.activateForWindows()
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init(image: CGImage, title: String) {
        canvas = CanvasView(image: image)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let scale = screen.backingScaleFactor
        let maxSize = screen.visibleFrame.insetBy(dx: 60, dy: 60).size
        let natural = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(1, min(maxSize.width / natural.width, (maxSize.height - 96) / natural.height))
        let contentSize = CGSize(width: max(560, natural.width * fit), height: max(320, natural.height * fit) + 88)

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        canvas.zoom = fit
        canvas.delegate = self
        window.delegate = self
        buildInterface()
        updateStatus()

        NotificationCenter.default.addObserver(self, selector: #selector(toolChangedFromCanvas),
                                               name: .canvasToolChanged, object: canvas)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Interface

    private func buildInterface() {
        guard let window, let content = window.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let toolbar = makeToolbar()
        let bottomBar = makeBottomBar()
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.underPageBackgroundColor
        scrollView.documentView = canvas
        scrollView.allowsMagnification = false

        [toolbar, scrollView, bottomBar].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 44)
        ])

        canvas.frame = CGRect(origin: .zero, size: canvas.intrinsicContentSize)
        window.makeFirstResponder(canvas)
        selectTool(.arrow)
    }

    private func makeToolbar() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .titlebar
        bar.blendingMode = .withinWindow

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY

        let tools: [ToolKind] = [.select, .arrow, .rectangle, .ellipse, .line, .pen,
                                 .text, .counter, .highlight, .blur, .pixelate, .redact, .crop]
        for tool in tools {
            let button = NSButton(image: NSImage(systemSymbolName: tool.symbolName,
                                                 accessibilityDescription: tool.title) ?? NSImage(),
                                  target: self, action: #selector(toolButtonTapped(_:)))
            button.bezelStyle = .texturedRounded
            button.setButtonType(.toggle)
            button.toolTip = "\(tool.title) (\(CanvasView.toolShortcuts.first { $0.value == tool }?.key.uppercased() ?? ""))"
            button.tag = tools.firstIndex(of: tool) ?? 0
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            toolButtons[tool] = button
            stack.addArrangedSubview(button)
        }

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 22).isActive = true
        stack.addArrangedSubview(separator)

        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 40).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(colorWell)

        for color in [NSColor.systemRed, .systemYellow, .systemGreen, .systemBlue, .white, .black] {
            let swatch = NSButton(title: "", target: self, action: #selector(swatchTapped(_:)))
            swatch.wantsLayer = true
            swatch.isBordered = false
            swatch.layer?.backgroundColor = color.cgColor
            swatch.layer?.cornerRadius = 8
            swatch.layer?.borderWidth = 1
            swatch.layer?.borderColor = NSColor.separatorColor.cgColor
            swatch.translatesAutoresizingMaskIntoConstraints = false
            swatch.widthAnchor.constraint(equalToConstant: 16).isActive = true
            swatch.heightAnchor.constraint(equalToConstant: 16).isActive = true
            swatch.tag = Int(color.hexString.dropFirst(), radix: 16) ?? 0
            stack.addArrangedSubview(swatch)
        }

        widthSlider.minValue = 1
        widthSlider.maxValue = 24
        widthSlider.doubleValue = 4
        widthSlider.target = self
        widthSlider.action = #selector(widthChanged)
        widthSlider.translatesAutoresizingMaskIntoConstraints = false
        widthSlider.widthAnchor.constraint(equalToConstant: 90).isActive = true
        stack.addArrangedSubview(widthSlider)

        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        return bar
    }

    private func makeBottomBar() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .titlebar
        bar.blendingMode = .withinWindow

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY

        statusLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(statusLabel)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        let actions: [(String, String, Selector)] = [
            ("Texto/QR", "text.viewfinder", #selector(recognizeText)),
            ("Limpar", "trash", #selector(clearAnnotations)),
            ("Salvar como…", "square.and.arrow.down.on.square", #selector(saveAs)),
            ("Salvar", "square.and.arrow.down", #selector(save)),
            ("Copiar", "doc.on.doc", #selector(copyImage))
        ]
        for (title, symbol, selector) in actions {
            let button = NSButton(title: " " + title, target: self, action: selector)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.imagePosition = .imageLeading
            button.bezelStyle = .texturedRounded
            stack.addArrangedSubview(button)
        }

        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor)
        ])
        return bar
    }

    // MARK: - Ações

    @objc private func toolButtonTapped(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let tool = ToolKind(rawValue: raw) else { return }
        selectTool(tool)
    }

    @objc private func toolChangedFromCanvas() {
        selectTool(canvas.tool)
    }

    private func selectTool(_ tool: ToolKind) {
        canvas.tool = tool
        toolButtons.forEach { $0.value.state = ($0.key == tool) ? .on : .off }
        window?.invalidateCursorRects(for: canvas)
    }

    @objc private func colorChanged() {
        canvas.color = colorWell.color
    }

    @objc private func swatchTapped(_ sender: NSButton) {
        guard let cgColor = sender.layer?.backgroundColor else { return }
        let color = NSColor(cgColor: cgColor) ?? .systemRed
        canvas.color = color
        colorWell.color = color
    }

    @objc private func widthChanged() {
        canvas.lineWidth = CGFloat(widthSlider.doubleValue)
        canvas.fontSize = CGFloat(widthSlider.doubleValue) * 7
    }

    @objc func copyImage() {
        ImageOutput.copyToPasteboard(canvas.flattenedImage())
        flashStatus("Copiado")
    }

    @objc func save() {
        guard let url = ImageOutput.save(canvas.flattenedImage()) else {
            flashStatus("Falha ao salvar")
            return
        }
        flashStatus("Salvo em \(url.lastPathComponent)")
    }

    @objc func saveAs() {
        ImageOutput.saveWithPanel(canvas.flattenedImage())
    }

    @objc func clearAnnotations() {
        canvas.clearAnnotations()
    }

    @objc func recognizeText() {
        let image = canvas.flattenedImage()
        flashStatus("Lendo texto…")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = TextRecognizer.recognize(in: image)
            DispatchQueue.main.async {
                TextResultWindowController.present(result: result, source: image)
            }
        }
    }

    @objc func undo(_ sender: Any?) { canvas.undo(); updateStatus() }
    @objc func redo(_ sender: Any?) { canvas.redo(); updateStatus() }

    @objc func zoomIn(_ sender: Any?) {
        canvas.zoom = min(6, canvas.zoom * 1.25)
        canvas.frame = CGRect(origin: .zero, size: canvas.intrinsicContentSize)
        updateStatus()
    }

    @objc func zoomOut(_ sender: Any?) {
        canvas.zoom = max(0.1, canvas.zoom / 1.25)
        canvas.frame = CGRect(origin: .zero, size: canvas.intrinsicContentSize)
        updateStatus()
    }

    @objc func actualSize(_ sender: Any?) {
        canvas.zoom = 1
        canvas.frame = CGRect(origin: .zero, size: canvas.intrinsicContentSize)
        updateStatus()
    }

    // MARK: - Delegados

    func canvasDidChangeImage(_ canvas: CanvasView) {
        canvas.frame = CGRect(origin: .zero, size: canvas.intrinsicContentSize)
        updateStatus()
    }

    func canvasDidRequestCropFinished(_ canvas: CanvasView) {
        selectTool(.arrow)
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        Self.openEditors.removeAll { $0 === self }
        if Self.openEditors.isEmpty { AppEnvironment.deactivateWhenNoWindows() }
    }

    private func updateStatus() {
        let size = canvas.pixelSize
        statusLabel.stringValue = "\(Int(size.width)) × \(Int(size.height)) px · \(Int(canvas.zoom * 100))%"
    }

    private func flashStatus(_ message: String) {
        statusLabel.stringValue = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in self?.updateStatus() }
    }
}
