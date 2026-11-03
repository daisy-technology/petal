/// How the Desktop's name comes in front of the windows (Mission Control, or a preview).
public enum NameTransition: String, CaseIterable, Identifiable, Sendable {
    case fade, zoom, slide, none

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    public static let durations: ClosedRange<Double> = 0.1...1.0
    public static let defaultDuration = 0.35

    /// A stored value, or Fade when it's missing or unknown.
    public static func load(_ raw: String?) -> NameTransition {
        raw.flatMap(NameTransition.init(rawValue:)) ?? .fade
    }

    /// A stored duration, or the default when it's missing (0) or out of range.
    public static func clampDuration(_ value: Double) -> Double {
        durations.contains(value) ? value : defaultDuration
    }
}
