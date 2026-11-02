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

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = SpacesSnapshot()
    @Published private(set) var activeID = 0
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var showEdge: Bool {
        didSet {
            UserDefaults.standard.set(showEdge, forKey: "showEdge")
            syncEdges()
        }
    }

    let labels = Labels()
    private let edges = EdgeController()
    private var observers: [NSObjectProtocol] = []

    init() {
        showEdge = UserDefaults.standard.object(forKey: "showEdge") as? Bool ?? true
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
    var activeColor: Swatch? { active.flatMap { labels.color(for: $0.uuid) } }

    /// Desktops grouped by display, in Mission Control order.
    var displays: [(id: String, desktops: [Desktop])] {
        var order: [String] = []
        var groups: [String: [Desktop]] = [:]
        for desktop in snapshot.desktops {
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
        syncEdges()
    }

    func rename(_ desktop: Desktop, to name: String) {
        objectWillChange.send()
        labels.rename(desktop.uuid, to: name)
    }

    func toggleColor(_ desktop: Desktop, _ swatch: Swatch) {
        objectWillChange.send()
        labels.toggleColor(desktop.uuid, swatch)
        syncEdges()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Petal: launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func syncEdges() {
        edges.sync(snapshot: snapshot, labels: labels, enabled: showEdge)
    }
}
