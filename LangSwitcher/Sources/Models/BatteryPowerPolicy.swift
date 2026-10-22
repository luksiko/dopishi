import Foundation

// MARK: - Battery Power Policy
// Determines adaptive performance, debounce, and model selection on battery power.

public enum BatteryPowerPolicy: String, CaseIterable, Identifiable {
    case adaptiveEco = "adaptiveEco"
    case throttleOnly = "throttleOnly"
    case pauseInference = "pauseInference"
    case unrestricted = "unrestricted"

    public var id: String { rawValue }

    @MainActor
    public var displayName: String {
        switch self {
        case .adaptiveEco:
            return LocalizationManager.shared.t("ai.battery.policy.adaptiveEco")
        case .throttleOnly:
            return LocalizationManager.shared.t("ai.battery.policy.throttleOnly")
        case .pauseInference:
            return LocalizationManager.shared.t("ai.battery.policy.pauseInference")
        case .unrestricted:
            return LocalizationManager.shared.t("ai.battery.policy.unrestricted")
        }
    }

    @MainActor
    public var description: String {
        switch self {
        case .adaptiveEco:
            return LocalizationManager.shared.t("ai.battery.policy.adaptiveEco.desc")
        case .throttleOnly:
            return LocalizationManager.shared.t("ai.battery.policy.throttleOnly.desc")
        case .pauseInference:
            return LocalizationManager.shared.t("ai.battery.policy.pauseInference.desc")
        case .unrestricted:
            return LocalizationManager.shared.t("ai.battery.policy.unrestricted.desc")
        }
    }
}
