import AppKit
import ServiceManagement

final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shotr")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "Shotr"
        menu.delegate = self
        buildMenu()
        statusItem.menu = menu
    }

    private func buildMenu() {
        menu.removeAllItems()

        add(title: "Reabrir última captura", action: #selector(reopen), hotKey: nil)
        menu.addItem(.separator())

        add(title: "Capturar Tela", action: #selector(captureScreen), hotKey: .captureScreen, symbol: "display")
        add(title: "Capturar Área", action: #selector(captureArea), hotKey: .captureArea, symbol: "viewfinder")
        add(title: "Captura Rolando", action: #selector(captureScrolling), hotKey: .scrollingCapture, symbol: "chevron.down.2")
        add(title: "Reconhecer Texto/QR", action: #selector(recognizeText), hotKey: .recognizeText, symbol: "text.viewfinder")

        let moreItem = NSMenuItem(title: "mais", action: nil, keyEquivalent: "")
        moreItem.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        let moreMenu = NSMenu()
        moreMenu.addItem(item(title: "Capturar Área Anterior", action: #selector(capturePreviousArea), hotKey: .previousArea))
        moreMenu.addItem(item(title: "Conta-gotas de Cor", action: #selector(pickColor), hotKey: .pickColor))
        moreMenu.addItem(item(title: "Abrir Imagem da Área de Transferência", action: #selector(fromClipboard), hotKey: nil))
        moreMenu.addItem(.separator())
        moreMenu.addItem(item(title: "Abrir Pasta de Capturas", action: #selector(openFolder), hotKey: nil))
        moreItem.submenu = moreMenu
        menu.addItem(moreItem)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "Abrir ao Iniciar", action: #selector(toggleLaunchAtStartup), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = isLaunchAtStartupEnabled ? .on : .off
        menu.addItem(launchItem)

        let settingsItem = NSMenuItem(title: "Ajustes", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(title: String, action: Selector, hotKey: HotKey?, symbol: String? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: hotKey?.keyEquivalent ?? "")
        menuItem.keyEquivalentModifierMask = hotKey?.cocoaModifiers ?? []
        menuItem.target = self
        if let symbol { menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return menuItem
    }

    private func add(title: String, action: Selector, hotKey: HotKey?, symbol: String? = nil) {
        menu.addItem(item(title: title, action: action, hotKey: hotKey, symbol: symbol))
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first { $0.title == "Abrir ao Iniciar" }?.state = isLaunchAtStartupEnabled ? .on : .off
    }

    // MARK: - Ações

    @objc private func reopen() { CaptureCoordinator.openLastScreenshotInEditor() }
    @objc private func captureScreen() { CaptureCoordinator.captureFullScreen() }
    @objc private func captureArea() { CaptureCoordinator.captureArea() }
    @objc private func captureScrolling() { CaptureCoordinator.captureScrolling() }
    @objc private func recognizeText() { CaptureCoordinator.recognizeText() }
    @objc private func capturePreviousArea() { CaptureCoordinator.capturePreviousArea() }
    @objc private func pickColor() { CaptureCoordinator.pickColor() }
    @objc private func fromClipboard() { CaptureCoordinator.captureFromClipboard() }

    @objc private func openFolder() {
        NSWorkspace.shared.open(Preferences.shared.saveDirectory)
    }

    @objc private func openSettings() {
        SettingsWindowController.present()
    }

    // MARK: - Abrir ao iniciar

    private var isLaunchAtStartupEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func toggleLaunchAtStartup() {
        do {
            if isLaunchAtStartupEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            Notifier.show(title: "Não consegui alterar", body: error.localizedDescription)
        }
        buildMenu()
    }
}
