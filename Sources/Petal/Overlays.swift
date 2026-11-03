import AppKit
import PetalCore
import SwiftUI

/// Keeps one borderless, click-through window per Desktop: the colored edge, or
/// the Desktop's name drawn large on the wallpaper.
///
/// A window that can't join all Spaces stays on the Space it was first shown
/// on, so each Desktop gets its own window, created the first time that Desktop
/// is on screen. macOS has no public way to put a window on another Space.
@MainActor
final class OverlayController {
    private let level: NSWindow.Level
    private var windows: [String: (window: NSWindow, display: String)] = [:]

    init(level: NSWindow.Level) { self.level = level }

    /// `wanted` maps a Desktop's uuid to what its window shows; Desktops left out lose their window.
    func sync(_ wanted: [String: AnyView], current: [String: String]) {
        for (uuid, entry) in windows {
            guard let view = wanted[uuid] else {
                entry.window.orderOut(nil)
                windows[uuid] = nil
                continue
            }
            (entry.window.contentView as? NSHostingView<AnyView>)?.rootView = view
            if let screen = Self.screen(for: entry.display) {
                entry.window.setFrame(Self.frame(on: screen), display: true)
            }
        }

        for (display, uuid) in current where windows[uuid] == nil {
            guard let view = wanted[uuid], let screen = Self.screen(for: display) else { continue }
            windows[uuid] = (makeWindow(on: screen, view: view), display)
        }
    }

    private func makeWindow(on screen: NSScreen, view: AnyView) -> NSWindow {
        let window = NSWindow(contentRect: Self.frame(on: screen), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = level
        // .stationary keeps it in place in Mission Control, drawn with the desktop
        // instead of shown as a window tile.
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        window.contentView = host
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

extension NSWindow.Level {
    /// On the wallpaper, under the desktop icons and every window.
    static let wallpaper = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
}

/// A thin frame around a colored Desktop.
struct EdgeOverlay: View {
    let color: Color
    var body: some View {
        Rectangle().strokeBorder(color, lineWidth: 4).ignoresSafeArea()
    }
}

/// The Desktop's name, large and faint, so Mission Control shows which Desktop is which.
struct NameOverlay: View {
    let name: String
    let color: Color?

    var body: some View {
        Text(name)
            .font(.system(size: 160, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.2)
            .foregroundStyle((color ?? .white).opacity(0.65))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 2)
            .padding(.horizontal, 80)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
