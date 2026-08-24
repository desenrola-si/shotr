import AppKit

/// O app vive na barra de menus: abrir pelo Spotlight não mostraria nada.
/// Esta janela é a resposta visível a esse clique.
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {

    private static var shared: WelcomeWindowController?
    private let permissionLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "Autorizar…", target: nil, action: nil)

    static func present() {
        if shared == nil { shared = WelcomeWindowController() }
        AppEnvironment.activateForWindows()
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        shared?.refreshPermission()
    }

    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 400),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Shotr"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 38, weight: .regular)
        icon.contentTintColor = .controlAccentColor

        let title = NSTextField(labelWithString: "O Shotr mora na barra de menus")
        title.font = .systemFont(ofSize: 17, weight: .semibold)

        let explanation = NSTextField(wrappingLabelWithString: """
        Ele não tem janela principal nem ícone no Dock: procure o ícone de moldura \
        no topo direito da tela, ao lado do relógio. Clicar nele abre o menu com tudo.

        Se o ícone não aparecer, a barra pode estar cheia — em Ajustes do Sistema › \
        Barra de Menus dá para liberar espaço.
        """)
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor

        let shortcuts = NSTextField(wrappingLabelWithString: shortcutSummary())
        shortcuts.font = .monospacedSystemFont(ofSize: 11, weight: .regular)

        permissionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        permissionButton.bezelStyle = .texturedRounded
        permissionButton.target = self
        permissionButton.action = #selector(fixPermission)

        let settingsButton = NSButton(title: "Ajustes e atalhos", target: self, action: #selector(openSettings))
        settingsButton.bezelStyle = .texturedRounded

        let testButton = NSButton(title: "Testar captura de área", target: self, action: #selector(testCapture))
        testButton.bezelStyle = .texturedRounded
        testButton.keyEquivalent = "\r"

        let header = NSStackView(views: [icon, title])
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY

        let permissionRow = NSStackView(views: [permissionLabel, permissionButton])
        permissionRow.orientation = .horizontal
        permissionRow.spacing = 10

        let buttons = NSStackView(views: [settingsButton, testButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let column = NSStackView(views: [header, explanation, shortcuts, permissionRow, buttons])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 16
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)

        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24)
        ])
    }

    private func shortcutSummary() -> String {
        ShortcutAction.allCases.map { action in
            let hotKey = ShortcutStore.shared.hotKey(for: action)?.displayString ?? "sem atalho"
            return hotKey.padding(toLength: max(6, hotKey.count + 2), withPad: " ", startingAt: 0) + action.title
        }.joined(separator: "\n")
    }

    func refreshPermission() {
        permissionLabel.stringValue = "Verificando a permissão de tela…"
        permissionButton.isHidden = true
        Task { @MainActor in
            let granted = await PermissionGuide.hasAccess()
            permissionLabel.stringValue = granted
                ? "✓ Gravação de tela autorizada"
                : "✗ Gravação de tela bloqueada — a captura não funciona assim"
            permissionLabel.textColor = granted ? .systemGreen : .systemOrange
            permissionButton.isHidden = granted
        }
    }

    @objc private func fixPermission() {
        Task { @MainActor in
            _ = await PermissionGuide.ensureAccess()
            refreshPermission()
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.present(selectingShortcuts: true)
    }

    @objc private func testCapture() {
        window?.orderOut(nil)
        CaptureCoordinator.captureArea()
    }

    func windowWillClose(_ notification: Notification) {
        AppEnvironment.deactivateWhenNoWindows()
    }
}
