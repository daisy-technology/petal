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
    static func flower(_ swatch: Swatch?) -> NSImage {
        var config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        if let swatch { config = config.applying(.init(paletteColors: [swatch.nsColor])) }
        let image = NSImage(systemSymbolName: "camera.macro", accessibilityDescription: "Petal")!
            .withSymbolConfiguration(config)!
        image.isTemplate = swatch == nil
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
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var swatch: Swatch? { model.labels.color(for: desktop.uuid) }
    private var name: String { model.labels.name(for: desktop) }
    private var isCurrent: Bool { model.snapshot.current[desktop.display] == desktop.uuid }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { picking.toggle() } label: { dot }
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
                                .overlay(Circle().strokeBorder(.primary.opacity(swatch == option ? 0.9 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.rawValue.capitalized)
                        .accessibilityAddTraits(swatch == option ? .isSelected : [])
                    }
                }
                .padding(.leading, 22)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(hovering || editing ? 0.07 : 0)))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: picking)
    }

    private var dot: some View {
        Group {
            if let swatch {
                Circle().fill(swatch.color)
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
