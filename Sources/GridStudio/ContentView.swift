import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(Controller.self) private var c
    @State private var showMonitor = true
    @State private var importing = false
    @State private var exporting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            main
            Divider()
            CreditFooter()
        }
    }

    private var main: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                GridSurface()
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showMonitor {
                    Divider()
                    MonitorView().frame(height: 190)
                }
            }
            .background(Theme.canvas)
            Divider()
            InspectorView()
                .frame(width: 330)
        }
        .frame(minWidth: 1000, minHeight: 620)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                StatusPill(connected: c.info.connected, midiOK: c.midiOK, id: c.info.id)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { c.panic() } label: { Label("All Notes Off", systemImage: "exclamationmark.octagon") }
                    .help("Send All Notes Off on every channel (⌘.)")
                Button { importing = true } label: { Label("Open Mapping", systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Load a saved mapping (⌘O)")
                Button { exporting = true } label: { Label("Save Mapping", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Save this mapping to a file (⌘S)")
                Button { withAnimation(.snappy) { showMonitor.toggle() } } label: {
                    Label("MIDI Monitor", systemImage: "waveform.path.ecg")
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .help("Show or hide the MIDI monitor (⇧⌘M)")
            }
        }
        .navigationTitle("Grid Studio")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            if case let .success(url) = r {
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                do { try c.importProfile(from: url) } catch { self.error = "That file is not a Grid Studio mapping." }
            }
        }
        .fileExporter(isPresented: $exporting, document: ProfileDoc(profile: c.profile),
                      contentType: .json, defaultFilename: "Grid Mapping.json") { _ in }
        .alert("Could not open the mapping", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct CreditFooter: View {
    var body: some View {
        Text("Powered by AGsoundtrax LLC / Adi Goldstein  ·  Copyright © 2026")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(.bar)
            .accessibilityLabel("Powered by AGsoundtrax LLC, Adi Goldstein. Copyright 2026")
    }
}

struct ProfileDoc: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var profile: Profile
    init(profile: Profile) { self.profile = profile }
    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        profile = try JSONDecoder().decode(Profile.self, from: d)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try e.encode(profile))
    }
}

struct StatusPill: View {
    let connected: Bool
    let midiOK: Bool
    let id: String

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(connected ? Theme.ok : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                    .shadow(color: connected ? Theme.ok.opacity(0.8) : .clear, radius: 4)
                Text(connected ? (id.isEmpty ? "Grid connected" : id) : "Looking for grid…")
            }
            HStack(spacing: 6) {
                Circle().fill(midiOK ? Theme.ok : .red).frame(width: 8, height: 8)
                Text(midiOK ? "MIDI: Grid Studio" : "MIDI unavailable")
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 10).padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

enum Theme {
    static let canvas = Color(nsColor: .underPageBackgroundColor)
    static let ok = Color(red: 0.32, green: 0.82, blue: 0.48)
    // Warm white, like the grid's LEDs.
    static let led = Color(red: 1.0, green: 0.93, blue: 0.80)
    static let accent = Color.accentColor
}
