import AppKit
import ApplicationServices
import PetalCore

/// Switches Desktops by sending the user's own Mission Control shortcuts.
/// macOS has no other way for an app to do this, and sending keys needs Accessibility.
enum Switcher {
    static var shortcuts: SpaceShortcuts {
        SpaceShortcuts.parse(UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys"))
    }

    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func run(_ plan: SwitchPlan) {
        guard case let .press(shortcut, times) = plan else { return }
        for step in 0..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(step)) { press(shortcut) }
        }
    }

    private static func press(_ shortcut: Shortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: down)
            event?.flags = CGEventFlags(rawValue: shortcut.modifiers)
            event?.post(tap: .cghidEventTap)
        }
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func openKeyboardShortcuts() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
    }
}
