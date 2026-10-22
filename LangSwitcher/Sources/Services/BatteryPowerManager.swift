import Foundation
import Combine
import AppKit

// MARK: - Battery Power Manager
// Manages adaptive GPU and CPU throttling, dynamic debounce adjustments, and
// lightweight eco-model selection when running on MacBook battery or Low Power Mode.

@MainActor
final class BatteryPowerManager: ObservableObject {

    static let shared = BatteryPowerManager()

    @Published private(set) var isLowPowerModeActive: Bool = false
    @Published private(set) var isEffectiveEcoActive: Bool = false

    private var cancellables = Set<AnyCancellable>()

    // Test overrides
    var batteryStateOverride: Bool?
    var lowPowerModeOverride: Bool?

    init() {
        self.isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
        updateEffectiveState()

        // Observe Low Power Mode toggles
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateDidChange),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )

        // Observe PowerService changes
        PowerService.shared.$isOnBattery
            .sink { [weak self] _ in
                self?.updateEffectiveState()
            }
            .store(in: &cancellables)
    }

    @objc private func powerStateDidChange() {
        self.isLowPowerModeActive = ProcessInfo.processInfo.isLowPowerModeEnabled
        updateEffectiveState()
    }

    func updateEffectiveState() {
        let onBattery = batteryStateOverride ?? PowerService.shared.isOnBattery
        let lowPower = lowPowerModeOverride ?? isLowPowerModeActive
        let policy = SettingsManager.shared.aiBatteryPolicy
        let enabled = SettingsManager.shared.aiBatteryModeEnabled

        if enabled && (onBattery || lowPower) && (policy == .adaptiveEco || policy == .throttleOnly) {
            self.isEffectiveEcoActive = true
        } else {
            self.isEffectiveEcoActive = false
        }
    }

    // MARK: - Adaptive Debounce Calculation

    /// Computes the effective debounce delay based on battery state and policy.
    /// When on battery or Low Power Mode, debounce increases from 150ms to 350ms to reduce Metal GPU usage by ~60%.
    func effectiveDebounceDelay(
        baseDelay: Double,
        isOnBattery: Bool? = nil,
        isLowPower: Bool? = nil,
        policy: BatteryPowerPolicy? = nil
    ) -> Double {
        let onBattery = isOnBattery ?? (batteryStateOverride ?? PowerService.shared.isOnBattery)
        let lowPower = isLowPower ?? (lowPowerModeOverride ?? isLowPowerModeActive)
        let activePolicy = policy ?? SettingsManager.shared.aiBatteryPolicy
        let enabled = SettingsManager.shared.aiBatteryModeEnabled

        guard enabled else { return baseDelay }

        // If system Low Power Mode is on, always throttle
        if lowPower {
            return max(baseDelay, 0.350)
        }

        guard onBattery else { return baseDelay }

        switch activePolicy {
        case .adaptiveEco, .throttleOnly:
            return max(baseDelay, 0.350)
        case .pauseInference, .unrestricted:
            return baseDelay
        }
    }

    // MARK: - Adaptive Model Selection

    /// Checks whether an ultra-compact eco model should be preferred on battery power.
    func shouldUseEcoModel(
        currentModel: RecommendedAIModel,
        isOnBattery: Bool? = nil,
        policy: BatteryPowerPolicy? = nil
    ) -> Bool {
        let onBattery = isOnBattery ?? (batteryStateOverride ?? PowerService.shared.isOnBattery)
        let activePolicy = policy ?? SettingsManager.shared.aiBatteryPolicy
        let enabled = SettingsManager.shared.aiBatteryModeEnabled

        guard enabled && onBattery else { return false }
        guard activePolicy == .adaptiveEco else { return false }

        // If standard model is already the lightest (0.5B), no need to downgrade
        if currentModel.id == "qwen2.5-0.5b" {
            return false
        }
        return true
    }

    /// Returns the active model, seamlessly falling back to a compact 0.5B model on battery if downloaded.
    func effectiveModel(standardModel: RecommendedAIModel) -> RecommendedAIModel {
        guard shouldUseEcoModel(currentModel: standardModel) else {
            return standardModel
        }

        // Look for downloaded eco model (qwen2.5-0.5b)
        if let ecoModel = RecommendedAIModel.allModels.first(where: { $0.id == "qwen2.5-0.5b" }),
           AIModelManager.shared.isDownloaded(model: ecoModel) {
            return ecoModel
        }

        return standardModel
    }

    // MARK: - Status Presentation

    func statusDescription(l10n: LocalizationManager) -> String {
        let onBattery = batteryStateOverride ?? PowerService.shared.isOnBattery
        let lowPower = lowPowerModeOverride ?? isLowPowerModeActive
        let policy = SettingsManager.shared.aiBatteryPolicy

        if lowPower {
            return l10n.t("ai.battery.status.lowPowerMode")
        }

        if onBattery {
            switch policy {
            case .adaptiveEco:
                return l10n.t("ai.battery.status.batteryEco")
            case .throttleOnly:
                return l10n.t("ai.battery.status.batteryThrottled")
            case .pauseInference:
                return l10n.t("ai.battery.status.batteryPaused")
            case .unrestricted:
                return l10n.t("ai.battery.status.batteryUnrestricted")
            }
        } else {
            return l10n.t("ai.battery.status.acPower")
        }
    }
}
