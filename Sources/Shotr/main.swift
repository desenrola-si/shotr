import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController()
        Notifier.requestAuthorization()
        buildMainMenu()

        HotKeyCenter.shared.start()
        ShortcutStore.shared.registerAll()
        reportFailedShortcuts()

        runCommandLineAction()

        if !Preferences.shared.hasSeenWelcome {
            Preferences.shared.hasSeenWelcome = true
            WelcomeWindowController.present()
        }
    }

    /// Clicar no app no Spotlight, no Finder ou no Dock cai aqui quando ele já está rodando.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        WelcomeWindowController.present()
        return true
    }

    /// Permite disparar uma captura direto pelo terminal:
    /// `Shotr.app/Contents/MacOS/Shotr --area`
    private func runCommandLineAction() {
        let actions: [String: () -> Void] = [
            "--settings": { SettingsWindowController.present() },
            "--shortcuts-window": { SettingsWindowController.present(selectingShortcuts: true) },
            "--screen": CaptureCoordinator.captureFullScreen,
            "--area": CaptureCoordinator.captureArea,
            "--scroll": CaptureCoordinator.captureScrolling,
            "--ocr": CaptureCoordinator.recognizeText,
            "--color": CaptureCoordinator.pickColor,
            "--previous": CaptureCoordinator.capturePreviousArea
        ]
        guard let argument = CommandLine.arguments.dropFirst().first(where: { actions[$0] != nil }),
              let action = actions[argument] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: action)
    }

    /// Um atalho pode falhar quando outro app já registrou a mesma tecla.
    private func reportFailedShortcuts() {
        let failed = ShortcutStore.shared.failedRegistrations
        guard !failed.isEmpty else { return }
        Notifier.show(title: "Atalho ocupado por outro app",
                      body: failed.map(\.title).joined(separator: ", ") + " — troque em Ajustes › Atalhos.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregisterAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar Shotr", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "Arquivo")
        fileMenu.addItem(withTitle: "Salvar", action: #selector(EditorWindowController.save), keyEquivalent: "s")
        let saveAs = fileMenu.addItem(withTitle: "Salvar Como…", action: #selector(EditorWindowController.saveAs), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Fechar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Editar")
        editMenu.addItem(withTitle: "Desfazer", action: #selector(EditorWindowController.undo(_:)), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Refazer", action: #selector(EditorWindowController.redo(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Copiar", action: #selector(EditorWindowController.copyImage), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Colar como Nova Imagem", action: #selector(pasteAsImage), keyEquivalent: "v").target = self
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Selecionar Tudo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "Visualizar")
        viewMenu.addItem(withTitle: "Aumentar Zoom", action: #selector(EditorWindowController.zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Diminuir Zoom", action: #selector(EditorWindowController.zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Tamanho Real", action: #selector(EditorWindowController.actualSize(_:)), keyEquivalent: "0")
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettings() { SettingsWindowController.present() }
    @objc private func pasteAsImage() { CaptureCoordinator.captureFromClipboard() }
}

/// Flags que não sobem a interface: consultam ou alteram o item de abertura no login.
func handleLoginArguments() {
    let arguments = Set(CommandLine.arguments.dropFirst())
    if arguments.contains("--shortcuts") {
        HotKeyCenter.shared.start()
        ShortcutStore.shared.registerAll()
        let failed = Set(ShortcutStore.shared.failedRegistrations)
        for action in ShortcutAction.allCases {
            let hotKey = ShortcutStore.shared.hotKey(for: action)
            let registro = failed.contains(action) ? "REGISTRO FALHOU" : "registrado"
            let aviso = ShortcutStore.shared.warning(for: action).map { " · \($0)" } ?? ""
            print("\(action.title): \(hotKey?.displayString ?? "sem atalho") · \(registro)\(aviso)")
        }
        exit(0)
    }

    if arguments.contains("--permission") {
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        Task {
            granted = await PermissionGuide.hasAccess()
            semaphore.signal()
        }
        semaphore.wait()
        print("gravacao-de-tela: \(granted ? "concedida" : "negada") (preflight diz: \(CGPreflightScreenCaptureAccess() ? "concedida" : "negada"))")
        exit(0)
    }
    guard !arguments.isDisjoint(with: ["--login-status", "--enable-login", "--disable-login"]) else { return }

    let service = SMAppService.mainApp
    if arguments.contains("--enable-login") {
        do { try service.register() } catch { print("erro ao registrar: \(error.localizedDescription)") }
    }
    if arguments.contains("--disable-login") {
        do { try service.unregister() } catch { print("erro ao remover: \(error.localizedDescription)") }
    }

    let description: String
    switch service.status {
    case .enabled: description = "enabled"
    case .requiresApproval: description = "requiresApproval (aprovar em Ajustes › Geral › Itens de Início)"
    case .notRegistered: description = "notRegistered"
    case .notFound: description = "notFound"
    @unknown default: description = "desconhecido"
    }
    print("abrir-ao-iniciar: \(description)")
    exit(0)
}

handleLoginArguments()

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
