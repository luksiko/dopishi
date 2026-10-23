import Foundation
import SwiftUI

// MARK: - Autocompletion Display Mode
// Controls whether completion suggestions are shown as inline ghost text at the caret,
// a floating HUD menu, or both.

enum AutocompletionDisplayMode: Int, CaseIterable, Identifiable, Codable {
    case ghostText = 1    // Inline semi-transparent ghost text tail (default)
    case popup = 0        // Classic floating popup menu
    case both = 2         // Both popup menu and inline ghost text
    
    var id: Int { rawValue }
    
    @MainActor
    var displayName: String {
        LocalizationManager.shared.t("autocompletion.displayMode.\(nameKey)")
    }
    
    @MainActor
    var description: String {
        LocalizationManager.shared.t("autocompletion.displayModeDesc.\(nameKey)")
    }
    
    private var nameKey: String {
        switch self {
        case .ghostText: return "ghostText"
        case .popup: return "popup"
        case .both: return "both"
        }
    }
}
