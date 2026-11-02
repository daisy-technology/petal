import Foundation

public enum Swatch: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, indigo, pink
    public var id: String { rawValue }
}

public struct Label: Codable, Equatable {
    public var name: String?
    public var color: Swatch?
    var isEmpty: Bool { name == nil && color == nil }
}

/// Names and colors keyed by Space uuid, stored in UserDefaults.
public final class Labels {
    public static let maxLength = 32
    private static let key = "labels"

    private let defaults: UserDefaults
    public private(set) var all: [String: Label]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.key)
        all = data.flatMap { try? JSONDecoder().decode([String: Label].self, from: $0) } ?? [:]
    }

    public func name(for desktop: Desktop) -> String {
        all[desktop.uuid]?.name ?? desktop.defaultName
    }

    public func color(for uuid: String) -> Swatch? {
        all[uuid]?.color
    }

    /// Trims, caps at `maxLength`; blank input goes back to the default name.
    public func rename(_ uuid: String, to input: String) {
        let trimmed = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLength))
        update(uuid) { $0.name = trimmed.isEmpty ? nil : trimmed }
    }

    /// Picking the color a Desktop already has clears it.
    public func toggleColor(_ uuid: String, _ swatch: Swatch) {
        update(uuid) { $0.color = $0.color == swatch ? nil : swatch }
    }

    /// Forgets Desktops that no longer exist. An empty set means the Space list
    /// couldn't be read, so nothing is removed.
    public func prune(keeping uuids: Set<String>) {
        guard !uuids.isEmpty else { return }
        let kept = all.filter { uuids.contains($0.key) }
        if kept.count != all.count {
            all = kept
            save()
        }
    }

    private func update(_ uuid: String, _ change: (inout Label) -> Void) {
        var label = all[uuid] ?? Label()
        change(&label)
        all[uuid] = label.isEmpty ? nil : label
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
