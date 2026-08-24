import AppKit
import Carbon.HIToolbox

/// Atalhos que o próprio macOS já ocupa. Um atalho global registrado por cima
/// de um destes nunca dispara — o sistema atende primeiro.
enum SystemHotKeys {

    private static var cache: [HotKey: String]?

    static func conflict(for hotKey: HotKey) -> String? {
        occupied()[hotKey]
    }

    static func occupied() -> [HotKey: String] {
        if let cache { return cache }
        var result = fallbackList
        for (key, name) in readSymbolicHotKeys() where result[key] == nil {
            result[key] = name
        }
        cache = result
        return result
    }

    static func invalidate() {
        cache = nil
    }

    /// Lê `com.apple.symbolichotkeys`, onde ficam os atalhos de teclado do sistema.
    private static func readSymbolicHotKeys() -> [HotKey: String] {
        guard let defaults = UserDefaults(suiteName: "com.apple.symbolichotkeys"),
              let entries = defaults.dictionary(forKey: "AppleSymbolicHotKeys") else { return [:] }

        var found: [HotKey: String] = [:]
        for (identifier, raw) in entries {
            guard let entry = raw as? [String: Any],
                  (entry["enabled"] as? Bool) ?? false,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Any],
                  parameters.count >= 3,
                  let keyCode = (parameters[1] as? NSNumber)?.intValue,
                  let modifiers = (parameters[2] as? NSNumber)?.intValue,
                  keyCode >= 0 else { continue }

            let hotKey = HotKey(keyCode: UInt32(keyCode),
                                carbonModifiers: HotKey.carbonModifiers(fromCocoaRaw: modifiers))
            guard hotKey.carbonModifiers != 0 else { continue }
            found[hotKey] = symbolicNames[identifier] ?? "atalho do sistema"
        }
        return found
    }

    private static let symbolicNames: [String: String] = [
        "28": "Captura de tela do sistema",
        "29": "Captura de tela para a área de transferência",
        "30": "Captura de área do sistema",
        "31": "Captura de área para a área de transferência",
        "184": "Captura e gravação de tela do sistema",
        "64": "Spotlight",
        "65": "Busca do Finder",
        "32": "Mission Control",
        "33": "Mission Control",
        "36": "Application Windows",
        "60": "Trocar idioma de entrada",
        "61": "Trocar fonte de entrada",
        "162": "Launchpad",
        "175": "Notification Center"
    ]

    /// Rede de segurança: as capturas nativas existem em todo Mac.
    private static let fallbackList: [HotKey: String] = [
        HotKey(keyCode: UInt32(kVK_ANSI_3), carbonModifiers: UInt32(shiftKey | cmdKey)): "Captura de tela do macOS",
        HotKey(keyCode: UInt32(kVK_ANSI_4), carbonModifiers: UInt32(shiftKey | cmdKey)): "Captura de área do macOS",
        HotKey(keyCode: UInt32(kVK_ANSI_5), carbonModifiers: UInt32(shiftKey | cmdKey)): "Captura e gravação do macOS",
        HotKey(keyCode: UInt32(kVK_ANSI_6), carbonModifiers: UInt32(shiftKey | cmdKey)): "Captura da Touch Bar",
        HotKey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey)): "Spotlight",
        HotKey(keyCode: UInt32(kVK_Tab), carbonModifiers: UInt32(cmdKey)): "Trocar de app",
        HotKey(keyCode: UInt32(kVK_ANSI_Q), carbonModifiers: UInt32(cmdKey)): "Encerrar app"
    ]
}
