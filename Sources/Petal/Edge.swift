import AppKit
import PetalCore

/// Draws a thin colored frame on each colored Desktop.
///
/// A window that can't join all Spaces stays on the Space it was first shown
/// on, so each Desktop gets its own window, created the first time that Desktop
/// is on screen. macOS has no public way to put a window on another Space.
@MainActor
final class EdgeController {
    static let width: CGFloat = 4

    private var windows: [String: (window: NSWindow, display: String)] = [:]

    func sync(snapshot: SpacesSnapshot, labels: Labels, enabled: Bool) {
        var wanted: [String: Tint] = [:]
        if enabled {
            for desktop in snapshot.desktops {
                if let tint = labels.color(for: desktop.uuid) { wanted[desktop.uuid] = tint }
            }
        }

        for (uuid, entry) in windows {
            guard let tint = wanted[uuid] else {
                entry.window.orderOut(nil)
                windows[uuid] = nil
                continue
            }
            (entry.window.contentView as? EdgeView)?.color = tint.nsColor
            if let screen = Self.screen(for: entry.display) {
                entry.window.setFrame(Self.frame(on: screen), display: true)
            }
        }

        for (display, uuid) in snapshot.current where windows[uuid] == nil {
            guard let tint = wanted[uuid], let screen = Self.screen(for: display) else { continue }
            windows[uuid] = (Self.makeWindow(on: screen, color: tint.nsColor), display)
        }
    }

    private static func makeWindow(on screen: NSScreen, color: NSColor) -> NSWindow {
        let window = NSWindow(contentRect: frame(on: screen), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        // .stationary keeps it in place in Mission Control, drawn with the desktop
        // instead of shown as a window tile.
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        let view = EdgeView()
        view.color = color
        window.contentView = view
        window.orderFrontRegardless()
        return window
    }

    /// The whole screen except the menu bar.
    private static func frame(on screen: NSScreen) -> NSRect {
        var rect = screen.frame
        rect.size.height = screen.visibleFrame.maxY - rect.minY
        return rect
    }

    /// Matches the display UUID that SkyLight reports to an NSScreen.
    private static func screen(for display: String) -> NSScreen? {
        let match = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
            else { return false }
            return CFUUIDCreateString(nil, uuid) as String == display
        }
        // "Main" shows up when Displays have separate Spaces is off.
        return match ?? NSScreen.screens.first
    }
}

final class EdgeView: NSView {
    var color: NSColor = .clear {
        didSet { layer?.borderColor = color.cgColor }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.borderWidth = EdgeController.width
    }

    required init?(coder: NSCoder) { nil }
}
