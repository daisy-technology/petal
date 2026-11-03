import XCTest
@testable import PetalCore

/// Builds the shape `CGSCopyManagedDisplaySpaces` returns (probed on macOS 27.0.1).
private func space(_ id: Int, _ uuid: String, type: Int = 0) -> [String: Any] {
    ["id64": id, "ManagedSpaceID": id, "type": type, "uuid": uuid]
}

private func display(_ id: String, current: String, _ spaces: [[String: Any]]) -> [String: Any] {
    ["Display Identifier": id, "Current Space": ["uuid": current], "Spaces": spaces]
}

final class SpacesTests: XCTestCase {
    // T-1
    func testOneDisplayNumbersInOrder() {
        let raw = [display("D1", current: "a", [space(1, "a"), space(2, "b"), space(3, "c")])]
        let snap = Spaces.parse(raw)
        XCTAssertEqual(snap.desktops.map(\.uuid), ["a", "b", "c"])
        XCTAssertEqual(snap.desktops.map(\.number), [1, 2, 3])
        XCTAssertEqual(snap.desktops.map(\.defaultName), ["Desktop 1", "Desktop 2", "Desktop 3"])
    }

    // T-2
    func testFullScreenSpaceIsSkipped() {
        let raw = [display("D1", current: "a", [space(1, "a"), space(9, "fs", type: 4), space(2, "b")])]
        let snap = Spaces.parse(raw)
        XCTAssertEqual(snap.desktops.map(\.uuid), ["a", "b"])
        XCTAssertEqual(snap.desktops.last?.defaultName, "Desktop 2")
    }

    // T-3
    func testNumberingRestartsPerDisplay() {
        let raw = [
            display("D1", current: "a", [space(1, "a"), space(2, "b")]),
            display("D2", current: "d", [space(3, "c"), space(4, "d")]),
        ]
        let snap = Spaces.parse(raw)
        XCTAssertEqual(snap.desktops.map(\.number), [1, 2, 1, 2])
        XCTAssertEqual(snap.desktops.map(\.display), ["D1", "D1", "D2", "D2"])
    }

    // T-4
    func testMalformedInputNeverCrashes() {
        XCTAssertTrue(Spaces.parse(nil).desktops.isEmpty)
        XCTAssertTrue(Spaces.parse([Any]()).desktops.isEmpty)
        XCTAssertTrue(Spaces.parse("garbage").desktops.isEmpty)
        let raw: [Any] = [
            42,
            ["Display Identifier": "D1", "Spaces": "nope"],
            display("D2", current: "x", [["id64": 5, "type": 0], space(6, "ok")]),
        ]
        let snap = Spaces.parse(raw)
        XCTAssertEqual(snap.desktops.map(\.uuid), ["ok"])
        XCTAssertEqual(snap.desktops.first?.number, 1)
    }

    // T-5
    func testCurrentSpacePerDisplay() {
        let raw = [
            display("D1", current: "b", [space(1, "a"), space(2, "b")]),
            display("D2", current: "c", [space(3, "c")]),
        ]
        XCTAssertEqual(Spaces.parse(raw).current, ["D1": "b", "D2": "c"])
    }

    // T-6
    func testActiveLookup() {
        let raw = [display("D1", current: "a", [space(1, "a"), space(7, "fs", type: 4)])]
        let snap = Spaces.parse(raw)
        XCTAssertEqual(snap.desktop(id64: 1)?.uuid, "a")
        XCTAssertNil(snap.desktop(id64: 7))
        XCTAssertNil(snap.desktop(id64: 99))
    }
}

