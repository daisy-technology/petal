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

    /// Also bring the name in front of the windows while the ⌘-Tab switcher is held.
    @Published var nameInAppSwitcher: Bool {
        didSet {
            UserDefaults.standard.set(nameInAppSwitcher, forKey: "nameInAppSwitcher")
            placeNames()
        }
    }

    @Published var nameSize: Double {
        didSet {
            UserDefaults.standard.set(nameSize, forKey: "nameSize")
            syncOverlays()
        }
    }
    @Published var nameTransition: NameTransition {
        didSet { UserDefaults.standard.set(nameTransition.rawValue, forKey: "nameTransition") }
    }
    @Published var nameTransitionDuration: Double {
        didSet { UserDefaults.standard.set(nameTransitionDuration, forKey: "nameTransitionDuration") }
    }
    private var previewEnd: DispatchWorkItem?
    private let stage = NameStage()
    /// True while the size slider is held: the name comes in front of the windows so you see it change.
    private var previewingName = false

    let labels = Labels()
    private let edges = OverlayController(level: .floating)
    private let names = OverlayController(level: .wallpaper)
    private var missionControl: MissionControlWatcher?
    private var observers: [NSObjectProtocol] = []

    init() {
        showEdge = UserDefaults.standard.object(forKey: "showEdge") as? Bool ?? true
        showName = UserDefaults.standard.object(forKey: "showName") as? Bool ?? true
        nameInAppSwitcher = UserDefaults.standard.bool(forKey: "nameInAppSwitcher")
        let size = UserDefaults.standard.double(forKey: "nameSize")
        nameSize = NameOverlay.sizes.contains(size) ? size : NameOverlay.defaultSize
        nameTransition = NameTransition.load(UserDefaults.standard.string(forKey: "nameTransition"))
        nameTransitionDuration = NameTransition.clampDuration(UserDefaults.standard.double(forKey: "nameTransitionDuration"))
        let onChange: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onChange),
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: onChange),
        ]
        // On the wallpaper the name hides behind big windows; while Mission Control
        // is open it sits above them, so every Desktop shows which one it is.
        names.onRise = { [stage] style, seconds in stage.play(style, duration: seconds) }
        missionControl = MissionControlWatcher { [weak self] _ in self?.placeNames() }
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

    func previewName(_ on: Bool) {
        previewEnd?.cancel()
        previewingName = on
        placeNames()
    }

    /// Plays the chosen transition once: the name comes in front, holds, then goes back.
    func playTransitionPreview() {
        previewEnd?.cancel()
        previewingName = false
        placeNames()
        // Let it settle on the wallpaper before it rises again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.previewName(true)
            let end = DispatchWorkItem { [weak self] in self?.previewName(false) }
            self.previewEnd = end
            DispatchQueue.main.asyncAfter(deadline: .now() + self.nameTransitionDuration + 0.8, execute: end)
        }
    }

    private func placeNames() {
        let overview = missionControl.map { $0.isOpen && (nameInAppSwitcher || !$0.isAppSwitcher) } ?? false
        names.move(to: previewingName || overview ? .floating : .wallpaper,
                   transition: nameTransition, duration: nameTransitionDuration)
    }

    private func syncOverlays() {
        var edge: [String: AnyView] = [:]
        var name: [String: AnyView] = [:]
        for desktop in snapshot.desktops {
            let tint = labels.color(for: desktop.uuid)
            if showEdge, let tint { edge[desktop.uuid] = AnyView(EdgeOverlay(color: tint.color)) }
            if showName { name[desktop.uuid] = AnyView(NameOverlay(name: labels.name(for: desktop), color: tint?.color, size: nameSize, stage: stage)) }
        }
        edges.sync(edge, current: snapshot.current)
        names.sync(name, current: snapshot.current)
    }
}
