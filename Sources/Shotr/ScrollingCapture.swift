import AppKit
import Carbon.HIToolbox

/// Captura contínua de uma área enquanto o usuário rola, costurando os quadros.
final class ScrollingCapture {
    static let shared = ScrollingCapture()

    private var stitcher = ImageStitcher()
    private var timer: Timer?
    private var area: CGRect = .zero
    private var hud: HUDPanel?
    private var idleFrames = 0
    private var isRunning = false
    private var hotKeyIDs: [UInt32] = []
    private var completion: ((CGImage?) -> Void)?

    private init() {}

    func start(area: CGRect, completion: @escaping (CGImage?) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.area = area
        self.completion = completion
        stitcher = ImageStitcher()
        idleFrames = 0

        showHUD()
        registerKeys()

        let interval = Preferences.shared.scrollingInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
        tick()
    }

    private func tick() {
        Task { @MainActor in
            guard isRunning, let image = try? await ScreenCapturer.capture(globalRect: area) else { return }
            let appended = stitcher.append(image)
            idleFrames = appended ? 0 : idleFrames + 1
            hud?.update(height: stitcher.capturedHeight, idle: idleFrames)
            if idleFrames >= 40 { finish(cancelled: false) }
        }
    }

    func finish(cancelled: Bool) {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        hud?.close()
        hud = nil
        unregisterKeys()

        let result = cancelled ? nil : stitcher.compose()
        let callback = completion
        completion = nil
        stitcher = ImageStitcher()
        callback?(result)
    }

    // MARK: - HUD e teclas

    private func showHUD() {
        let screen = NSScreen.screens.first { $0.frame.intersects(area) } ?? NSScreen.main
        let panel = HUDPanel(target: self)
        if let screen {
            let origin = CGPoint(x: screen.frame.midX - 190, y: max(screen.frame.minY + 60, area.minY - 90))
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
        hud = panel
    }

    private func registerKeys() {
        let center = HotKeyCenter.shared
        hotKeyIDs.append(center.register(HotKey(keyCode: UInt32(kVK_Return), modifiers: 0)) { [weak self] in
            self?.finish(cancelled: false)
        })
        hotKeyIDs.append(center.register(HotKey(keyCode: UInt32(kVK_Escape), modifiers: 0)) { [weak self] in
            self?.finish(cancelled: true)
        })
    }

    private func unregisterKeys() {
        hotKeyIDs.forEach { HotKeyCenter.shared.unregister(id: $0) }
        hotKeyIDs.removeAll()
    }
}

private final class HUDPanel: NSPanel {
    private let label = NSTextField(labelWithString: "Role a página…")
    private unowned let target: ScrollingCapture

    init(target: ScrollingCapture) {
        self.target = target
        super.init(contentRect: CGRect(x: 0, y: 0, width: 380, height: 62),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        build()
    }

    private func build() {
        let effect = NSVisualEffectView(frame: contentRect(forFrameRect: frame))
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        contentView = effect

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white

        let done = NSButton(title: "Concluir (⏎)", target: self, action: #selector(finish))
        done.bezelStyle = .texturedRounded
        done.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancelar (⎋)", target: self, action: #selector(cancel))
        cancel.bezelStyle = .texturedRounded

        let stack = NSStackView(views: [label, NSView(), cancel, done])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])
    }

    func update(height: Int, idle: Int) {
        let suffix = idle > 6 ? " · sem conteúdo novo" : ""
        label.stringValue = "Capturado: \(height) px\(suffix)"
    }

    @objc private func finish() { target.finish(cancelled: false) }
    @objc private func cancel() { target.finish(cancelled: true) }

    override var canBecomeKey: Bool { false }
}
