/// A keyboard shortcut as macOS stores it in `com.apple.symbolichotkeys`.
public struct Shortcut: Equatable {
    public let keyCode: UInt16
    /// Modifier bits; the same values in NSEvent.ModifierFlags and CGEventFlags.
    public let modifiers: UInt64

    public init(keyCode: UInt16, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

/// The Mission Control shortcuts Petal can send to change Desktops.
public struct SpaceShortcuts: Equatable {
    /// Mission Control number → "Switch to Desktop N", only for enabled ones.
    public var desktops: [Int: Shortcut] = [:]
    public var left: Shortcut?
    public var right: Shortcut?

    // Symbolic hotkey ids from com.apple.symbolichotkeys.
    static let leftID = "79", rightID = "81", firstDesktopID = 118, lastDesktopID = 133
    /// Control + the function bit that arrow keys carry.
    static let arrowModifiers: UInt64 = 0x840000

    /// Reads `AppleSymbolicHotKeys`. A missing entry means the macOS default:
    /// Control-arrows on, "Switch to Desktop N" off.
    public static func parse(_ hotKeys: [String: Any]?) -> SpaceShortcuts {
        let hotKeys = hotKeys ?? [:]
        let defaultLeft = Shortcut(keyCode: 123, modifiers: arrowModifiers)
        let defaultRight = Shortcut(keyCode: 124, modifiers: arrowModifiers)

        var result = SpaceShortcuts()
        result.left = hotKeys[leftID] == nil ? defaultLeft : enabledShortcut(hotKeys[leftID], default: defaultLeft)
        result.right = hotKeys[rightID] == nil ? defaultRight : enabledShortcut(hotKeys[rightID], default: defaultRight)
        for id in firstDesktopID...lastDesktopID {
            let number = id - firstDesktopID + 1
            if let shortcut = enabledShortcut(hotKeys[String(id)], default: defaultDesktop(number)) {
                result.desktops[number] = shortcut
            }
        }
        return result
    }

    /// Control-1 … Control-9, the keys macOS assigns when "Switch to Desktop N" is turned on.
    static func defaultDesktop(_ number: Int) -> Shortcut? {
        let digitKeys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard (1...digitKeys.count).contains(number) else { return nil }
        return Shortcut(keyCode: digitKeys[number - 1], modifiers: 0x40000)
    }

    /// An enabled entry with no key data uses the default keys; macOS stores untouched shortcuts that way.
    private static func enabledShortcut(_ entry: Any?, default fallback: Shortcut?) -> Shortcut? {
        guard let entry = entry as? [String: Any], flag(entry["enabled"]) else { return nil }
        guard let value = entry["value"] as? [String: Any] else { return fallback }
        guard let parameters = value["parameters"] as? [Any], parameters.count >= 3,
              let keyCode = number(parameters[1]), let modifiers = number(parameters[2]),
              keyCode >= 0, keyCode < 0xFFFF, modifiers >= 0
        else { return nil }
        return Shortcut(keyCode: UInt16(keyCode), modifiers: UInt64(modifiers))
    }

    private static func flag(_ value: Any?) -> Bool {
        (value as? Bool) ?? (number(value).map { $0 != 0 } ?? false)
    }

    private static func number(_ value: Any?) -> Int? {
        (value as? Int) ?? (value as? Double).map { Int($0) }
    }
}

public enum SwitchPlan: Equatable {
    case press(Shortcut, times: Int)
}

extension Spaces {
    /// How to get from the target display's current Desktop to `target`, or nil
    /// when it's already current or the needed shortcut is turned off.
    public static func plan(to target: Desktop, in snapshot: SpacesSnapshot, shortcuts: SpaceShortcuts) -> SwitchPlan? {
        let onDisplay = snapshot.desktops.filter { $0.display == target.display }
        guard let currentUUID = snapshot.current[target.display],
              let current = onDisplay.firstIndex(where: { $0.uuid == currentUUID }),
              let goal = onDisplay.firstIndex(of: target),
              current != goal
        else { return nil }

        // "Switch to Desktop N" numbering across several displays isn't reliable, so only use it with one.
        let displays = Set(snapshot.desktops.map(\.display))
        if displays.count == 1, let direct = shortcuts.desktops[target.number] {
            return .press(direct, times: 1)
        }
        let steps = goal - current
        guard let arrow = steps > 0 ? shortcuts.right : shortcuts.left else { return nil }
        return .press(arrow, times: abs(steps))
    }
}
