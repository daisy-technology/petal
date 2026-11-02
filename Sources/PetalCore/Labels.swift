import Foundation

public enum Swatch: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, teal, blue, indigo, pink
    public var id: String { rawValue }
}

/// A Desktop's color: a preset swatch or any custom `#RRGGBB`.
/// Stored as a single string ("orange" or "#FF8800").
public enum Tint: Equatable {
    case swatch(Swatch)
    case custom(String)

    public init?(_ raw: String) {
        if let swatch = Swatch(rawValue: raw) {
            self = .swatch(swatch)
        } else if let hex = Self.normalizedHex(raw) {
            self = .custom(hex)
        } else {
            return nil
        }
    }

    public var raw: String {
        switch self {
        case .swatch(let swatch): swatch.rawValue
        case .custom(let hex): hex
        }
    }

    /// 0-255 components of a custom color; nil for presets, which follow the system palette.
    public var rgb: (r: Int, g: Int, b: Int)? {
        guard case .custom(let hex) = self, let value = Int(hex.dropFirst(), radix: 16) else { return nil }
        return (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
    }

    static func normalizedHex(_ raw: String) -> String? {
        let digits = raw.dropFirst()
        guard raw.hasPrefix("#"), digits.count == 6, digits.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + digits.uppercased()
    }
}

public struct Label: Codable, Equatable {
    public var name: String?
    public var color: Tint?
    var isEmpty: Bool { name == nil && color == nil }

    init(name: String? = nil, color: Tint? = nil) {
        self.name = name
        self.color = color
    }

    private enum Keys: String, CodingKey { case name, color }

    // A color this version doesn't understand is dropped instead of failing the whole store.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        color = try c.decodeIfPresent(String.self, forKey: .color).flatMap(Tint.init)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(color?.raw, forKey: .color)
    }
}

/// Names and colors keyed by Space uuid, stored in UserDefaults.
public final class Labels {
    public static let maxLength = 32
    private static let key = "labels"
    private static let orderKey = "order"

    private let defaults: UserDefaults
    public private(set) var all: [String: Label]
    /// Petal's own menu order, by uuid. Mission Control's order can't be changed.
    public private(set) var order: [String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.key)
        all = data.flatMap { try? JSONDecoder().decode([String: Label].self, from: $0) } ?? [:]
        order = defaults.stringArray(forKey: Self.orderKey) ?? []
    }

    public func name(for desktop: Desktop) -> String {
        all[desktop.uuid]?.name ?? desktop.defaultName
    }

    public func color(for uuid: String) -> Tint? {
        all[uuid]?.color
    }

    /// Trims, caps at `maxLength`; blank input goes back to the default name.
    public func rename(_ uuid: String, to input: String) {
        let trimmed = String(input.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLength))
        update(uuid) { $0.name = trimmed.isEmpty ? nil : trimmed }
    }

    /// Picking the color a Desktop already has clears it.
    public func toggleColor(_ uuid: String, _ swatch: Swatch) {
        update(uuid) { $0.color = $0.color == .swatch(swatch) ? nil : .swatch(swatch) }
    }

    /// Sets any `#RRGGBB` color. Anything else is ignored and the current color stays.
    public func setCustomColor(_ uuid: String, hex: String) {
        guard let normalized = Tint.normalizedHex(hex) else { return }
        update(uuid) { $0.color = .custom(normalized) }
    }

    public func clearColor(_ uuid: String) {
        update(uuid) { $0.color = nil }
    }

    /// Desktops in the user's order. Ones never moved keep Mission Control order, after the moved ones.
    public func ordered(_ desktops: [Desktop]) -> [Desktop] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        return desktops.enumerated().sorted { a, b in
            switch (rank[a.element.uuid], rank[b.element.uuid]) {
            case let (x?, y?): x < y
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }

    /// Moves a Desktop within its display's list. Other displays keep their order.
    public func move(_ uuid: String, to index: Int, within group: [Desktop]) {
        var uuids = ordered(group).map(\.uuid)
        guard let from = uuids.firstIndex(of: uuid) else { return }
        uuids.remove(at: from)
        uuids.insert(uuid, at: min(max(index, 0), uuids.count))
        let inGroup = Set(uuids)
        order = order.filter { !inGroup.contains($0) } + uuids
        defaults.set(order, forKey: Self.orderKey)
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
        let keptOrder = order.filter(uuids.contains)
        if keptOrder.count != order.count {
            order = keptOrder
            defaults.set(order, forKey: Self.orderKey)
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
