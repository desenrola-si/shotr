import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay
    case noPermission
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "Nenhuma tela encontrada."
        case .noPermission: return "Permissão de gravação de tela negada. Abra Ajustes do Sistema › Privacidade e Segurança › Gravação de Tela e marque o Shotr."
        case .failed(let message): return message
        }
    }
}

enum ScreenCapturer {

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Captura o display inteiro que contém o ponto informado (ou o principal).
    static func captureDisplay(containing point: CGPoint? = nil) async throws -> (image: CGImage, screen: NSScreen) {
        let screen = point.flatMap { p in NSScreen.screens.first { $0.frame.contains(p) } }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { throw CaptureError.noDisplay }
        let image = try await capture(screen: screen)
        return (image, screen)
    }

    static func capture(screen: NSScreen) async throws -> CGImage {
        let displayID = screen.displayID
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID })
                ?? content.displays.first else { throw CaptureError.noDisplay }

        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let configuration = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// Captura uma janela específica, com o fundo transparente preservado.
    static func capture(window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.captureResolution = .best
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = false
        configuration.backgroundColor = .clear
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    static func onScreenWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows
            .filter { $0.frame.width > 40 && $0.frame.height > 40 }
            .filter { $0.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { $0.windowLayer < $1.windowLayer }
    }

    /// Captura um retângulo em coordenadas globais do AppKit (origem embaixo à esquerda).
    static func capture(globalRect rect: CGRect) async throws -> CGImage {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main else {
            throw CaptureError.noDisplay
        }
        let full = try await capture(screen: screen)
        guard let cropped = full.cropping(to: screen.pixelRect(fromGlobal: rect)) else {
            throw CaptureError.failed("Não consegui recortar a área selecionada.")
        }
        return cropped
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    /// Converte um retângulo global do AppKit em pixels dentro da imagem capturada desta tela.
    func pixelRect(fromGlobal rect: CGRect) -> CGRect {
        let scale = backingScaleFactor
        let localX = rect.minX - frame.minX
        let localTop = frame.maxY - rect.maxY
        return CGRect(x: (localX * scale).rounded(.down),
                      y: (localTop * scale).rounded(.down),
                      width: (rect.width * scale).rounded(),
                      height: (rect.height * scale).rounded())
    }
}
