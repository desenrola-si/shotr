import AppKit
import ScreenCaptureKit

/// O `CGPreflightScreenCaptureAccess` mente quando a assinatura do app mudou:
/// o painel mostra o app ligado e a captura segue negada. Quem responde a verdade
/// é o próprio ScreenCaptureKit.
enum PermissionGuide {

    private static var alertShownAt: Date?

    static func hasAccess() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    static func ensureAccess() async -> Bool {
        if await hasAccess() { return true }
        CGRequestScreenCaptureAccess()
        if await hasAccess() { return true }
        presentAlert()
        return false
    }

    @MainActor
    private static func presentAlert() {
        if let alertShownAt, Date().timeIntervalSince(alertShownAt) < 60 { return }
        alertShownAt = Date()

        let alert = NSAlert()
        alert.messageText = "O macOS ainda não liberou a captura"
        alert.informativeText = """
        Se o Shotr já aparece marcado em Gravação de Tela, a autorização é de uma versão anterior \
        do app: remova o Shotr da lista com o botão “−”, ligue de novo e escolha “Sair e Reabrir”.
        """
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Agora não")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
