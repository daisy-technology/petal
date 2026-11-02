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
