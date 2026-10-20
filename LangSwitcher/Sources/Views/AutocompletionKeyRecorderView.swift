import SwiftUI
import Carbon

// MARK: - Autocompletion Key Recorder View
// Allows recording a custom key (single key or key + modifier) for accepting autocompletion.

struct AutocompletionKeyRecorderView: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: UInt
    @EnvironmentObject var l10n: LocalizationManager
    
    @State private var isRecording = false
    @State private var monitor: Any?
    
    var body: some View {
        HStack {
            Text(l10n.t("autocompletion.customKey"))
                .font(.subheadline)
            
            Spacer()
            
            if isRecording {
                Text(l10n.t("autocompletion.recordKey"))
                    .foregroundStyle(.orange)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Text(currentKeyDescription)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
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
            self.keyCode = event.keyCode
            self.modifiers = eventMods.rawValue
            stopRecording()
            return nil
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let mon = monitor {
            NSEvent.removeMonitor(mon)
            monitor = nil
        }
    }
}
