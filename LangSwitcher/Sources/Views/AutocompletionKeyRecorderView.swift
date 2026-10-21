import SwiftUI
import Carbon

// MARK: - Autocompletion Key Recorder View
// Allows recording a custom key (single key or key + modifier) for accepting autocompletion.

struct AutocompletionKeyRecorderView: View {
    var title: String? = nil
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt
    var canClear: Bool = false
    var enabled: Binding<Bool>? = nil
    @EnvironmentObject var l10n: LocalizationManager
    
    @State private var isRecording = false
    @State private var monitor: Any?
    
    var body: some View {
        HStack {
            if let title = title {
                Text(title)
                    .font(.subheadline)
            } else {
                Text(l10n.t("autocompletion.customKey"))
                    .font(.subheadline)
            }
            
            Spacer()
            
            if isRecording {
                Text(l10n.t("autocompletion.recordKey"))
                    .foregroundStyle(.orange)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else if enabled?.wrappedValue == false {
                Text(l10n.t("autocompletion.noneKey"))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(currentKeyDescription)
                    .font(.system(.body, design: .monospaced))
                    .bold()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            if canClear && enabled?.wrappedValue != false && !isRecording {
                Button {
                    keyCode = 0
                    modifiers = 0
                    enabled?.wrappedValue = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Button(isRecording ? l10n.t("hotkeyRecorder.cancel") : l10n.t("autocompletion.changeKey")) {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var currentKeyDescription: String {
        let nseventMods = NSEvent.ModifierFlags(rawValue: modifiers).intersection(.deviceIndependentFlagsMask)
        let modsStr = HotkeyManager.modifierFlagsToString(nseventMods)
        let keyStr = HotkeyManager.keyCodeToString(keyCode)
        return "\(modsStr)\(keyStr)"
    }
    
    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Escape cancels recording
            if event.keyCode == 0x35 {
                stopRecording()
                return nil
            }
            
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            recordShortcut(keyCode: event.keyCode, modifiers: eventMods.rawValue)
            stopRecording()
            return nil
        }
    }
    
    func recordShortcut(keyCode newCode: UInt16, modifiers newModifiers: UInt) {
        keyCode = newCode
        modifiers = newModifiers
        enabled?.wrappedValue = true
    }

    private func stopRecording() {
        isRecording = false
        if let mon = monitor {
            NSEvent.removeMonitor(mon)
            monitor = nil
        }
    }
}
