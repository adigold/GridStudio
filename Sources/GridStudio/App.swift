import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: Controller?

    // Dev aid used to make the README screenshots:
    // `Grid Studio --snapshot out.png [--layout faders] [--select 37] [--demo] [--light]`
    // renders the window to a PNG and quits. It never saves settings.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let out = URL(fileURLWithPath: args[i + 1])
        if args.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
        if args.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
               let v = w.contentView?.superview ?? w.contentView,
               let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: out)
            }
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { controller?.shutdown() } // LEDs off on quit
    }
}

@main
struct GridStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var controller = Controller()
    @StateObject private var updater = Updater()
    @State private var launched = false

    var body: some Scene {
        Window("Grid Studio", id: "main") {
            ContentView()
                .environment(controller)
                .environmentObject(updater)
                .onAppear {
                    delegate.controller = controller
                    if !launched { launched = true; updater.checkOnLaunch() }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkNow() }
                    .disabled(!updater.canCheck)
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Grid") {
                Button("All Notes Off") { controller.panic() }
                    .keyboardShortcut(".", modifiers: .command)
                Button("Reset All Pad Edits") { controller.resetAllPads() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
                Divider()
                Toggle("Rotate Grid 180°", isOn: Binding(
                    get: { controller.profile.rotate }, set: { controller.profile.rotate = $0 }))
                    .keyboardShortcut("r", modifiers: [.command, .option])
            }
        }

        MenuBarExtra {
            MenuBarView().environment(controller).environmentObject(updater)
        } label: {
            Image(systemName: controller.info.connected ? "square.grid.3x3.fill" : "square.grid.3x3")
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarView: View {
    @Environment(Controller.self) private var c
    @EnvironmentObject private var updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusPill(connected: c.info.connected, midiOK: c.midiOK, id: c.info.id)
            Text("Layout: \(c.profile.layout.title)").font(.callout).foregroundStyle(.secondary)
            Divider()
            Button("Open Grid Studio") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("All Notes Off") { c.panic() }
            Button("Check for Updates…") { updater.checkNow() }.disabled(!updater.canCheck)
            Divider()
            Button("Quit Grid Studio") { NSApp.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 240)
    }
}
