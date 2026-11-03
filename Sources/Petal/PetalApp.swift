import AppKit
import PetalCore
import SwiftUI

@main
struct PetalApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(nsImage: Self.flower(model.activeColor))
            Text(model.title)
        }
        .menuBarExtraStyle(.window)
    }

    /// The flower takes the Desktop's color; with no color it follows the menu bar like any template icon.
    static func flower(_ tint: Tint?) -> NSImage {
        var config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let tint { config = config.applying(.init(paletteColors: [tint.nsColor])) }
        let image = NSImage(systemSymbolName: "camera.macro", accessibilityDescription: "Petal")!
            .withSymbolConfiguration(config)!
        image.isTemplate = tint == nil
        return image
    }
}

enum Metrics {
    static let rowHeight: CGFloat = 30
    static let inset: CGFloat = 8
    /// Critically damped: rows settle without bouncing (apple-design default).
    static let spring = Animation.spring(response: 0.3, dampingFraction: 1)
}

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var picking: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.displays.enumerated()), id: \.element.id) { index, display in
                if model.displays.count > 1 {
                    Text("Display \(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Metrics.inset)
                        .padding(.top, index == 0 ? 4 : 12)
                        .padding(.bottom, 4)
                }
                DesktopList(model: model, desktops: display.desktops, picking: $picking) { desktop in
                    if model.switchTo(desktop) { dismiss() }
                }
            }
            if model.snapshot.desktops.isEmpty {
                Text("Couldn’t read your Desktops.")
                    .foregroundStyle(.secondary)
                    .padding(Metrics.inset)
            }

            if model.needsAccessibility {
                Notice(text: "Petal needs Accessibility access to switch Desktops. Turn on Petal in Settings, then click again.",
                       action: "Open Accessibility Settings", perform: Switcher.openAccessibilitySettings)
            } else if model.shortcutOff {
                Notice(text: "Turn on “Move left a space” and “Move right a space” in Keyboard Shortcuts → Mission Control.",
                       action: "Open Keyboard Settings", perform: Switcher.openKeyboardShortcuts)
            }

            Divider().padding(.vertical, 6)

            SettingRow(title: "Show name on desktop", isOn: $model.showName)
            if model.showName {
                HStack(spacing: 8) {
                    Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                    Slider(value: $model.nameSize, in: NameOverlay.sizes) { editing in
                        model.previewName(editing)
                    }
                    .controlSize(.mini)
                    .accessibilityLabel("Name size")
                    Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
                }
                .frame(height: Metrics.rowHeight - 4)
                .padding(.horizontal, Metrics.inset)
                .help("Name size. Hold the slider to preview it over your windows.")

                SettingRow(title: "Show name while ⌘-Tab", isOn: $model.nameInAppSwitcher)
                    .help("Off: the name comes over your windows only in Mission Control.")

                HStack {
                    Text("Transition")
                    Spacer()
                    Picker("Transition", selection: $model.nameTransition) {
                        ForEach(NameTransition.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
                .frame(height: Metrics.rowHeight - 4)
                .padding(.horizontal, Metrics.inset)
                .onChange(of: model.nameTransition) { _, _ in model.playTransitionPreview() }

                if model.nameTransition != .none {
                    HStack(spacing: 8) {
                        Text("Duration")
                        Slider(value: $model.nameTransitionDuration, in: NameTransition.durations, step: 0.05) { editing in
                            if !editing { model.playTransitionPreview() }
                        }
                        .controlSize(.mini)
                        .accessibilityLabel("Transition duration")
                        Text(String(format: "%.2f s", model.nameTransitionDuration))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: Metrics.rowHeight - 4)
                    .padding(.horizontal, Metrics.inset)
                }
            }
            SettingRow(title: "Show color edge", isOn: $model.showEdge)
            SettingRow(title: "Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }))

            Divider().padding(.vertical, 6)

            Text("Click to switch, double-click to rename, hold to reorder.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Metrics.inset)
                .padding(.bottom, 4)
            MenuButton(title: "Quit Petal", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(6)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
        .background(FitWindow())
        .onAppear {
            model.refresh()
            model.recheckAccess()
        }
    }
}

/// One display's Desktops. Press and hold a row to lift it, drag, release to drop.
struct DesktopList: View {
    @ObservedObject var model: AppModel
    let desktops: [Desktop]
    @Binding var picking: String?
    let onSwitch: (Desktop) -> Void

    @State private var dragging: String?
    @State private var offset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var from: Int? { desktops.firstIndex { $0.uuid == dragging } }
    private var target: Int? {
        from.map { min(max($0 + Int((offset / Metrics.rowHeight).rounded()), 0), desktops.count - 1) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(desktops.enumerated()), id: \.element.uuid) { index, desktop in
                let lifted = dragging == desktop.uuid
                DesktopRow(
                    model: model,
                    desktop: desktop,
                    lifted: lifted,
                    picking: Binding(
                        get: { picking == desktop.uuid },
                        set: { picking = $0 ? desktop.uuid : nil }),
                    onSwitch: { onSwitch(desktop) },
                    onLift: {
                        picking = nil
                        withAnimation(reduceMotion ? nil : Metrics.spring) { dragging = desktop.uuid }
                    },
                    onDrag: { offset = $0 },
                    onDrop: { drop(desktop) })
                .offset(y: shift(index, lifted: lifted))
                .zIndex(lifted ? 1 : 0)
                .animation(lifted || reduceMotion ? nil : Metrics.spring, value: target)
            }
        }
    }

    /// The lifted row follows the pointer 1:1; the rows it passes slide one row the other way.
    private func shift(_ index: Int, lifted: Bool) -> CGFloat {
        guard let from, let target else { return 0 }
        if lifted { return offset }
        if from < target, index > from, index <= target { return -Metrics.rowHeight }
        if target < from, index >= target, index < from { return Metrics.rowHeight }
        return 0
    }

    private func drop(_ desktop: Desktop) {
        let destination = target ?? 0
        withAnimation(reduceMotion ? nil : Metrics.spring) {
            model.move(desktop, to: destination)
            dragging = nil
            offset = 0
        }
    }
}

struct DesktopRow: View {
    @ObservedObject var model: AppModel
    let desktop: Desktop
    let lifted: Bool
    @Binding var picking: Bool
    let onSwitch: () -> Void
    let onLift: () -> Void
    let onDrag: (CGFloat) -> Void
    let onDrop: () -> Void

    @State private var editing = false
    @State private var customOpen = false
    @State private var hue = 0.0
    @State private var hovering = false
    @State private var pressed = false
    @State private var suppressTap = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Tint? { model.labels.color(for: desktop.uuid) }
    private var name: String { model.labels.name(for: desktop) }
    private var isCurrent: Bool { model.snapshot.current[desktop.display] == desktop.uuid }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    picking.toggle()
                    if !picking { customOpen = false }
                } label: { dot }
                    .buttonStyle(.plain)
                    .help("Choose a color")
                    .accessibilityLabel("Color for \(name)")

                if editing {
                    TextField(desktop.defaultName, text: $draft)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit(commit)
                        .onExitCommand { editing = false }
                        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                } else {
                    Text(name)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isCurrent && !editing {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Current Desktop")
                }
            }
            .frame(height: Metrics.rowHeight - 4)
            .padding(.horizontal, Metrics.inset)
            .background(RoundedRectangle(cornerRadius: 6).fill(highlight))
            .contentShape(Rectangle())
            .gesture(editing ? nil : taps)
            .simultaneousGesture(editing ? nil : pressTracking)
            .simultaneousGesture(editing ? nil : reorder)
            .onHover { hovering = $0 }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Switches to this Desktop")
            .accessibilityAction(named: "Rename", beginEditing)

            if picking { swatches }
        }
        .scaleEffect(lifted ? 1.03 : 1)
        .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: 8, y: 3)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: picking)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: customOpen)
    }

    private var highlight: Color {
        if lifted { return Color(nsColor: .controlBackgroundColor) }
        if pressed { return .primary.opacity(0.12) }
        return .primary.opacity(hovering || editing ? 0.07 : 0)
    }

    // MARK: Gestures

    /// Double-click renames; a single click switches once the double-click window has passed.
    private var taps: some Gesture {
        TapGesture(count: 2).onEnded(beginEditing)
            .exclusively(before: TapGesture().onEnded {
                if suppressTap { return }
                onSwitch()
            })
    }

    /// Highlights the row the moment it's pressed, before the click is decided.
    private var pressTracking: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded { _ in pressed = false }
    }

    private var reorder: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .first(true):
                    break
                case .second(true, let drag):
                    if !suppressTap {
                        suppressTap = true
                        onLift()
                    }
                    onDrag(drag?.translation.height ?? 0)
                default:
                    break
                }
            }
            .onEnded { _ in
                guard suppressTap else { return }
                onDrop()
                // The release can still look like a click; ignore it until the double-click window ends.
                DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval + 0.1) { suppressTap = false }
            }
    }

    // MARK: Colors

    private var swatches: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Button { model.clearColor(desktop) } label: {
                    Circle()
                        .strokeBorder(.secondary, lineWidth: 1.5)
                        .overlay(Rectangle().fill(.secondary).frame(width: 1.5).rotationEffect(.degrees(45)))
                        .clipShape(Circle())
                        .frame(width: 16, height: 16)
                        .overlay(selectionRing(tint == nil))
                }
                .buttonStyle(.plain)
                .help("No color")
                .accessibilityLabel("No color")
                .accessibilityAddTraits(tint == nil ? .isSelected : [])

                ForEach(Swatch.allCases) { option in
                    Button { model.toggleColor(desktop, option) } label: {
                        Circle()
                            .fill(option.color)
                            .frame(width: 16, height: 16)
                            .overlay(selectionRing(tint == .swatch(option)))
                    }
                    .buttonStyle(.plain)
                    .help(option.rawValue.capitalized)
                    .accessibilityLabel(option.rawValue.capitalized)
                    .accessibilityAddTraits(tint == .swatch(option) ? .isSelected : [])
                }

                Button {
                    hue = tint?.hue ?? hue
                    customOpen.toggle()
                } label: {
                    Circle()
                        .fill(AngularGradient(colors: Self.rainbow, center: .center))
                        .frame(width: 16, height: 16)
                        .overlay(selectionRing(isCustom))
                }
                .buttonStyle(.plain)
                .help("Custom color")
                .accessibilityLabel("Custom color")
                .accessibilityAddTraits(isCustom ? .isSelected : [])
            }

            if customOpen {
                HueStrip(hue: hue) { newHue in
                    hue = newHue
                    model.setCustomColor(desktop, hue: newHue)
                }
                .padding(.trailing, 4)
                .transition(.opacity)
            }
        }
        .padding(.leading, Metrics.inset + 28)
        .padding(.bottom, 6)
        .transition(.opacity)
    }

    private func selectionRing(_ selected: Bool) -> some View {
        Circle().strokeBorder(.primary.opacity(selected ? 0.9 : 0), lineWidth: 2).padding(-3)
    }

    static let rainbow = stride(from: 0.0, through: 1.0, by: 1.0 / 6).map {
        Color(hue: $0, saturation: Tint.stripSaturation, brightness: Tint.stripBrightness)
    }

    private var isCustom: Bool {
        if case .custom = tint { return true }
        return false
    }

    private var dot: some View {
        Group {
            if let tint {
                Circle().fill(tint.color)
            } else {
                Circle().strokeBorder(.secondary, lineWidth: 1.5)
            }
        }
        .frame(width: 12, height: 12)
        .frame(width: 18, height: 18)
        .contentShape(Rectangle())
    }

    // MARK: Rename

    private func beginEditing() {
        draft = model.labels.all[desktop.uuid]?.name ?? ""
        editing = true
        focused = true
        // Select the old name so typing replaces it.
        DispatchQueue.main.async { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
    }

    private func commit() {
        guard editing else { return }
        model.rename(desktop, to: draft)
        editing = false
    }
}

