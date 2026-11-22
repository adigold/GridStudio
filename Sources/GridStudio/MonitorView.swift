import SwiftUI

struct MonitorView: View {
    @Environment(Controller.self) private var c

    var body: some View {
        @Bindable var c = c
        VStack(spacing: 0) {
            HStack {
                Text("MIDI MONITOR").font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
                Spacer()
                Toggle("Pause", isOn: $c.monitorPaused).toggleStyle(.button).controlSize(.small)
                Button("Clear") { c.monitor.removeAll() }.controlSize(.small)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(c.monitor) { line in
                        HStack(spacing: 10) {
                            Text(line.time, format: .dateTime.hour().minute().second())
                                .foregroundStyle(.tertiary)
                            Image(systemName: line.incoming ? "arrow.down.left" : "arrow.up.right")
                                .foregroundStyle(line.incoming ? Color.orange : Theme.ok)
                                .help(line.incoming ? "From your DAW to the grid" : "From the grid to your DAW")
                            Text(line.text)
                        }
                        .font(.system(size: 11.5, design: .monospaced))
                    }
                    if c.monitor.isEmpty {
                        Text("Press a pad. Everything the grid sends and receives shows up here.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.background)
    }
}
