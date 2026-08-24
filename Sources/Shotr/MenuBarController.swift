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
        statusItem.isVisible = true
        if statusItem.button == nil {
            NSLog("Shotr: a barra de menus não devolveu espaço para o ícone")
        }
        menu.delegate = self
        buildMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(buildMenu),
                                               name: .shortcutsChanged, object: nil)
        statusItem.menu = menu
    }

    @objc private func buildMenu() {
        menu.removeAllItems()

        add(title: "Reabrir última captura", action: #selector(reopen), shortcut: nil)
        menu.addItem(.separator())

        add(title: ShortcutAction.captureScreen.title, action: #selector(captureScreen), shortcut: .captureScreen)
        add(title: ShortcutAction.captureArea.title, action: #selector(captureArea), shortcut: .captureArea)
        add(title: ShortcutAction.captureScrolling.title, action: #selector(captureScrolling), shortcut: .captureScrolling)
        add(title: ShortcutAction.recognizeText.title, action: #selector(recognizeText), shortcut: .recognizeText)

        let moreItem = NSMenuItem(title: "mais", action: nil, keyEquivalent: "")
        moreItem.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        let moreMenu = NSMenu()
        moreMenu.addItem(item(title: ShortcutAction.capturePreviousArea.title,
                              action: #selector(capturePreviousArea), shortcut: .capturePreviousArea))
        moreMenu.addItem(item(title: ShortcutAction.pickColor.title,
                              action: #selector(pickColor), shortcut: .pickColor))
        moreMenu.addItem(item(title: "Abrir Imagem da Área de Transferência",
                              action: #selector(fromClipboard), shortcut: nil))
        moreMenu.addItem(.separator())
        moreMenu.addItem(item(title: "Abrir Pasta de Capturas", action: #selector(openFolder), shortcut: nil))
        moreItem.submenu = moreMenu
        menu.addItem(moreItem)

        menu.addItem(.separator())

        let shortcutsItem = NSMenuItem(title: "Configurar Atalhos…", action: #selector(openShortcuts), keyEquivalent: "")
        shortcutsItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)
        shortcutsItem.target = self
        menu.addItem(shortcutsItem)

        let settingsItem = NSMenuItem(title: "Ajustes", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        let launchItem = NSMenuItem(title: "Abrir ao Iniciar", action: #selector(toggleLaunchAtStartup), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = isLaunchAtStartupEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(title: String, action: Selector, shortcut: ShortcutAction?) -> NSMenuItem {
        let hotKey = shortcut.flatMap { ShortcutStore.shared.hotKey(for: $0) }
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: hotKey?.menuKeyEquivalent ?? "")
        menuItem.keyEquivalentModifierMask = hotKey?.cocoaModifiers ?? []
        menuItem.target = self
        if let shortcut {
            menuItem.image = NSImage(systemSymbolName: shortcut.symbolName, accessibilityDescription: nil)
        }
        if let hotKey, hotKey.menuKeyEquivalent.isEmpty {
            menuItem.title = "\(title)   \(hotKey.displayString)"
        }
        if let shortcut, let warning = ShortcutStore.shared.warning(for: shortcut) {
            menuItem.toolTip = warning
        }
        return menuItem
    }

    private func add(title: String, action: Selector, shortcut: ShortcutAction?) {
        menu.addItem(item(title: title, action: action, shortcut: shortcut))
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

    @objc private func openShortcuts() {
        SettingsWindowController.present(selectingShortcuts: true)
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
