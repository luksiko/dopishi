import Foundation
import SwiftUI

// MARK: - Autocompletion Display Mode
// Controls whether completion suggestions are shown as a floating HUD menu,
// inline ghost text at the caret, or both.

enum AutocompletionDisplayMode: Int, CaseIterable, Identifiable, Codable {
    case popup = 0        // Classic floating popup menu
    case ghostText = 1    // Inline semi-transparent ghost text tail
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
        case .popup: return "popup"
        case .ghostText: return "ghostText"
        case .both: return "both"
        }
    }
}