/// MenuBarExtra grows its window when the menu gets taller but never shrinks it,
/// which leaves a see-through band above the rows. This sizes the window to the
/// menu every time the menu's height changes, keeping the top edge under the menu bar.
struct FitWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            DispatchQueue.main.async { [weak self] in self?.fit() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            fit()
        }

        private func fit() {
            guard let window, let content = window.contentView else { return }
            let height = frame.height
            guard height > 0, abs(content.frame.height - height) > 0.5 else { return }
            var rect = window.frame
            rect.origin.y += rect.height - height
            rect.size.height = height
            window.setFrame(rect, display: true)
        }
    }
}

struct SettingRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .frame(height: Metrics.rowHeight - 4)
        .padding(.horizontal, Metrics.inset)
    }
}

struct MenuButton: View {
    let title: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(shortcut).foregroundStyle(.secondary)
            }
            .frame(height: Metrics.rowHeight - 4)
            .padding(.horizontal, Metrics.inset)
            .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(hovering ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct Notice: View {
    let text: String
    let action: String
    let perform: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Button(action, action: perform)
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.14)))
        .padding(.top, 6)
    }
}

/// A strip of hues you drag along to pick any color. It responds on press,
/// not release, and keeps following the pointer while it moves.
struct HueStrip: View {
    let hue: Double
    let onChange: (Double) -> Void

    private let knob: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let track = max(geo.size.width - knob, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: DesktopRow.rainbow, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 10)
                Circle()
                    .fill(Color(hue: hue, saturation: Tint.stripSaturation, brightness: Tint.stripBrightness))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: knob, height: knob)
                    .offset(x: hue * track)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(min(max((drag.location.x - knob / 2) / track, 0), 1))
            })
        }
        .frame(height: knob)
        .accessibilityElement()
        .accessibilityLabel("Custom color")
        .accessibilityValue("Hue \(Int(hue * 360)) degrees")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1.0 / 24 : -1.0 / 24
            onChange(min(max(hue + step, 0), 1))
        }
    }
}
