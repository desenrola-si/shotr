import AppKit

/// Guarda o atalho de cada ação e mantém o registro global em dia.
final class ShortcutStore {
    static let shared = ShortcutStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "shortcuts"
    private var hotKeys: [ShortcutAction: HotKey] = [:]
    private var registrationIDs: [ShortcutAction: UInt32] = [:]

    private init() {
        load()
    }

    private func load() {
        var loaded: [ShortcutAction: HotKey] = [:]
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: HotKey].self, from: data) {
            for (rawAction, hotKey) in decoded {
                guard let action = ShortcutAction(rawValue: rawAction) else { continue }
                loaded[action] = hotKey
            }
        }
        for action in ShortcutAction.allCases where loaded[action] == nil {
            loaded[action] = action.defaultHotKey
        }
        hotKeys = loaded
    }

    private func persist() {
        let encodable = Dictionary(uniqueKeysWithValues: hotKeys.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        defaults.set(data, forKey: storageKey)
    }

    // MARK: - Consulta

    func hotKey(for action: ShortcutAction) -> HotKey? {
        hotKeys[action]
    }

    /// Outra ação do Shotr que já usa a mesma combinação.
    func conflictingAction(with hotKey: HotKey, ignoring action: ShortcutAction) -> ShortcutAction? {
        hotKeys.first { $0.key != action && $0.value == hotKey }?.key
    }

    /// Atalhos que o sistema ou outra ação do Shotr já ocupam, prontos para exibir.
    func warning(for action: ShortcutAction) -> String? {
        guard let hotKey = hotKeys[action] else { return nil }
        if let system = SystemHotKeys.conflict(for: hotKey) {
            return "\(hotKey.displayString) é do macOS (\(system)) — o Shotr não vai receber"
        }
        if let other = conflictingAction(with: hotKey, ignoring: action) {
            return "mesma combinação de “\(other.title)”"
        }
        return nil
    }

    // MARK: - Alteração

    func set(_ hotKey: HotKey?, for action: ShortcutAction) {
        if let hotKey {
            hotKeys[action] = hotKey
        } else {
            hotKeys.removeValue(forKey: action)
        }
        persist()
        registerAll()
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }

    func resetToDefaults() {
        hotKeys = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultHotKey) })
        persist()
        registerAll()
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }

    // MARK: - Registro global

    func registerAll() {
        registrationIDs.values.forEach { HotKeyCenter.shared.unregister(id: $0) }
        registrationIDs.removeAll()
        for (action, hotKey) in hotKeys {
            let id = HotKeyCenter.shared.register(hotKey) { action.run() }
            guard id != 0 else { continue }
            registrationIDs[action] = id
        }
    }

    /// Ações cujo registro global falhou — normalmente porque outro app já pegou a tecla.
    var failedRegistrations: [ShortcutAction] {
        hotKeys.keys.filter { registrationIDs[$0] == nil }.sorted { $0.title < $1.title }
    }
}

extension Notification.Name {
    static let shortcutsChanged = Notification.Name("ShotrShortcutsChanged")
}
