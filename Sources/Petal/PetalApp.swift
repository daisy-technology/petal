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

struct MenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(model.displays.enumerated()), id: \.element.id) { index, display in
                if model.displays.count > 1 {
                    Text("Display \(index + 1)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, index == 0 ? 2 : 10)
                }
                ForEach(display.desktops) { desktop in
                    DesktopRow(model: model, desktop: desktop)
                }
            }
            if model.snapshot.desktops.isEmpty {
                Text("Couldn’t read your Desktops.")
                    .foregroundStyle(.secondary)
                    .padding(8)
            }

            Divider().padding(.vertical, 6)

            Group {
                Toggle("Show color edge", isOn: $model.showEdge)
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)

            Divider().padding(.vertical, 6)

            HStack {
                Text("Click a name to rename it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
        }
        .padding(8)
        .frame(width: 290)
        .onAppear { model.refresh() }
    }
}

struct DesktopRow: View {
    @ObservedObject var model: AppModel
    let desktop: Desktop

    @State private var editing = false
    @State private var picking = false
    @State private var customOpen = false
    @State private var hue = 0.0
    @State private var hovering = false
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
                        .contentShape(Rectangle())
                        .onTapGesture(perform: beginEditing)
                        .help("Click to rename")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Renames this Desktop")
                }

                if isCurrent {
                    Text("Now")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if picking {
                HStack(spacing: 8) {
                    ForEach(Swatch.allCases) { option in
                        Button { model.toggleColor(desktop, option) } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(.primary.opacity(tint == .swatch(option) ? 0.9 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
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
                            .overlay(Circle().strokeBorder(.primary.opacity(isCustom ? 0.9 : 0), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help("Custom color")
                    .accessibilityLabel("Custom color")
                    .accessibilityAddTraits(isCustom ? .isSelected : [])
                }
                .padding(.leading, 22)
                .transition(.opacity)

                if customOpen {
                    HueStrip(hue: hue) { newHue in
                        hue = newHue
                        model.setCustomColor(desktop, hue: newHue)
                    }
                    .padding(.leading, 22)
                    .padding(.trailing, 4)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(hovering || editing ? 0.07 : 0)))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: picking)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: customOpen)
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

    private func beginEditing() {
        draft = model.labels.all[desktop.uuid]?.name ?? ""
        editing = true
        focused = true
    }

    private func commit() {
        guard editing else { return }
        model.rename(desktop, to: draft)
        editing = false
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
