// The on-screen grid: mirrors the hardware LEDs live, and every pad can be
// clicked (plays it, like the hardware) or selected for editing.
import SwiftUI

struct GridSurface: View {
    @Environment(Controller.self) private var c
    @State private var mouseDown: Int?

    var body: some View {
        let cols = c.cols, rows = c.rows
        GeometryReader { geo in
            let gap: CGFloat = 8
            let side = min((geo.size.width - 48 - gap * CGFloat(cols - 1)) / CGFloat(cols),
                           (geo.size.height - 48 - gap * CGFloat(rows - 1)) / CGFloat(rows))
            let pad = max(18, side)
            VStack(spacing: gap) {
                ForEach(0..<rows, id: \.self) { y in
                    HStack(spacing: gap) {
                        ForEach(0..<cols, id: \.self) { x in
                            let i = y * cols + x
                            PadView(index: i, size: pad,
                                    level: i < c.leds.count ? c.leds[i] : 0,
                                    label: c.label(i),
                                    selected: c.selected == i,
                                    edited: c.isOverridden(i))
                                .gesture(DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        if mouseDown != i { mouseDown = i; c.press(i, down: true) }
                                    }
                                    .onEnded { _ in
                                        c.press(i, down: false); mouseDown = nil
                                    })
                        }
                    }
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.13)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if !c.info.connected {
                    Label("Plug in your grid. You can still click the pads to test the MIDI.", systemImage: "cable.connector")
                        .font(.callout).foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .offset(y: 24)
                }
            }
        }
    }
}

struct PadView: View {
    let index: Int
    let size: CGFloat
    let level: UInt8
    let label: String
    let selected: Bool
    let edited: Bool

    var body: some View {
        let t = Double(level) / 15
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(Color(white: 0.09))
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .fill(Theme.led.opacity(t == 0 ? 0 : 0.10 + 0.90 * t))
                .shadow(color: Theme.led.opacity(t * 0.7), radius: size * 0.25 * t)
            RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                .strokeBorder(selected ? Theme.accent : Color.white.opacity(0.06), lineWidth: selected ? 2.5 : 1)
            if size > 34, !label.isEmpty {
                Text(label)
                    .font(.system(size: max(8, size * 0.2), weight: .semibold, design: .rounded))
                    .foregroundStyle(t > 0.55 ? Color.black.opacity(0.7) : Color.white.opacity(0.45))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(3)
            }
            if edited {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(5)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.08), value: level)
        .contentShape(Rectangle())
        .accessibilityLabel("Pad \(index % 16 + 1), row \(index / 16 + 1), \(label)")
        .accessibilityAddTraits(.isButton)
    }
}
