import AppKit
import Carbon.HIToolbox

final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var registered: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?

    private init() {}

    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            DispatchQueue.main.async { HotKeyCenter.shared.fire(id: hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
    }

    @discardableResult
    func register(_ hotKey: HotKey, action: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x53485452), id: id) // 'SHTR'
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return 0 }
        registered[id] = ref
        handlers[id] = action
        return id
    }

    func unregister(id: UInt32) {
        if let ref = registered.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        handlers.removeValue(forKey: id)
    }

    func unregisterAll() {
        registered.values.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
        handlers.removeAll()
    }

    private func fire(id: UInt32) {
        handlers[id]?()
    }
}