final class LabelsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let d1 = Desktop(uuid: "a", id64: 1, display: "D1", number: 1)

    override func setUp() {
        suite = "petal.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    // T-7
    func testRenameTrims() {
        let labels = Labels(defaults: defaults)
        labels.rename("a", to: "  Design  ")
        XCTAssertEqual(labels.name(for: d1), "Design")
    }

    // T-8
    func testBlankRenameRestoresDefault() {
        let labels = Labels(defaults: defaults)
        labels.rename("a", to: "Design")
        labels.rename("a", to: "   ")
        XCTAssertEqual(labels.name(for: d1), "Desktop 1")
    }

    // T-9
    func testRenameCapsLength() {
        let labels = Labels(defaults: defaults)
        labels.rename("a", to: String(repeating: "x", count: 40))
        XCTAssertEqual(labels.name(for: d1).count, Labels.maxLength)
    }

    // T-10
    func testPersistsAcrossInstances() {
        let first = Labels(defaults: defaults)
        first.rename("a", to: "Mail")
        first.toggleColor("a", .teal)
        let second = Labels(defaults: defaults)
        XCTAssertEqual(second.name(for: d1), "Mail")
        XCTAssertEqual(second.color(for: "a"), .swatch(.teal))
    }

    // T-11
    func testPruneDropsMissingDesktops() {
        let labels = Labels(defaults: defaults)
        labels.rename("a", to: "Keep")
        labels.rename("gone", to: "Old")
        labels.prune(keeping: ["a"])
        XCTAssertEqual(Set(labels.all.keys), ["a"])
        XCTAssertEqual(Set(Labels(defaults: defaults).all.keys), ["a"])
    }

    // T-12
    func testPruneWithNothingSeenKeepsEverything() {
        let labels = Labels(defaults: defaults)
        labels.rename("a", to: "Keep")
        labels.prune(keeping: [])
        XCTAssertEqual(labels.name(for: d1), "Keep")
    }

    // T-13
    func testToggleColor() {
        let labels = Labels(defaults: defaults)
        labels.toggleColor("a", .pink)
        XCTAssertEqual(labels.color(for: "a"), .swatch(.pink))
        labels.toggleColor("a", .blue)
        XCTAssertEqual(labels.color(for: "a"), .swatch(.blue))
        labels.toggleColor("a", .blue)
        XCTAssertNil(labels.color(for: "a"))
    }

    // T-14
    func testEmptyEntryIsRemoved() {
        let labels = Labels(defaults: defaults)
        labels.rename("a", to: "Name")
        labels.toggleColor("a", .red)
        labels.rename("a", to: "")
        labels.toggleColor("a", .red)
        XCTAssertTrue(labels.all.isEmpty)
    }

    // T-16
    func testCustomColorIsNormalizedAndPersists() {
        let labels = Labels(defaults: defaults)
        labels.setCustomColor("a", hex: "#ff8800")
        XCTAssertEqual(labels.color(for: "a"), .custom("#FF8800"))
        let tint = Labels(defaults: defaults).color(for: "a")
        XCTAssertEqual(tint, .custom("#FF8800"))
        XCTAssertEqual(tint?.rgb?.r, 255)
        XCTAssertEqual(tint?.rgb?.g, 136)
        XCTAssertEqual(tint?.rgb?.b, 0)
    }

    // T-17
    func testInvalidCustomColorIsRejected() {
        let labels = Labels(defaults: defaults)
        labels.toggleColor("a", .green)
        for bad in ["orange", "#12345", "#GGGGGG", "FF8800", ""] {
            labels.setCustomColor("a", hex: bad)
        }
        XCTAssertEqual(labels.color(for: "a"), .swatch(.green))
    }

    // T-18
    func testUnknownStoredColorKeepsTheName() {
        let json = #"{"a":{"name":"Mail","color":"ultraviolet"}}"#
        defaults.set(Data(json.utf8), forKey: "labels")
        let labels = Labels(defaults: defaults)
        XCTAssertEqual(labels.name(for: d1), "Mail")
        XCTAssertNil(labels.color(for: "a"))
    }

    // T-15
    func testParseAndNameIsFast() {
        let raw = (0..<2).map { d in
            display("D\(d)", current: "s\(d)-0", (0..<8).map { space(d * 8 + $0, "s\(d)-\($0)") })
        }
        let labels = Labels(defaults: defaults)
        for i in 0..<8 { labels.rename("s0-\(i)", to: "Name \(i)") }
        let start = DispatchTime.now()
        let snap = Spaces.parse(raw)
        let names = snap.desktops.map { labels.name(for: $0) }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        XCTAssertEqual(names.count, 16)
        XCTAssertLessThan(ms, 5)
    }
}

final class LabelStoreTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "petal.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    // T-19
    func testClearColorKeepsName() {
        let labels = Labels(defaults: defaults)
        labels.rename("a", to: "Mail")
        labels.setCustomColor("a", hex: "#336699")
        labels.clearColor("a")
        XCTAssertNil(labels.color(for: "a"))
        XCTAssertEqual(labels.all["a"]?.name, "Mail")
    }

    // T-20
    func testOldMenuOrderIsDropped() {
        defaults.set(["c", "a"], forKey: "order")
        _ = Labels(defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "order"))
    }
}

final class SwitchingTests: XCTestCase {
    private let ctrl: UInt64 = 0x40000
    private let arrows: UInt64 = 0x840000

    private func display(_ id: String, current: String, _ uuids: [String], from start: Int) -> [String: Any] {
        ["Display Identifier": id, "Current Space": ["uuid": current],
         "Spaces": uuids.enumerated().map { ["id64": start + $0, "type": 0, "uuid": $1] as [String: Any] }]
    }

