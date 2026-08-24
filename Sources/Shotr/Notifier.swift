import AppKit
import UserNotifications

enum Notifier {
    private static var authorized = false

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            authorized = granted
        }
    }

    static func show(title: String, body: String) {
        guard authorized else {
            NSLog("Shotr: \(title) — \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Alterna a política de ativação: sem janelas, o app fica só na barra de menus.
enum AppEnvironment {
    static func activateForWindows() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    static func deactivateWhenNoWindows() {
        let visible = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        guard !visible else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
