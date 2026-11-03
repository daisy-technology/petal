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
    private var windows: [String: (window: NSWindow, display: String)] = [:]

    private(set) var level: NSWindow.Level
    /// Called as the windows start coming up, so their content can play its own motion.
    var onRise: ((NameTransition, Double) -> Void)?

    init(level: NSWindow.Level) { self.level = level }

    /// Moves every window to `newLevel`. Going up, the name comes in with `transition`
    /// over `duration`; coming down it fades out in half that, then settles back.
    func move(to newLevel: NSWindow.Level, transition: NameTransition, duration: Double) {
        guard newLevel != level else { return }
        let rising = newLevel > level
        level = newLevel
        let all = windows.values.map(\.window)

        var style = transition
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, style == .zoom || style == .slide { style = .fade }
        if style == .none {
            all.forEach { $0.level = newLevel; $0.alphaValue = 1 }
            return
        }

        func settle(_ seconds: Double) {
            all.forEach { $0.level = newLevel }
            if rising { onRise?(style, seconds) }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = seconds
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                all.forEach { $0.animator().alphaValue = 1 }
            }
        }

        if rising {
            all.forEach { $0.alphaValue = 0 }
            settle(duration)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = duration / 2
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                all.forEach { $0.animator().alphaValue = 0 }
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    // Mission Control may have opened again during the fade.
                    guard self?.level == newLevel else { return }
                    settle(duration / 2)
                }
            })
        }
    }

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

/// Tells when Mission Control is open. There's no API for it, but while it is,
/// the Dock shows a full-screen window at layer 20. The ⌘-Tab app switcher shows
/// the same window, so ⌘ being held when it appears marks it as the switcher.
@MainActor
final class MissionControlWatcher {
    private var timer: Timer?
    private(set) var isOpen = false
    /// True when the window that's up belongs to the ⌘-Tab switcher, not Mission Control.
    private(set) var isAppSwitcher = false

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        // ponytail: polls about 7 times a second; CGWindowList is cheap and there's no notification to use instead.
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let open = Self.dockCoversScreen()
                if open != self.isOpen {
                    self.isOpen = open
                    // ponytail: ⌘ held while opening Mission Control by its own key reads as the switcher.
                    self.isAppSwitcher = open && CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
                    onChange(open)
                }
            }
        }
    }

    private static func dockCoversScreen() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        return list.contains { window in
            guard window[kCGWindowOwnerName as String] as? String == "Dock",
                  window[kCGWindowLayer as String] as? Int == 20,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { return false }
            return (bounds["Height"] ?? 0) >= 400
        }
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
/// Drives Zoom and Slide inside every name view at once.
@MainActor
final class NameStage: ObservableObject {
    @Published private(set) var settled = true
    private(set) var style = NameTransition.fade

    /// Jumps to the start pose, then eases into place over `duration`.
    func play(_ style: NameTransition, duration: Double) {
        self.style = style
        var start = Transaction()
        start.disablesAnimations = true
        withTransaction(start) { settled = false }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: duration)) { self.settled = true }
        }
    }
}

struct NameOverlay: View {
    /// Point sizes the menu's slider moves between.
    static let sizes: ClosedRange<Double> = 60...320
    static let defaultSize = 160.0

    let name: String
    let color: Color?
    let size: Double
    @ObservedObject var stage: NameStage

    var body: some View {
        Text(name)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.2)
            .foregroundStyle((color ?? .white).opacity(0.65))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 2)
            .padding(.horizontal, 80)
            // Zoom grows it from 92%; Slide lifts it 40 pt into place.
            .scaleEffect(stage.settled || stage.style != .zoom ? 1 : 0.92)
            .offset(y: stage.settled || stage.style != .slide ? 0 : 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
