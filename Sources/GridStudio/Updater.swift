// Auto updates through Sparkle (https://sparkle-project.org).
// On every launch the app reads appcast.xml from the GitHub repo. When a newer signed
// version is listed there, the user gets the standard "update available" window, or it
// installs silently if they turned on automatic installs.
// Every update must carry an EdDSA signature that matches SUPublicEDKey in Info.plist,
// so nobody but the key holder can push an update.
import Foundation
import Sparkle

@MainActor
final class Updater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published var canCheck = false
    @Published var automaticInstall: Bool {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticInstall }
    }

    /// Sparkle only works from a bundled, signed app (not from `swift run`).
    static var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" &&
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: Self.isBundled, updaterDelegate: nil, userDriverDelegate: nil)
        automaticInstall = controller.updater.automaticallyDownloadsUpdates
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
    }

    /// Called once at launch: look for a new version right away.
    func checkOnLaunch() {
        guard Self.isBundled, !CommandLine.arguments.contains("--snapshot") else { return }
        controller.updater.checkForUpdatesInBackground()
    }

    func checkNow() { controller.checkForUpdates(nil) }

    var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }
}
