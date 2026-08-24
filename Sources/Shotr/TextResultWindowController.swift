import AppKit

final class TextResultWindowController: NSWindowController, NSWindowDelegate {

    private static var open: [TextResultWindowController] = []
    private let textView = NSTextView()
    private let result: RecognitionResult

    static func present(result: RecognitionResult, source: CGImage?) {
        if result.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Nenhum texto reconhecido"
            alert.informativeText = "Não encontrei texto nem QR Code nessa imagem."
            alert.alertStyle = .informational
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        let controller = TextResultWindowController(result: result)
        open.append(controller)
        AppEnvironment.activateForWindows()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        ImageOutput.copyToPasteboard(text: controller.fullText)
    }

    var fullText: String {
        var parts: [String] = []
        if !result.lines.isEmpty { parts.append(result.plainText) }
        if !result.barcodes.isEmpty {
            parts.append("— QR/código de barras —")
            parts.append(contentsOf: result.barcodes)
        }
        return parts.joined(separator: "\n")
    }

    init(result: RecognitionResult) {
        self.result = result
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 420),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Texto reconhecido"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        textView.isEditable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.string = fullText
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView

        let copyButton = NSButton(title: "Copiar tudo", target: self, action: #selector(copyAll))
        copyButton.bezelStyle = .texturedRounded
        copyButton.keyEquivalent = "\r"

        let info = NSTextField(labelWithString:
            "\(result.lines.count) linha(s)" + (result.barcodes.isEmpty ? "" : " · \(result.barcodes.count) código(s)") + " · já copiado")
        info.textColor = .secondaryLabelColor
        info.font = .systemFont(ofSize: 11)

        [scrollView, copyButton, info].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -10),

            info.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            info.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),

            copyButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            copyButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    @objc private func copyAll() {
        ImageOutput.copyToPasteboard(text: textView.string)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
        if Self.open.isEmpty { AppEnvironment.deactivateWhenNoWindows() }
    }
}
