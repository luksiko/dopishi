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
    }

    /// Triggers an interactive update check with user-facing dialogs
    func checkForUpdates() {
        guard let controller = updaterController, controller.updater.canCheckForUpdates else {
            return
        }
        controller.checkForUpdates(nil)
    }
}
