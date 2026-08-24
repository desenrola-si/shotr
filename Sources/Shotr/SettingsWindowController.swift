import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private static var shared: SettingsWindowController?

    private let folderLabel = NSTextField(labelWithString: "")
    private let formatPopUp = NSPopUpButton()
    private let afterPopUp = NSPopUpButton()
    private let copyCheck = NSButton(checkboxWithTitle: "Copiar para a área de transferência", target: nil, action: nil)
    private let saveCheck = NSButton(checkboxWithTitle: "Salvar no disco automaticamente", target: nil, action: nil)
    private let soundCheck = NSButton(checkboxWithTitle: "Tocar som ao capturar", target: nil, action: nil)
    private let templateField = NSTextField(string: "")
    private let qualitySlider = NSSlider()
    private let intervalSlider = NSSlider()

    static func present() {
        if shared == nil { shared = SettingsWindowController() }
        AppEnvironment.activateForWindows()
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 430),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "Ajustes do Shotr"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        build()
        load()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }

        let chooseButton = NSButton(title: "Escolher…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .texturedRounded
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor

        ImageFormat.allCases.forEach { formatPopUp.addItem(withTitle: $0.title) }
        formatPopUp.target = self
        formatPopUp.action = #selector(apply)

        AfterCapture.allCases.forEach { afterPopUp.addItem(withTitle: $0.title) }
        afterPopUp.target = self
        afterPopUp.action = #selector(apply)

        [copyCheck, saveCheck, soundCheck].forEach {
            $0.target = self
            $0.action = #selector(apply)
        }

        templateField.target = self
        templateField.action = #selector(apply)
        templateField.placeholderString = "Shotr {date} {time}"

        qualitySlider.minValue = 0.3
        qualitySlider.maxValue = 1
        qualitySlider.target = self
        qualitySlider.action = #selector(apply)

        intervalSlider.minValue = 0.15
        intervalSlider.maxValue = 1.2
        intervalSlider.target = self
        intervalSlider.action = #selector(apply)

        let hotkeyText = """
        ⇧⌘1 tela · ⇧⌘2 área · ⇧⌘3 rolando · ⌃⌥⌘O texto/QR
        ⇧⌘4 repetir área · ⇧⌘5 conta-gotas
        No editor: V seleção · A seta · R retângulo · O elipse · L linha · P lápis
        T texto · N numerador · H marca-texto · B desfoque · X pixelar · K tarja · C recortar
        """
        let hotkeyLabel = NSTextField(wrappingLabelWithString: hotkeyText)
        hotkeyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        hotkeyLabel.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [label("Pasta:"), stack([folderLabel, chooseButton])],
            [label("Formato:"), formatPopUp],
            [label("Qualidade JPEG:"), qualitySlider],
            [label("Depois de capturar:"), afterPopUp],
            [label("Também:"), stackVertical([copyCheck, saveCheck, soundCheck])],
            [label("Nome do arquivo:"), templateField],
            [label("Intervalo do scroll:"), intervalSlider],
            [label("Atalhos:"), hotkeyLabel]
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(grid)

        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20)
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func stack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 8
        return stack
    }

    private func stackVertical(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func load() {
        let preferences = Preferences.shared
        folderLabel.stringValue = preferences.saveDirectory.path
        formatPopUp.selectItem(withTitle: preferences.format.title)
        afterPopUp.selectItem(withTitle: preferences.afterCapture.title)
        copyCheck.state = preferences.alsoCopyToClipboard ? .on : .off
        saveCheck.state = preferences.alsoSaveToDisk ? .on : .off
        soundCheck.state = preferences.playShutterSound ? .on : .off
        templateField.stringValue = preferences.filenameTemplate
        qualitySlider.doubleValue = preferences.jpegQuality
        intervalSlider.doubleValue = preferences.scrollingInterval
    }

    @objc private func apply() {
        let preferences = Preferences.shared
        if let title = formatPopUp.titleOfSelectedItem,
           let format = ImageFormat.allCases.first(where: { $0.title == title }) {
            preferences.format = format
        }
        if let title = afterPopUp.titleOfSelectedItem,
           let after = AfterCapture.allCases.first(where: { $0.title == title }) {
            preferences.afterCapture = after
        }
        preferences.alsoCopyToClipboard = copyCheck.state == .on
        preferences.alsoSaveToDisk = saveCheck.state == .on
        preferences.playShutterSound = soundCheck.state == .on
        preferences.jpegQuality = qualitySlider.doubleValue
        preferences.scrollingInterval = intervalSlider.doubleValue
        let template = templateField.stringValue.trimmingCharacters(in: .whitespaces)
        if !template.isEmpty { preferences.filenameTemplate = template }
    }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Preferences.shared.saveDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Preferences.shared.saveDirectory = url
        folderLabel.stringValue = url.path
    }

    func windowWillClose(_ notification: Notification) {
        apply()
        AppEnvironment.deactivateWhenNoWindows()
    }
}
