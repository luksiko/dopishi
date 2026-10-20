import SwiftUI

// MARK: - Recovery Preview
//
// Shows what Thought Recovery made of a line before it is applied: the
// reconstruction, the runner-up readings and every changed span with its
// segment type. This is the "holding the hotkey shows the reconstructed
// preview / 2–3 best reconstructions for ambiguous text" part of the idea
// document, plus the undo that teaches the personal dictionary.

struct RecoveryPreviewView: View {

    @EnvironmentObject var l10n: LocalizationManager

    let plan: ThoughtRecovery.Plan

    var onApply: (String) -> Void
    var onCopy: (String) -> Void
    var onRevert: () -> Void
    var onCancel: () -> Void

    private var options: [String] {
        ([plan.reconstructed] + plan.alternatives).filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("recovery.title"))
                .font(.headline)

            if plan.isChanged {
                Text(l10n.t("recovery.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(l10n.t("recovery.nothingToChange"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            labelledText(l10n.t("recovery.original"), value: plan.original, emphasised: false)

            if plan.isChanged {
                labelledText(l10n.t("recovery.reconstructed"), value: plan.reconstructed, emphasised: true)
            }

            if !plan.alternatives.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.t("recovery.alternatives"))
                        .font(.caption)
                        .bold()
                    ForEach(Array(plan.alternatives.enumerated()), id: \.offset) { index, alternative in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(index + 2).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(alternative)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if !plan.changedSpans.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.t("recovery.changedSpans"))
                        .font(.caption)
                        .bold()
                    ForEach(Array(plan.changedSpans.enumerated()), id: \.offset) { _, span in
                        HStack(spacing: 6) {
                            Text(kindLabel(span.kind))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                            Text("\(span.text) → \(span.chosen.text)")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            if !plan.changedSpans.isEmpty {
                Text(l10n.t("recovery.confidence")
                        .replacingOccurrences(of: "%@", with: String(format: "%.0f%%", plan.confidence * 100)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(spacing: 8) {
                Button(l10n.t("recovery.apply")) {
                    onApply(plan.reconstructed)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!plan.isChanged)

                Button(l10n.t("recovery.copy")) {
                    onCopy(plan.reconstructed)
                }
                .disabled(!plan.isChanged)

                Spacer()

                Button(l10n.t("recovery.revert")) {
                    onRevert()
                }
                .disabled(!plan.isChanged)

                Button(l10n.t("common.cancel")) {
                    onCancel()
                }
            }

            Text(l10n.t("recovery.revertHint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 520)
    }

    private func labelledText(_ label: String, value: String, emphasised: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .bold()
            Text(value)
                .font(.system(emphasised ? .title3 : .body, design: .monospaced))
                .foregroundStyle(emphasised ? .primary : .secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func kindLabel(_ kind: ThoughtRecovery.SpanKind) -> String {
        l10n.t("recovery.kind.\(kind.rawValue)")
    }
}
