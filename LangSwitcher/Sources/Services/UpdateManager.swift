import Foundation
import Sparkle

/// Manages application updates via Sparkle 2 framework.
@MainActor
final class UpdateManager: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateManager()

    @Published private(set) var canCheckForUpdates: Bool = false
    @Published var automaticallyChecksForUpdates: Bool = true {
        didSet {
            updaterController?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            if !automaticallyChecksForUpdates {
                automaticallyDownloadsUpdates = false
            }
        }
    }
    @Published var automaticallyDownloadsUpdates: Bool = true {
        didSet {
            updaterController?.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    private(set) var updaterController: SPUStandardUpdaterController?

    override init() {
        super.init()
        setupUpdater()
    }

    private func setupUpdater() {
        // Only start updater in real app runtime with valid feed configuration
        guard Bundle.main.bundleIdentifier == "com.dopishi.app" ||
              Bundle.main.infoDictionary?["SUFeedURL"] != nil else {
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        self.updaterController = controller
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
    }

    /// Refreshes current updater settings from Sparkle
    func refreshStatus() {
        guard let controller = updaterController else { return }
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
    }

    /// Triggers an interactive update check with user-facing dialogs
    func checkForUpdates() {
        guard let controller = updaterController, controller.updater.canCheckForUpdates else {
            return
        }
        controller.checkForUpdates(nil)
    }
}
