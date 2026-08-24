import AppKit

/// Ponte entre as ações do menu/atalhos e a captura propriamente dita.
enum CaptureCoordinator {

    static func ensurePermission() -> Bool {
        if ScreenCapturer.hasPermission() { return true }
        ScreenCapturer.requestPermission()
        let alert = NSAlert()
        alert.messageText = "Permissão de gravação de tela"
        alert.informativeText = "Autorize o Shotr em Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e abra o app de novo."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Agora não")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    // MARK: - Ações

    static func captureFullScreen() {
        guard ensurePermission() else { return }
        Task { @MainActor in
            let mouse = NSEvent.mouseLocation
            guard let capture = try? await ScreenCapturer.captureDisplay(containing: mouse) else { return }
            deliver(capture.image)
        }
    }

    static func captureArea() {
        guard ensurePermission() else { return }
        AreaSelector.shared.select { result in
            guard let result else { return }
            deliver(result.image)
        }
    }

    static func capturePreviousArea() {
        guard ensurePermission() else { return }
        guard let rect = Preferences.shared.lastArea else {
            captureArea()
            return
        }
        Task { @MainActor in
            guard let image = try? await ScreenCapturer.capture(globalRect: rect) else { return }
            deliver(image)
        }
    }

    static func captureScrolling() {
        guard ensurePermission() else { return }
        AreaSelector.shared.select(highlightWindows: false) { result in
            guard let result else { return }
            ScrollingCapture.shared.start(area: result.globalRect) { image in
                guard let image else { return }
                deliver(image, forceEditor: true)
            }
        }
    }

    static func recognizeText() {
        guard ensurePermission() else { return }
        AreaSelector.shared.select { result in
            guard let result else { return }
            ImageOutput.playShutter()
            DispatchQueue.global(qos: .userInitiated).async {
                let recognition = TextRecognizer.recognize(in: result.image)
                DispatchQueue.main.async {
                    TextResultWindowController.present(result: recognition, source: result.image)
                }
            }
        }
    }

    static func pickColor() {
        guard ensurePermission() else { return }
        AreaSelector.shared.pickColor { color in
            guard let color else { return }
            ImageOutput.copyToPasteboard(text: color.hexString)
            Notifier.show(title: "Cor copiada", body: color.hexString)
        }
    }

    static func captureFromClipboard() {
        guard let image = ImageOutput.imageFromPasteboard() else {
            Notifier.show(title: "Nada de imagem", body: "A área de transferência não tem imagem.")
            return
        }
        EditorWindowController.present(image: image, title: "Da área de transferência")
    }

    static func openLastScreenshotInEditor() {
        let directory = Preferences.shared.saveDirectory
        let contents = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                    includingPropertiesForKeys: [.contentModificationDateKey],
                                                                    options: [.skipsHiddenFiles])) ?? []
        let images = contents.filter { ["png", "jpg", "jpeg", "tiff"].contains($0.pathExtension.lowercased()) }
        let latest = images.max {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
        guard let latest,
              let source = CGImageSourceCreateWithURL(latest as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            Notifier.show(title: "Nada para reabrir", body: "Não achei captura recente em \(directory.lastPathComponent).")
            return
        }
        EditorWindowController.present(image: image, title: latest.lastPathComponent)
    }

    // MARK: - Pós-captura

    static func deliver(_ image: CGImage, forceEditor: Bool = false) {
        ImageOutput.playShutter()
        let preferences = Preferences.shared

        if forceEditor || preferences.afterCapture == .openEditor {
            if preferences.alsoCopyToClipboard { ImageOutput.copyToPasteboard(image) }
            if preferences.alsoSaveToDisk { ImageOutput.save(image) }
            EditorWindowController.present(image: image)
            return
        }

        switch preferences.afterCapture {
        case .copyOnly:
            ImageOutput.copyToPasteboard(image)
            if preferences.alsoSaveToDisk { ImageOutput.save(image) }
            Notifier.show(title: "Captura copiada", body: "\(image.width) × \(image.height) px")
        case .saveOnly:
            let url = ImageOutput.save(image)
            if preferences.alsoCopyToClipboard { ImageOutput.copyToPasteboard(image) }
            Notifier.show(title: "Captura salva", body: url?.lastPathComponent ?? "")
        case .openEditor:
            break
        }
    }
}
