// Right panel: the layout, the selected pad's mapping, and the LED settings.
import SwiftUI

struct InspectorView: View {
    @Environment(Controller.self) private var c

    var body: some View {
        @Bindable var c = c
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Section("Layout") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Layout.allCases) { l in
                            LayoutCard(layout: l, selected: c.profile.layout == l) { c.profile.choose(l) }
                        }
                    }
                    Text(c.profile.layout.detail).font(.caption).foregroundStyle(.secondary)

                    switch c.profile.layout {
                    case .chromatic, .isomorphic, .drums:
                        NumberRow(title: "Lowest note", value: $c.profile.baseNote, range: 0...127,
                                  suffix: noteName(c.profile.baseNote))
                        if c.profile.layout == .isomorphic {
                            NumberRow(title: "Row step", value: $c.profile.rowOffset, range: 1...12,
                                      suffix: c.profile.rowOffset == 5 ? "fourths" : c.profile.rowOffset == 7 ? "fifths" : "semitones")
                        }
                        NumberRow(title: "Velocity", value: $c.profile.velocity, range: 1...127)
                    case .faders:
                        NumberRow(title: "First CC", value: $c.profile.ccBase, range: 0...112)
                    case .toggles:
                        EmptyView()
                    }
                    NumberRow(title: "MIDI channel", value: $c.profile.channel, range: 1...16)
                }

                Section("Selected pad") {
                    if let i = c.selected, i < c.cols * c.rows {
                        PadEditor(index: i)
                    } else {
                        Text("Click a pad here, or press one on the grid, to edit what it sends.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                Section("Lights") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pads light up from").font(.callout)
                        Picker("Pads light up from", selection: $c.profile.ledMode) {
                            ForEach(LEDMode.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented).labelsHidden()
                        Text("“From DAW”: notes and CCs sent to the “Grid Studio LEDs” MIDI port light the matching pads.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    SliderRow(title: "Resting glow", value: $c.profile.idleGlow, range: 0...8)
                    SliderRow(title: "Brightness", value: $c.profile.brightness, range: 1...15)
                    Toggle("Rotate grid 180° (cable on the left)", isOn: $c.profile.rotate)
                }

                Section("Updates") { UpdatesPanel() }
            }
            .padding(18)
        }
        .background(.background)
    }
}

private struct UpdatesPanel: View {
    @EnvironmentObject private var updater: Updater
    var body: some View {
        HStack {
            Text("Version \(updater.version)").font(.callout)
            Spacer()
            Button("Check Now") { updater.checkNow() }.controlSize(.small).disabled(!updater.canCheck)
        }
        Toggle("Install updates automatically", isOn: $updater.automaticInstall)
        Text("Grid Studio looks for a new version every time it opens.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
            content
        }
    }
}

private struct LayoutCard: View {
    let layout: Layout
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: layout.symbol).frame(width: 18)
                Text(layout.title).font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.18) : Color.primary.opacity(hover ? 0.08 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(layout.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PadEditor: View {
    @Environment(Controller.self) private var c
    let index: Int

    var body: some View {
        let p = c.pad(index)
        let set: (Pad) -> Void = { c.setPad(index, $0) }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Column \(index % c.cols + 1), row \(index / c.cols + 1)").font(.headline)
                Spacer()
                if c.isOverridden(index) {
                    Button("Reset") { c.resetPad(index) }.controlSize(.small)
                        .help("Go back to what the layout gives this pad")
                }
            }
            ThemedDropdown(title: "Sends", options: PadKind.allCases, selection: p.kind,
                           label: { $0.title }, detail: { $0.detail }) { k in
                var n = p; n.kind = k
                if k == .ccToggle || k == .cc || k == .fader { n.value = 127 }
                set(n)
            }
            if p.kind != .off {
                NumberRow(title: p.kind.isNote ? "Note" : "CC number",
                          value: Binding(get: { p.number }, set: { var n = p; n.number = $0; set(n) }),
                          range: 0...127, suffix: p.kind.isNote ? noteName(p.number) : nil)
                if p.kind != .fader {
                    NumberRow(title: p.kind.isNote ? "Velocity" : "Value",
                              value: Binding(get: { p.value }, set: { var n = p; n.value = $0; set(n) }),
                              range: 1...127)
                }
                NumberRow(title: "Channel",
                          value: Binding(get: { p.channel }, set: { var n = p; n.channel = $0; set(n) }),
                          range: 1...16)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

struct NumberRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var suffix: String? = nil

    var body: some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            if let suffix { Text(suffix).font(.callout).foregroundStyle(.secondary) }
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .onChange(of: value) { _, v in if !range.contains(v) { value = min(max(v, range.lowerBound), range.upperBound) } }
            Stepper("", value: $value, in: range).labelsHidden()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack {
            Text(title).font(.callout).frame(width: 100, alignment: .leading)
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            Text("\(value)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
        }
    }
}

/// A themed dropdown (a button that opens a styled list), used instead of a plain system menu.
struct ThemedDropdown<T: Hashable & Identifiable>: View {
    let title: String
    let options: [T]
    let selection: T
    let label: (T) -> String
    var detail: ((T) -> String)? = nil
    let onSelect: (T) -> Void
    @State private var open = false

    var body: some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Text(label(selection)).font(.callout.weight(.medium))
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $open, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(options) { o in
                        DropdownRow(text: label(o), detail: detail?(o), selected: o == selection) {
                            onSelect(o); open = false
                        }
                    }
                }
                .padding(6)
                .frame(width: 290)
            }
        }
    }
}

private struct DropdownRow: View {
    let text: String
    let detail: String?
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark").font(.caption.weight(.bold)).opacity(selected ? 1 : 0).padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(text).font(.callout.weight(.medium))
                    if let detail { Text(detail).font(.caption).foregroundStyle(hover ? .white.opacity(0.85) : .secondary) }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(hover ? .white : .primary)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? Theme.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
