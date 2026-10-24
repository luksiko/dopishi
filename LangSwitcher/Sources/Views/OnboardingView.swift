import SwiftUI
import AppKit

// MARK: - OnboardingView

struct OnboardingView: View {

    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager

    @ObservedObject private var aiModelManager = AIModelManager.shared

    @State private var currentStep = 0
    @State private var accessGranted = AccessibilityService.hasAccessibilityPermission
    @State private var testFieldText = ""
    @State private var conversionDemoShown = false

    // Permission polling timer
    @State private var permissionTimer: Timer? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            stepIndicator
                .padding(.top, 20)

            // Step content with slide animation
            ZStack {
                if currentStep == 0 {
                    step1View
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))
                } else if currentStep == 1 {
                    step2View
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))
                } else if currentStep == 2 {
                    step3View
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))
                } else {
                    step4View
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing),
                            removal: .move(edge: .leading)
                        ))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 540, height: 490)
        .onAppear {
            settingsManager.refreshSystemLayouts()
            startPermissionPolling()
        }
        .onDisappear {
            stopPermissionPolling()
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { idx in
                Circle()
                    .fill(idx == currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.25), value: currentStep)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Step 1: Accessibility Permission & Privacy

    private var step1View: some View {
        VStack(spacing: 14) {
            Image(systemName: accessGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                .font(.system(size: 52))
                .foregroundColor(accessGranted ? .green : .accentColor)
                .animation(.easeInOut(duration: 0.3), value: accessGranted)

            Text(l10n.t("onboarding.step1.title"))
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(l10n.t("onboarding.step1.body"))
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            // Privacy & Trust Box (Offline, Passwords, Open Source)
            VStack(alignment: .leading, spacing: 8) {
                Label(l10n.t("onboarding.privacy.offline"), systemImage: "wifi.slash")
                Label(l10n.t("onboarding.privacy.passwords"), systemImage: "lock.shield")
                Label(l10n.t("onboarding.privacy.openSource"), systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 460, alignment: .leading)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(8)

            if accessGranted {
                Label(l10n.t("onboarding.step1.granted"), systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.callout.weight(.medium))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))

                Button(action: advance) {
                    Text(l10n.t("onboarding.step2.continue"))
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(action: {
                    AccessibilityService.requestAccessibilityPermission()
                }) {
                    Text(l10n.t("onboarding.step1.grant"))
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: advance) {
                    Text(l10n.t("onboarding.step1.skip"))
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 2: Keyboard Languages

    private var step2View: some View {
        VStack(spacing: 16) {
            Text(l10n.t("onboarding.step2.title"))
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(l10n.t("onboarding.step2.body"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            layoutListView
                .frame(maxHeight: 220)

            Button(action: advance) {
                Text(l10n.t("onboarding.step2.continue"))
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var layoutListView: some View {
        let layouts = settingsManager.enabledLayouts
        if layouts.isEmpty {
            Text(l10n.t("onboarding.step2.noLayouts"))
                .foregroundColor(.secondary)
                .font(.callout)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(layouts) { layout in
                        LayoutRowView(layout: layout)
                            .environmentObject(l10n)
                    }
                }
            }
        }
    }

    // MARK: - Step 3: Local AI Assistant (Killer Feature)

    private var step3View: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.purple)

            Text(l10n.t("onboarding.ai.title"))
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(l10n.t("onboarding.ai.body"))
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            // AI Features Card
            VStack(alignment: .leading, spacing: 8) {
                Label(l10n.t("onboarding.ai.feature1"), systemImage: "cpu")
                Label(l10n.t("onboarding.ai.feature2"), systemImage: "shield.lefthalf.filled")
                Label(l10n.t("onboarding.ai.feature3"), systemImage: "arrow.down.circle")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 460, alignment: .leading)
            .background(Color.gray.opacity(0.08))
            .cornerRadius(8)

            // Download or Status Action
            switch aiModelManager.state {
            case .ready:
                Label(l10n.t("onboarding.ai.ready"), systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.callout.weight(.medium))

                Button(action: advance) {
                    Text(l10n.t("onboarding.step2.continue"))
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .downloading(let progress, _, _):
                VStack(spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 240)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button(action: advance) {
                    Text(l10n.t("onboarding.ai.continueInBackground"))
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

            case .notDownloaded, .error:
                Button(action: {
                    settingsManager.aiPredictiveEnabled = true
                    aiModelManager.startDownload()
                }) {
                    Label(l10n.t("onboarding.ai.downloadButton"), systemImage: "arrow.down.circle.fill")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: advance) {
                    Text(l10n.t("onboarding.ai.later"))
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Step 4: Try It Now

    private var step4View: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.chevron.compact.down.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text(l10n.t("onboarding.step3.title"))
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(l10n.t("onboarding.step3.body"))
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            TextField("ghbdtn", text: $testFieldText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)

            HStack(spacing: 8) {
                Text(l10n.t("onboarding.step3.hotkey"))
                    .foregroundColor(.secondary)
                    .font(.callout)
                Text(settingsManager.hotkeyDescription)
                    .font(.callout.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.gray.opacity(0.15))
                    )
            }

            HStack(spacing: 12) {
                Button(action: triggerTestConversion) {
                    Label(l10n.t("onboarding.step3.convert"), systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(testFieldText.isEmpty)

                if conversionDemoShown {
                    Label(l10n.t("onboarding.step3.tip"), systemImage: "sparkles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: conversionDemoShown)

            Button(action: completeOnboarding) {
                Text(l10n.t("onboarding.step3.done"))
                    .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func advance() {
        withAnimation {
            currentStep = min(currentStep + 1, 3)
        }
    }

    private func triggerTestConversion() {
        if !testFieldText.isEmpty {
            let activeLayoutIDs = settingsManager.enabledLayouts.map(\.id)
            let srcID = LayoutMapper.detectSourceLayout(text: testFieldText, candidateLayouts: activeLayoutIDs)
            let targetID = activeLayoutIDs.first(where: { $0 != srcID })
            if let srcID = srcID, let targetID = targetID,
               let converted = LayoutMapper.convert(text: testFieldText, from: srcID, to: targetID) {
                testFieldText = converted
            } else if let converted = LayoutMapper.convert(text: testFieldText, from: "com.apple.keylayout.US", to: "com.apple.keylayout.Russian") {
                testFieldText = converted
            }
        }
        withAnimation {
            conversionDemoShown = true
        }
    }

    private func completeOnboarding() {
        settingsManager.hasCompletedOnboarding = true
        NSApplication.shared.windows
            .first { $0.contentView?.subviews.contains { type(of: $0).description().contains("OnboardingView") } ?? false }?
            .close()
        // Notify AppDelegate to close onboarding window
        NotificationCenter.default.post(name: NSNotification.Name("CloseOnboardingWindow"), object: nil)
    }

    // MARK: - Permission Polling

    private func startPermissionPolling() {
        guard !accessGranted else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            Task { @MainActor in
                let trusted = AccessibilityService.hasAccessibilityPermission
                if trusted {
                    withAnimation {
                        accessGranted = true
                    }
                    t.invalidate()
                }
            }
        }
        permissionTimer = timer
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}

// MARK: - Layout Row View

private struct LayoutRowView: View {

    let layout: KeyboardLayout
    @EnvironmentObject var l10n: LocalizationManager

    // Observe DictionaryDownloadManager for download progress
    @StateObject private var downloadManager = DictionaryDownloadManager.shared

    var body: some View {
        HStack(spacing: 10) {
            Text(flagEmoji(for: layout.languageCode))
                .font(.title3)
            Text(layout.displayName)
                .font(.callout)
                .lineLimit(1)

            Spacer()

            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.07))
        .cornerRadius(8)
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let status = DictionaryDownloadManager.shared.status(for: layout.languageCode)
        let downloadState = downloadManager.downloadStates[layout.languageCode]

        switch status {
        case .systemProvided:
            Label(l10n.t("onboarding.step2.builtin"), systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption.weight(.medium))
                .labelStyle(.titleAndIcon)

        case .installed:
            Label(l10n.t("onboarding.step2.installed"), systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption.weight(.medium))
                .labelStyle(.titleAndIcon)

        case .availableForDownload(let dict):
            if let state = downloadState {
                switch state {
                case .downloading(let progress):
                    ProgressView(value: progress)
                        .frame(width: 80)
                        .progressViewStyle(.linear)
                case .completed:
                    Label(l10n.t("onboarding.step2.installed"), systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption.weight(.medium))
                        .labelStyle(.titleAndIcon)
                case .failed:
                    Button(l10n.t("onboarding.step2.download")) {
                        Task {
                            await DictionaryDownloadManager.shared.downloadDictionary(for: dict)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                case .idle:
                    downloadButton(dict: dict)
                }
            } else {
                downloadButton(dict: dict)
            }

        case .unsupported:
            Text("—")
                .foregroundColor(.secondary)
                .font(.caption)
        }
    }

    private func downloadButton(dict: DownloadableDictionary) -> some View {
        Button {
            Task {
                await DictionaryDownloadManager.shared.downloadDictionary(for: dict)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle")
                Text("\(l10n.t("onboarding.step2.download")) (~\(String(format: "%.1f", dict.approximateSizeMB)) MB)")
            }
            .font(.caption)
        }
        .buttonStyle(.bordered)
    }

    private func flagEmoji(for languageCode: String) -> String {
        let code = languageCode.lowercased().components(separatedBy: CharacterSet(charactersIn: "-_")).first ?? languageCode.lowercased()
        let flags: [String: String] = [
            "en": "🇺🇸", "ru": "🇷🇺", "uk": "🇺🇦", "de": "🇩🇪",
            "fr": "🇫🇷", "es": "🇪🇸", "it": "🇮🇹", "tg": "🇹🇯",
            "kk": "🇰🇿", "be": "🇧🇾", "tr": "🇹🇷", "he": "🇮🇱",
            "el": "🇬🇷", "pl": "🇵🇱", "cs": "🇨🇿", "sk": "🇸🇰",
            "nl": "🇳🇱", "pt": "🇵🇹", "sv": "🇸🇪", "no": "🇳🇴",
            "da": "🇩🇰", "fi": "🇫🇮", "hu": "🇭🇺", "ro": "🇷🇴",
        ]
        return flags[code] ?? "🌐"
    }
}