    private var defaults: SpaceShortcuts { SpaceShortcuts.parse(nil) }

    // T-23
    func testNoPlanForCurrentDesktop() {
        let snap = Spaces.parse([display("D1", current: "a", ["a", "b"], from: 1)])
        XCTAssertNil(Spaces.plan(to: snap.desktops[0], in: snap, shortcuts: defaults))
    }

    // T-24
    func testStepsCountFromThatDisplaysCurrentDesktop() {
        let snap = Spaces.parse([
            display("D1", current: "b", ["a", "b"], from: 1),
            display("D2", current: "c", ["c", "d", "e"], from: 10),
        ])
        let right = Shortcut(keyCode: 124, modifiers: arrows)
        let left = Shortcut(keyCode: 123, modifiers: arrows)
        XCTAssertEqual(Spaces.plan(to: snap.desktop(uuid: "e")!, in: snap, shortcuts: defaults), .press(right, times: 2))
        XCTAssertEqual(Spaces.plan(to: snap.desktop(uuid: "a")!, in: snap, shortcuts: defaults), .press(left, times: 1))
    }

    // T-25
    func testDirectShortcutOnOneDisplay() {
        let snap = Spaces.parse([display("D1", current: "a", ["a", "b", "c"], from: 1)])
        var shortcuts = defaults
        let three = Shortcut(keyCode: 20, modifiers: ctrl)
        shortcuts.desktops[3] = three
        XCTAssertEqual(Spaces.plan(to: snap.desktop(uuid: "c")!, in: snap, shortcuts: shortcuts), .press(three, times: 1))
    }

    // T-26
    func testTwoDisplaysFallBackToSteps() {
        let snap = Spaces.parse([
            display("D1", current: "a", ["a", "b", "c"], from: 1),
            display("D2", current: "x", ["x"], from: 10),
        ])
        var shortcuts = defaults
        shortcuts.desktops[3] = Shortcut(keyCode: 20, modifiers: ctrl)
        XCTAssertEqual(Spaces.plan(to: snap.desktop(uuid: "c")!, in: snap, shortcuts: shortcuts),
                       .press(Shortcut(keyCode: 124, modifiers: arrows), times: 2))
    }

    // T-27
    func testParseSymbolicHotKeys() {
        XCTAssertEqual(defaults.left, Shortcut(keyCode: 123, modifiers: arrows))
        XCTAssertEqual(defaults.right, Shortcut(keyCode: 124, modifiers: arrows))
        XCTAssertTrue(defaults.desktops.isEmpty)

        let parsed = SpaceShortcuts.parse([
            "79": ["enabled": false, "value": ["parameters": [65535, 123, 8650752], "type": "standard"]],
            "81": ["enabled": true, "value": ["parameters": [65535, 2, 1048576], "type": "standard"]],
            "120": ["enabled": 1, "value": ["parameters": [51, 20, 262144], "type": "standard"]],
            "121": ["enabled": 0, "value": ["parameters": [52, 21, 262144], "type": "standard"]],
        ])
        XCTAssertNil(parsed.left)
        XCTAssertEqual(parsed.right, Shortcut(keyCode: 2, modifiers: 1048576))
        XCTAssertEqual(parsed.desktops, [3: Shortcut(keyCode: 20, modifiers: 262144)])

        let snap = Spaces.parse([display("D1", current: "b", ["a", "b"], from: 1)])
        XCTAssertNil(Spaces.plan(to: snap.desktop(uuid: "a")!, in: snap, shortcuts: parsed))

        // Enabled with no key data (how macOS stores untouched defaults) means the default keys.
        let bare = SpaceShortcuts.parse(["79": ["enabled": true], "81": ["enabled": 1], "118": ["enabled": true]])
        XCTAssertEqual(bare.left, Shortcut(keyCode: 123, modifiers: arrows))
        XCTAssertEqual(bare.right, Shortcut(keyCode: 124, modifiers: arrows))
        XCTAssertEqual(bare.desktops[1], Shortcut(keyCode: 18, modifiers: ctrl))
    }
}

final class NameTransitionTests: XCTestCase {
    // T-28
    func testLoadAndClamp() {
        XCTAssertEqual(NameTransition.load("zoom"), .zoom)
        XCTAssertEqual(NameTransition.load("wobble"), .fade)
        XCTAssertEqual(NameTransition.load(nil), .fade)
        XCTAssertEqual(NameTransition.clampDuration(0), NameTransition.defaultDuration)
        XCTAssertEqual(NameTransition.clampDuration(0.5), 0.5)
        XCTAssertEqual(NameTransition.clampDuration(5), NameTransition.defaultDuration)
    }
}
