import AppKit
import Carbon.HIToolbox

/// Cada coisa que o Shotr sabe fazer por atalho.
enum ShortcutAction: String, CaseIterable, Codable {
    case captureScreen
    case captureArea
    case captureScrolling
    case recognizeText
    case capturePreviousArea
    case pickColor

    var title: String {
        switch self {
        case .captureScreen: return "Capturar Tela"
        case .captureArea: return "Capturar Área"
        case .captureScrolling: return "Captura Rolando"
        case .recognizeText: return "Reconhecer Texto/QR"
        case .capturePreviousArea: return "Repetir Última Área"
        case .pickColor: return "Conta-gotas de Cor"
        }
    }

    var symbolName: String {
        switch self {
        case .captureScreen: return "display"
        case .captureArea: return "viewfinder"
        case .captureScrolling: return "chevron.down.2"
        case .recognizeText: return "text.viewfinder"
        case .capturePreviousArea: return "arrow.clockwise.viewfinder"
        case .pickColor: return "eyedropper"
        }
    }

    /// Padrões escolhidos para não brigar com os atalhos nativos de captura
    /// do macOS (⇧⌘3, ⇧⌘4, ⇧⌘5 e ⇧⌘6).
    var defaultHotKey: HotKey {
        switch self {
        case .captureScreen:
            return HotKey(keyCode: UInt32(kVK_ANSI_1), carbonModifiers: UInt32(shiftKey | cmdKey))
        case .captureArea:
            return HotKey(keyCode: UInt32(kVK_ANSI_2), carbonModifiers: UInt32(shiftKey | cmdKey))
        case .captureScrolling:
            return HotKey(keyCode: UInt32(kVK_ANSI_S), carbonModifiers: UInt32(optionKey | shiftKey | cmdKey))
        case .recognizeText:
            return HotKey(keyCode: UInt32(kVK_ANSI_O), carbonModifiers: UInt32(controlKey | optionKey | cmdKey))
        case .capturePreviousArea:
            return HotKey(keyCode: UInt32(kVK_ANSI_R), carbonModifiers: UInt32(optionKey | shiftKey | cmdKey))
        case .pickColor:
            return HotKey(keyCode: UInt32(kVK_ANSI_C), carbonModifiers: UInt32(optionKey | shiftKey | cmdKey))
        }
    }

    func run() {
        switch self {
        case .captureScreen: CaptureCoordinator.captureFullScreen()
        case .captureArea: CaptureCoordinator.captureArea()
        case .captureScrolling: CaptureCoordinator.captureScrolling()
        case .recognizeText: CaptureCoordinator.recognizeText()
        case .capturePreviousArea: CaptureCoordinator.capturePreviousArea()
        case .pickColor: CaptureCoordinator.pickColor()
        }
    }
}
