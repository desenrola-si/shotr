import AppKit
import Carbon.HIToolbox

struct HotKey: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let captureScreen = HotKey(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(shiftKey | cmdKey))
    static let captureArea = HotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(shiftKey | cmdKey))
    static let scrollingCapture = HotKey(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(shiftKey | cmdKey))
    static let recognizeText = HotKey(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(controlKey | optionKey | cmdKey))
    static let previousArea = HotKey(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(shiftKey | cmdKey))
    static let pickColor = HotKey(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(shiftKey | cmdKey))

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    var keyEquivalent: String {
        switch Int(keyCode) {
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_O: return "o"
        default: return ""
        }
    }
}

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
        let status = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, hotKeyID,
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
