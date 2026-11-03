/// One normal Desktop (Space) as Mission Control numbers it.
public struct Desktop: Equatable, Identifiable {
    public let uuid: String
    public let id64: Int
    public let display: String
    /// 1-based position among normal Desktops on its display.
    public let number: Int

    public init(uuid: String, id64: Int, display: String, number: Int) {
        self.uuid = uuid
        self.id64 = id64
        self.display = display
        self.number = number
    }

    public var id: String { uuid }
    public var defaultName: String { "Desktop \(number)" }
}

public struct SpacesSnapshot: Equatable {
    public var desktops: [Desktop] = []
    /// Display identifier → uuid of the Space showing on it.
    public var current: [String: String] = [:]

    public init() {}

    public func desktop(id64: Int) -> Desktop? { desktops.first { $0.id64 == id64 } }
    public func desktop(uuid: String) -> Desktop? { desktops.first { $0.uuid == uuid } }
}

public enum Spaces {
    /// Normal Desktop. Full-screen apps use 4 and are not numbered by Mission Control.
    static let normalType = 0

    /// Reads the output of the private `CGSCopyManagedDisplaySpaces`.
    /// Anything that isn't the expected shape is dropped, never trapped on.
    public static func parse(_ raw: Any?) -> SpacesSnapshot {
        var snap = SpacesSnapshot()
        for case let display as [String: Any] in raw as? [Any] ?? [] {
            guard let displayID = display["Display Identifier"] as? String else { continue }
            if let cur = display["Current Space"] as? [String: Any], let uuid = cur["uuid"] as? String {
                snap.current[displayID] = uuid
            }
            var number = 0
            for case let space as [String: Any] in display["Spaces"] as? [Any] ?? [] {
                guard (space["type"] as? Int) == normalType,
                      let uuid = space["uuid"] as? String, !uuid.isEmpty,
                      let id64 = space["id64"] as? Int ?? space["ManagedSpaceID"] as? Int
                else { continue }
                number += 1
                snap.desktops.append(Desktop(uuid: uuid, id64: id64, display: displayID, number: number))
            }
        }
        return snap
    }
}
