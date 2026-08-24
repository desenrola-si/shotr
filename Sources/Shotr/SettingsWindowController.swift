import AppKit
import ServiceManagement

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private static var shared: SettingsWindowController?

    private let folderLabel = NSTextField(labelWithString: "")
    private let formatPopUp = NSPopUpButton()
    private let afterPopUp = NSPopUpButton()
    private let copyCheck = NSButton(checkboxWithTitle: "Copiar para a área de transferência", target: nil, action: nil)
    private let saveCheck = NSButton(checkboxWithTitle: "Salvar no disco automaticamente", target: nil, action: nil)
    private let soundCheck = NSButton(checkboxWithTitle: "Tocar som ao capturar", target: nil, action: nil)
    private let loginCheck = NSButton(checkboxWithTitle: "Abrir junto com o sistema", target: nil, action: nil)
    private let templateField = NSTextField(string: "")
    private let qualitySlider = NSSlider()
    private let intervalSlider = NSSlider()
    private let intervalLabel = NSTextField(labelWithString: "")
    private let qualityLabel = NSTextField(labelWithString: "")

    private var recorders: [ShortcutAction: KeyRecorderField] = [:]
    private var warningLabels: [ShortcutAction: NSTextField] = [:]

    static func present(selectingShortcuts: Bool = false) {
        if shared == nil { shared = SettingsWindowController() }
        AppEnvironment.activateForWindows()
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        if selectingShortcuts { shared?.selectShortcutsTab() }
        NSApp.activate(ignoringOtherApps: true)
    }

    private let tabView = NSTabView()

    init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 470),
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

    private func selectShortcutsTab() {
        tabView.selectTabViewItem(at: 1)
    }

    // MARK: - Montagem

    private func build() {
        guard let content = window?.contentView else { return }

        let general = NSTabViewItem(identifier: "geral")
        general.label = "Geral"
        general.view = generalView()

        let shortcuts = NSTabViewItem(identifier: "atalhos")
        shortcuts.label = "Atalhos"
        shortcuts.view = shortcutsView()

        let editor = NSTabViewItem(identifier: "editor")
        editor.label = "Editor"
        editor.view = editorView()

        [general, shortcuts, editor].forEach { tabView.addTabViewItem($0) }
        tabView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    private func generalView() -> NSView {
        let container = NSView()

        let chooseButton = NSButton(title: "Escolher…", target: self, action: #selector(chooseFolder))
        chooseButton.bezelStyle = .texturedRounded
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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
        loginCheck.target = self
        loginCheck.action = #selector(toggleLogin)

        templateField.target = self
        templateField.action = #selector(apply)
        templateField.placeholderString = "Shotr {date} {time}"
        templateField.translatesAutoresizingMaskIntoConstraints = false
        templateField.widthAnchor.constraint(equalToConstant: 220).isActive = true

        qualitySlider.minValue = 0.3
        qualitySlider.maxValue = 1
        qualitySlider.target = self
        qualitySlider.action = #selector(apply)
        qualitySlider.translatesAutoresizingMaskIntoConstraints = false
        qualitySlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        qualityLabel.textColor = .secondaryLabelColor
        qualityLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        intervalSlider.minValue = 0.15
        intervalSlider.maxValue = 1.2
        intervalSlider.target = self
        intervalSlider.action = #selector(apply)
        intervalSlider.translatesAutoresizingMaskIntoConstraints = false
        intervalSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        intervalLabel.textColor = .secondaryLabelColor
        intervalLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)

        let hint = NSTextField(wrappingLabelWithString:
            "“{date}” vira a data e “{time}” a hora. O intervalo do scroll é a pausa entre um quadro e o próximo na captura rolando.")
        hint.textColor = .tertiaryLabelColor
        hint.font = .systemFont(ofSize: 11)

        let grid = NSGridView(views: [
            [label("Pasta:"), stack([folderLabel, chooseButton])],
            [label("Formato:"), stack([formatPopUp])],
            [label("Qualidade JPEG:"), stack([qualitySlider, qualityLabel])],
            [label("Depois de capturar:"), stack([afterPopUp])],
            [label("Também:"), stackVertical([copyCheck, saveCheck, soundCheck])],
            [label("Nome do arquivo:"), stack([templateField])],
            [label("Intervalo do scroll:"), stack([intervalSlider, intervalLabel])],
            [label("Início:"), stack([loginCheck])],
            [NSGridCell.emptyContentView, hint]
        ])
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20)
        ])
        return container
    }

    private func shortcutsView() -> NSView {
        let container = NSView()

        let explanation = NSTextField(wrappingLabelWithString:
            "Clique no campo e digite a combinação. O macOS reserva ⇧⌘3, ⇧⌘4, ⇧⌘5 e ⇧⌘6 para as capturas dele: se você escolher uma dessas, o aviso aparece embaixo e o Shotr não recebe a tecla.")
        explanation.font = .systemFont(ofSize: 11)
        explanation.textColor = .secondaryLabelColor

        var rows: [[NSView]] = []
        for action in ShortcutAction.allCases {
            let title = NSTextField(labelWithString: action.title)
            title.alignment = .right

            let recorder = KeyRecorderField(hotKey: ShortcutStore.shared.hotKey(for: action))
            recorder.onChange = { [weak self] hotKey in
                ShortcutStore.shared.set(hotKey, for: action)
                self?.refreshWarnings()
            }
            recorders[action] = recorder

            let warning = NSTextField(labelWithString: "")
            warning.font = .systemFont(ofSize: 10)
            warning.textColor = .systemOrange
            warning.lineBreakMode = .byTruncatingTail
            warningLabels[action] = warning

            rows.append([title, stackVertical([recorder, warning])])
        }

        let resetButton = NSButton(title: "Restaurar padrões", target: self, action: #selector(resetShortcuts))
        resetButton.bezelStyle = .texturedRounded
        rows.append([NSGridCell.emptyContentView, stack([resetButton])])

        let grid = NSGridView(views: rows)
        grid.columnSpacing = 12
        grid.rowSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.translatesAutoresizingMaskIntoConstraints = false
        explanation.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(explanation)
        container.addSubview(grid)

        NSLayoutConstraint.activate([
            explanation.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            explanation.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            explanation.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: explanation.bottomAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20)
        ])
        refreshWarnings()
        return container
    }

    private func editorView() -> NSView {
        let container = NSView()
        let text = """
        Seleção de área
          arrastar seleciona · clique pega a janela sob o cursor
          Espaço captura a tela inteira · Esc cancela
          a lupa mostra o pixel e o código da cor

        Ferramentas do editor
          V selecionar e mover     A seta            R retângulo
          O elipse                 L linha           P lápis
          T texto                  N numerador       H marca-texto
          B desfoque               X pixelar         K tarja preta
          C recortar

        Ações
          ⌘C copiar · ⌘S salvar · ⇧⌘S salvar como
          ⌘Z desfazer · ⇧⌘Z refazer · ⌘+ ⌘- zoom · ⌘0 tamanho real
          Delete apaga o item selecionado

        Segurar ⇧ ao arrastar trava o ângulo (linha e seta)
        ou a proporção (retângulo e elipse).
        """
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20)
        ])
        return container
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.alignment = .right
        return field
    }

    private func stack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
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

    // MARK: - Estado

    private func load() {
        let preferences = Preferences.shared
        folderLabel.stringValue = preferences.saveDirectory.path
        formatPopUp.selectItem(withTitle: preferences.format.title)
        afterPopUp.selectItem(withTitle: preferences.afterCapture.title)
        copyCheck.state = preferences.alsoCopyToClipboard ? .on : .off
        saveCheck.state = preferences.alsoSaveToDisk ? .on : .off
        soundCheck.state = preferences.playShutterSound ? .on : .off
        loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
        templateField.stringValue = preferences.filenameTemplate
        qualitySlider.doubleValue = preferences.jpegQuality
        intervalSlider.doubleValue = preferences.scrollingInterval
        updateValueLabels()
    }

    private func updateValueLabels() {
        qualityLabel.stringValue = "\(Int(qualitySlider.doubleValue * 100))%"
        intervalLabel.stringValue = String(format: "%.2f s", intervalSlider.doubleValue)
    }

    private func refreshWarnings() {
        SystemHotKeys.invalidate()
        for action in ShortcutAction.allCases {
            recorders[action]?.update(hotKey: ShortcutStore.shared.hotKey(for: action))
            let warning = ShortcutStore.shared.warning(for: action)
            warningLabels[action]?.stringValue = warning ?? ""
            warningLabels[action]?.isHidden = warning == nil
        }
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
        updateValueLabels()
    }

    @objc private func toggleLogin() {
        do {
            if loginCheck.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Notifier.show(title: "Não consegui alterar", body: error.localizedDescription)
        }
        loginCheck.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func resetShortcuts() {
        ShortcutStore.shared.resetToDefaults()
        refreshWarnings()
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
