import SwiftUI

// MARK: - Autocompletion Popup View
// Floating HUD view showing autocompletion candidates next to the text caret.

struct AutocompletionPopupView: View {
    let candidates: [AutocompletionCandidate]
    let selectedIndex: Int
    let acceptKeyHint: String
    let onSelect: (AutocompletionCandidate) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    HStack(spacing: 8) {
                        // Number shortcut badge (1, 2, 3...)
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(index == selectedIndex ? .white : .secondary)
                            .frame(width: 16, height: 16)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(index == selectedIndex ? Color.accentColor : Color.secondary.opacity(0.15))
                            )
                        
                        // Candidate word
                        Text(candidate.word.trimmingCharacters(in: .whitespaces))
                            .font(.system(size: 13, weight: index == selectedIndex ? .semibold : .regular))
                            .foregroundStyle(index == selectedIndex ? .primary : .secondary)
                        
                        Spacer(minLength: 8)
                        
                        // Screen context badge if applicable
                        if candidate.hasScreenContext {
                            HStack(spacing: 2) {
                                Image(systemName: "bubble.left.fill")
                                    .font(.system(size: 8))
                                Text(LocalizationManager.shared.t("autocompletion.badge.context"))
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundStyle(Color.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        // Cross-layout badge if applicable
                        if candidate.isCrossLayout {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 8))
                                Text(badgeLabel(for: candidate.targetLayoutID))
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(index == selectedIndex ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(candidate)
                    }
                }
            }
            .padding(6)
            
            Divider()
                .opacity(0.4)
            
            // Footer with shortcut hint
            HStack(spacing: 6) {
                Text(acceptKeyHint)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                
                Text(LocalizationManager.shared.t("autocompletion.hint.toAccept"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Esc")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(minWidth: 170, maxWidth: 260)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.regularMaterial)
                )
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func badgeLabel(for layoutID: String) -> String {
        let lower = layoutID.lowercased()
        if lower.contains("russian") || lower.contains(".ru") {
            return "RU"
        } else if lower.contains("ukrainian") || lower.contains(".uk") {
            return "UK"
        } else if lower.contains("polish") || lower.contains(".pl") {
            return "PL"
        } else if lower.contains("german") || lower.contains(".de") {
            return "DE"
        } else if lower.contains("french") || lower.contains(".fr") {
            return "FR"
        } else if lower.contains("spanish") || lower.contains(".es") {
            return "ES"
        } else {
            return "EN"
        }
    }
}
