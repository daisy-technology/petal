import AppKit
import PetalCore
import ServiceManagement
import SwiftUI

extension Swatch {
    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .pink: .systemPink
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

extension Tint {
    /// Saturation and brightness of colors picked on the hue strip.
    static let stripSaturation = 0.75
    static let stripBrightness = 0.95

    var nsColor: NSColor {
        switch self {
        case .swatch(let swatch):
            return swatch.nsColor
        case .custom:
            let c = rgb ?? (0, 0, 0)
            return NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Where this color sits on the hue strip (0...1).
    var hue: Double { Double(nsColor.usingColorSpace(.sRGB)?.hueComponent ?? 0) }

    static func hex(hue: Double) -> String {
        let c = NSColor(hue: hue, saturation: stripSaturation, brightness: stripBrightness, alpha: 1)
            .usingColorSpace(.sRGB)!
        func byte(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = SpacesSnapshot()
    @Published private(set) var activeID = 0
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Set after a click to switch was refused for lack of Accessibility access.
    @Published private(set) var needsAccessibility = false
    /// Set when the Mission Control shortcut Petal needs is turned off.
    @Published private(set) var shortcutOff = false
    @Published var showEdge: Bool {
        didSet {
            UserDefaults.standard.set(showEdge, forKey: "showEdge")
            syncOverlays()
        }
    }
    @Published var showName: Bool {
        didSet {
            UserDefaults.standard.set(showName, forKey: "showName")
            syncOverlays()
        }
    }

    let labels = Labels()
    private let edges = OverlayController(level: .floating)
    private let names = OverlayController(level: .wallpaper)
    private var observers: [NSObjectProtocol] = []

    init() {
        showEdge = UserDefaults.standard.object(forKey: "showEdge") as? Bool ?? true
        showName = UserDefaults.standard.object(forKey: "showName") as? Bool ?? true
        let onChange: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onChange),
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: onChange),
        ]
        refresh()
    }

    var active: Desktop? { snapshot.desktop(id64: activeID) }
    var title: String { active.map(labels.name(for:)) ?? "Desktop" }
    var activeColor: Tint? { active.flatMap { labels.color(for: $0.uuid) } }

    /// Desktops grouped by display, in Mission Control order.
    var displays: [(id: String, desktops: [Desktop])] {
        var order: [String] = []
        var groups: [String: [Desktop]] = [:]
        for desktop in labels.ordered(snapshot.desktops) {
            if groups[desktop.display] == nil { order.append(desktop.display) }
            groups[desktop.display, default: []].append(desktop)
        }
        return order.map { ($0, groups[$0]!) }
    }

    func refresh() {
        let read = SkyLight.read()
        snapshot = read.snapshot
        activeID = read.activeID
        labels.prune(keeping: Set(snapshot.desktops.map(\.uuid)))
        syncOverlays()
    }

    func rename(_ desktop: Desktop, to name: String) {
        objectWillChange.send()
        labels.rename(desktop.uuid, to: name)
        syncOverlays()
    }

    func toggleColor(_ desktop: Desktop, _ swatch: Swatch) {
        objectWillChange.send()
        labels.toggleColor(desktop.uuid, swatch)
        syncOverlays()
    }

    func clearColor(_ desktop: Desktop) {
        objectWillChange.send()
        labels.clearColor(desktop.uuid)
        syncOverlays()
    }

    func move(_ desktop: Desktop, to index: Int) {
        objectWillChange.send()
        labels.move(desktop.uuid, to: index, within: snapshot.desktops.filter { $0.display == desktop.display })
    }

    /// Starts switching to `desktop`. Returns true when the menu should close.
    func switchTo(_ desktop: Desktop) -> Bool {
        refresh()
        guard let target = snapshot.desktop(uuid: desktop.uuid) else { return false }
        if snapshot.current[target.display] == target.uuid { return true }
        guard let plan = Spaces.plan(to: target, in: snapshot, shortcuts: Switcher.shortcuts) else {
            shortcutOff = true
            return false
        }
        // Ask macOS for Accessibility only the first time; after that, point to Settings.
        guard Switcher.isTrusted(prompt: !needsAccessibility) else {
            needsAccessibility = true
            return false
        }
        needsAccessibility = false
        shortcutOff = false
        // Let the menu close before the keys go out.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Switcher.run(plan) }
        return true
    }

    func recheckAccess() {
        if needsAccessibility, Switcher.isTrusted(prompt: false) { needsAccessibility = false }
    }

    func setCustomColor(_ desktop: Desktop, hue: Double) {
        objectWillChange.send()
        labels.setCustomColor(desktop.uuid, hex: Tint.hex(hue: hue))
        syncOverlays()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Petal: launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func syncOverlays() {
        var edge: [String: AnyView] = [:]
        var name: [String: AnyView] = [:]
        for desktop in snapshot.desktops {
            let tint = labels.color(for: desktop.uuid)
            if showEdge, let tint { edge[desktop.uuid] = AnyView(EdgeOverlay(color: tint.color)) }
            if showName { name[desktop.uuid] = AnyView(NameOverlay(name: labels.name(for: desktop), color: tint?.color)) }
        }
        edges.sync(edge, current: snapshot.current)
        names.sync(name, current: snapshot.current)
    }
}
