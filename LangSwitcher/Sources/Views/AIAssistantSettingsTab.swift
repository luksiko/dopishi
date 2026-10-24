import SwiftUI
import UniformTypeIdentifiers

// MARK: - AI Assistant Settings Tab

struct AIAssistantSettingsTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager

    @StateObject private var modelManager = AIModelManager.shared
    @StateObject private var powerService = PowerService.shared
    @StateObject private var inferenceEngine = AIInferenceEngine.shared
    @StateObject private var profiler = AIModelProfiler.shared
    @StateObject private var textHistoryStore = UserTextHistoryStore.shared
    @ObservedObject private var attentionCenter = AttentionCenter.shared
    @ObservedObject private var batteryManager = BatteryPowerManager.shared
    @ObservedObject private var loraManager = LoRAAdapterManager.shared

    @State private var modelToDelete: RecommendedAIModel?
    @State private var showDeleteAlert = false
    @State private var showResetStatsAlert = false
    @State private var showClearHistoryAlert = false

    var body: some View {
        Form {
            // MARK: - Master Switch & Engine Status
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundStyle(.tint)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(l10n.t("ai.masterSwitch.title"))
                                .font(.headline)
                            Text(settingsManager.aiPredictiveEnabled ? l10n.t("ai.masterSwitch.activeDesc") : l10n.t("ai.masterSwitch.disabledDesc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding(
                            get: { settingsManager.aiPredictiveEnabled },
                            set: { newValue in
                                settingsManager.aiPredictiveEnabled = newValue
                                if newValue {
                                    Task { await inferenceEngine.ensureRunning() }
                                } else {
                                    inferenceEngine.stop()
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                    }

                    Divider()

                    // Engine status indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(settingsManager.aiPredictiveEnabled && inferenceEngine.isRunning ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)

                        if !settingsManager.aiPredictiveEnabled {
                            Text(l10n.t("ai.status.offMemoryFreed"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if inferenceEngine.isStarting {
                            Text(l10n.t("ai.status.starting"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ProgressView()
                                .controlSize(.mini)
                        } else if inferenceEngine.isRunning {
                            let loadedName = (inferenceEngine.currentLoadedModelPath as NSString?)?.lastPathComponent ?? modelManager.currentModel.name
                            Text(String(format: l10n.t("ai.status.running"), loadedName))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(l10n.t("ai.status.stopped"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if settingsManager.aiPredictiveEnabled {
                            if !inferenceEngine.isRunning && modelManager.isDownloaded(model: modelManager.currentModel) {
                                Button(l10n.t("ai.engine.start")) {
                                    Task {
                                        await inferenceEngine.ensureRunning()
                                    }
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            } else if inferenceEngine.isRunning {
                                Button(l10n.t("ai.engine.restart")) {
                                    Task {
                                        inferenceEngine.stop()
                                        _ = await inferenceEngine.ensureRunning()
                                    }
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                            }
                        }
                    }
                    .padding(.top, 2)

                    // Inline Prediction Conflict Warning
                    if attentionCenter.activeIssues.contains(where: { $0.id == .inlinePredictionConflict }) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.body)
                                .foregroundStyle(.orange)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(l10n.t("attention.inlinePredictionConflict.title"))
                                    .font(.subheadline)
                                    .bold()
                                Text(l10n.t("attention.inlinePredictionConflict.desc"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button(l10n.t("attention.inlinePredictionConflict.action")) {
                                    InlinePredictionManager.disableAutomaticInlinePrediction()
                                    attentionCenter.refreshIssues()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .padding(.top, 2)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: - Time Saved Banner
            Section {
                TimeSavedBanner()
            }

            // MARK: - Interactive Sandbox
            Section {
                CompletionDemoTextField()
            }

            // MARK: - Section 1: Autocompletion Core
            Section(l10n.t("general.autocompletion")) {
                Toggle(l10n.t("autocompletion.enabled"), isOn: $settingsManager.autoCompletionEnabled)

                Text(l10n.t("autocompletion.desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settingsManager.autoCompletionEnabled {
                    Picker(l10n.t("autocompletion.displayMode"), selection: $settingsManager.autoCompletionDisplayMode) {
                        ForEach(AutocompletionDisplayMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Text(settingsManager.autoCompletionDisplayMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Stepper("\(l10n.t("autocompletion.minPrefixLength")) \(settingsManager.autoCompletionMinPrefixLength)", value: $settingsManager.autoCompletionMinPrefixLength, in: 2...5)

                    Stepper("\(l10n.t("autocompletion.maxSuggestions")) \(settingsManager.autoCompletionMaxSuggestions)", value: $settingsManager.autoCompletionMaxSuggestions, in: 1...6)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l10n.t("autocompletion.delay"))
                            Spacer()
                            Text("\(Int(settingsManager.autoCompletionDelay * 1000)) \(l10n.t("common.ms"))")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settingsManager.autoCompletionDelay, in: 0.0...0.30, step: 0.025)
                    }
                    .padding(.vertical, 2)

                    Toggle(l10n.t("autocompletion.includeCrossLayout"), isOn: $settingsManager.autoCompletionIncludeCrossLayout)

                    Toggle(l10n.t("autocompletion.suggestProfanity"), isOn: $settingsManager.autoCompletionSuggestProfanity)

                    HStack {
                        Toggle(l10n.t("autocompletion.fim"), isOn: $settingsManager.proFimEnabled)
                        Spacer()
                        ProBadge()
                    }
                    .padding(.top, 4)

                    Text(l10n.t("autocompletion.fimDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Section 2: Autocompletion Keybindings
            if settingsManager.autoCompletionEnabled {
                Section(l10n.t("autocompletion.shortcutsSection")) {
                    HStack {
                        Text(l10n.t("autocompletion.completeNextWord"))
                        Spacer()
                        Picker("", selection: $settingsManager.autoCompletionAcceptKey) {
                            ForEach(AutocompletionAcceptKey.allCases) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 170)
                    }

                    if settingsManager.autoCompletionAcceptKey == .custom {
                        AutocompletionKeyRecorderView(
                            keyCode: $settingsManager.autoCompletionCustomKeyCode,
                            modifiers: $settingsManager.autoCompletionCustomModifiers
                        )
                    }

                    Toggle(l10n.t("autocompletion.includeTrailingSpace"), isOn: $settingsManager.autoCompletionIncludeTrailingSpace)

                    Toggle(l10n.t("autocompletion.acceptEntirePhrase"), isOn: $settingsManager.autoCompletionAcceptEntirePhrase)

                    Toggle(l10n.t("autocompletion.includeTrailingPunctuation"), isOn: $settingsManager.autoCompletionIncludeTrailingPunctuation)

                    HStack {
                        Text(l10n.t("autocompletion.triggerFullCompletion"))
                        Spacer()
                        Picker("", selection: $settingsManager.autoCompletionAcceptAllKey) {
                            ForEach(AutocompletionAcceptAllKey.allCases) { key in
                                Text(key.displayName).tag(key)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 170)
                    }

                    if settingsManager.autoCompletionAcceptAllKey == .custom {
                        AutocompletionKeyRecorderView(
                            keyCode: $settingsManager.autoCompletionCustomAcceptAllKeyCode,
                            modifiers: $settingsManager.autoCompletionCustomAcceptAllModifiers
                        )
                    }

                    HStack {
                        Text(l10n.t("autocompletion.whenEscapePressed"))
                        Spacer()
                        Picker("", selection: $settingsManager.autoCompletionEscapeAction) {
                            ForEach(AutocompletionEscapeAction.allCases) { action in
                                Text(action.displayName).tag(action)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 200)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(l10n.t("autocompletion.forceActivate"))
                            .font(.subheadline)
                        AutocompletionKeyRecorderView(
                            title: "",
                            keyCode: $settingsManager.autoCompletionForceActivateKeyCode,
                            modifiers: $settingsManager.autoCompletionForceActivateModifiers,
                            canClear: true,
                            enabled: $settingsManager.autoCompletionForceActivateEnabled
                        )
                    }

                    Toggle(l10n.t("autocompletion.useNumberShortcuts"), isOn: $settingsManager.autoCompletionUseNumberShortcuts)
                }
            }

            Section(l10n.t("ai.instructions.title")) {
                VStack(alignment: .leading, spacing: 12) {
                    // Persona & LoRA Picker
                    VStack(alignment: .leading, spacing: 6) {
                        Picker(l10n.t("ai.persona.title"), selection: $loraManager.activeAdapterId) {
                            ForEach(loraManager.allAdapters) { adapter in
                                Label(adapter.name, systemImage: adapter.icon)
                                    .tag(adapter.id)
                            }
                        }
                        .pickerStyle(.menu)

                        if let active = loraManager.activeAdapter {
                            HStack {
                                Image(systemName: active.icon)
                                    .foregroundStyle(Color.accentColor)
                                Text(l10n.currentLanguage == "ru" ? active.systemPromptRu : active.systemPromptEn)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(6)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    Divider()

                    Text(l10n.t("ai.instructions.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $settingsManager.aiCustomInstructions)
                        .font(.body)
                        .frame(minHeight: 64, maxHeight: 100)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                    HStack(spacing: 8) {
                        presetButton(titleKey: "ai.instructions.preset.coder", textKey: "ai.instructions.preset.coder.text")
                        presetButton(titleKey: "ai.instructions.preset.concise", textKey: "ai.instructions.preset.concise.text")
                        presetButton(titleKey: "ai.instructions.preset.business", textKey: "ai.instructions.preset.business.text")
                        Spacer()
                        if !settingsManager.aiCustomInstructions.isEmpty {
                            Button(l10n.t("ai.instructions.clear")) { settingsManager.aiCustomInstructions = "" }
                                .buttonStyle(.link)
                        }
                    }
                }
            }

            // MARK: - Section 2: Local AI Models (Dropdown & RAM Guide)
            Section(l10n.t("ai.model.recommended")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(l10n.t("ai.model.recommended.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Model Dropdown Picker
                    Picker(l10n.t("ai.model.picker.label"), selection: Binding(
                        get: { settingsManager.selectedModelId },
                        set: { newId in
                            if newId == RecommendedAIModel.customModelID {
                                if settingsManager.customModelPath.isEmpty {
                                    selectCustomModelFile()
                                } else {
                                    modelManager.selectCustomModel(path: settingsManager.customModelPath)
                                    Task {
                                        await inferenceEngine.ensureRunning()
                                    }
                                }
                            } else {
                                let model = RecommendedAIModel.model(for: newId)
                                modelManager.selectModel(model)
                                Task {
                                    await inferenceEngine.ensureRunning()
                                }
                            }
                        }
                    )) {
                        Section(header: Text("8 GB RAM")) {
                            ForEach(RecommendedAIModel.allModels.filter { $0.ramTier == "8 GB" }) { model in
                                Text(pickerTitle(for: model)).tag(model.id)
                            }
                        }
                        Section(header: Text("8–16 GB RAM")) {
                            ForEach(RecommendedAIModel.allModels.filter { $0.ramTier == "8–16 GB" || $0.ramTier == "16 GB" }) { model in
                                Text(pickerTitle(for: model)).tag(model.id)
                            }
                        }
                        Section(header: Text("16–24+ GB RAM")) {
                            ForEach(RecommendedAIModel.allModels.filter { $0.ramTier.contains("24") }) { model in
                                Text(pickerTitle(for: model)).tag(model.id)
                            }
                        }
                        Divider()
                        Section(header: Text(l10n.t("ai.model.section.custom"))) {
                            Text(customPickerTitle).tag(RecommendedAIModel.customModelID)
                        }
                    }
                    .pickerStyle(.menu)

                    // Details Card for Selected Model
                    selectedModelCard(modelManager.currentModel)

                    Divider()
                        .padding(.vertical, 2)

                    // Concise RAM Recommendations Guide
                    ramRecommendationsGuide
                }
                .padding(.vertical, 4)
            }

            // MARK: - Section 3: Predictive Continuation Parameters
            Section(l10n.t("ai.predictive.parameters")) {
                if !settingsManager.aiPredictiveEnabled {
                    Text(l10n.t("ai.masterSwitch.disabledDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(l10n.t("ai.predictive.wordCount"), selection: $settingsManager.aiMaxContinuationWords) {
                        Text(String(format: l10n.t("ai.predictive.words"), 2)).tag(2)
                        Text(String(format: l10n.t("ai.predictive.words"), 3)).tag(3)
                        Text(String(format: l10n.t("ai.predictive.words"), 4)).tag(4)
                        Text("8 (PRO)").tag(8)
                        Text("15 (PRO)").tag(15)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)

                    if settingsManager.aiMaxContinuationWords > 4 {
                        HStack(spacing: 6) {
                            ProBadge()
                            Text(l10n.t("ai.predictive.proLengthDesc"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 2)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l10n.t("ai.predictive.debounceDelay"))
                            Spacer()
                            Text("\(Int(settingsManager.aiDebounceDelay * 1000)) \(l10n.t("common.ms"))")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: $settingsManager.aiDebounceDelay,
                            in: 0.15...1.0,
                            step: 0.05
                        )

                        HStack {
                            Text(l10n.t("ai.predictive.fast"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(l10n.t("ai.predictive.slow"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 6)

                    Toggle(l10n.t("ai.predictive.streaming"), isOn: $settingsManager.aiStreamingEnabled)
                        .padding(.top, 6)

                    Text(l10n.t("ai.predictive.streaming.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(l10n.t("ai.predictive.screenContext"), isOn: $settingsManager.aiScreenContextEnabled)
                        .padding(.top, 6)

                    Text(l10n.t("ai.predictive.screenContext.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Toggle(l10n.t("ai.deepContext"), isOn: $settingsManager.proDeepContextEnabled)
                        Spacer()
                        ProBadge()
                    }
                    .padding(.top, 6)

                    Text(l10n.t("ai.deepContextDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(l10n.t("ai.fieldAnchor.title"), isOn: $settingsManager.showFieldAnchorBadge)
                        .padding(.top, 6)

                    Text(l10n.t("ai.fieldAnchor.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Section 4: Battery Mode
            Section(l10n.t("ai.battery.title")) {
                Toggle(l10n.t("ai.battery.adaptiveManagement"), isOn: $settingsManager.aiBatteryModeEnabled)

                Text(l10n.t("ai.battery.desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settingsManager.aiBatteryModeEnabled {
                    Picker(l10n.t("ai.battery.policy.label"), selection: $settingsManager.aiBatteryPolicy) {
                        ForEach(BatteryPowerPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .pickerStyle(.menu)

                    Text(settingsManager.aiBatteryPolicy.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(powerService.isOnBattery ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(batteryManager.statusDescription(l10n: l10n))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }

            // MARK: - Section 5: Benchmark Profiler
            Section(l10n.t("ai.benchmark.title")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("ai.benchmark.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            Task {
                                await profiler.runBenchmark()
                            }
                        } label: {
                            if profiler.isRunning {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(l10n.t("ai.benchmark.running"))
                                }
                            } else {
                                Label(l10n.t("ai.benchmark.run"), systemImage: "gauge.with.dots.needle.bottom.50percent")
                            }
                        }
                        .disabled(profiler.isRunning || (!inferenceEngine.isRunning && !modelManager.isDownloaded(model: modelManager.currentModel)))

                        Spacer()

                        if let report = profiler.lastReport {
                            Text(String(format: l10n.t("ai.benchmark.lastRun"), report.date.formatted(date: .omitted, time: .shortened)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let report = profiler.lastReport {
                        VStack(alignment: .leading, spacing: 8) {
                            Divider()
                                .padding(.vertical, 2)

                            if report.samples.allSatisfy({ $0.continuation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    Text(l10n.t("ai.benchmark.error.noResponse"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.12))
                                .cornerRadius(6)
                            }

                            HStack(spacing: 12) {
                                statCard(
                                    title: l10n.t("ai.benchmark.ttft"),
                                    value: String(format: "%.0f ms", report.averageTTFTMs),
                                    icon: "bolt.fill",
                                    color: .orange
                                )
                                statCard(
                                    title: l10n.t("ai.benchmark.latency"),
                                    value: String(format: "%.0f ms", report.averageLatencyMs),
                                    icon: "clock.arrow.circlepath",
                                    color: .blue
                                )
                                statCard(
                                    title: l10n.t("ai.benchmark.speed"),
                                    value: String(format: "%.1f t/s", report.averageTokensPerSecond),
                                    icon: "speedometer",
                                    color: .green
                                )
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(l10n.t("ai.benchmark.samples"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)

                                ForEach(report.samples) { sample in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text("\"\(sample.prompt)\"")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(String(format: "%.0f ms", sample.ttftMs))
                                                .font(.caption2)
                                                .monospacedDigit()
                                                .foregroundStyle(.secondary)
                                        }
                                        HStack {
                                            Text("→ ")
                                                .font(.caption)
                                                .foregroundStyle(.tint)
                                            Text(sample.continuation)
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                            Spacer()
                                            Image(systemName: sample.isAppropriate ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                                .font(.caption)
                                                .foregroundStyle(sample.isAppropriate ? .green : .orange)
                                        }
                                    }
                                    .padding(6)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: - Section 7: Personalization & Writing History
            Section(l10n.t("ai.personalization.title")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(l10n.t("ai.personalization.enable"), isOn: $settingsManager.aiPersonalizationEnabled)

                    Text(l10n.t("ai.personalization.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if settingsManager.aiPersonalizationEnabled {
                        HStack {
                            Text(String(format: l10n.t("ai.personalization.count"), textHistoryStore.totalSnippetCount))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            if textHistoryStore.totalSnippetCount > 0 {
                                Button(l10n.t("ai.personalization.clear")) {
                                    showClearHistoryAlert = true
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                                .foregroundStyle(.red)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: - Section 8: Extended Statistics
            Section(l10n.t("ai.stats.title")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        statCard(
                            title: l10n.t("ai.stats.savedChars"),
                            value: settingsManager.savedCharactersCount.formatted(),
                            icon: "character.cursor.ibeam",
                            color: .blue
                        )
                        statCard(
                            title: l10n.t("ai.stats.savedClicks"),
                            value: settingsManager.savedClicksCount.formatted(),
                            icon: "hand.tap",
                            color: .purple
                        )
                        statCard(
                            title: l10n.t("ai.stats.conversions"),
                            value: settingsManager.conversionCount.formatted(),
                            icon: "arrow.2.squarepath",
                            color: .green
                        )
                    }

                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            showResetStatsAlert = true
                        } label: {
                            Text(l10n.t("ai.stats.reset"))
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .confirmationDialog(
                            l10n.t("ai.stats.resetConfirm"),
                            isPresented: $showResetStatsAlert,
                            titleVisibility: .visible
                        ) {
                            Button(l10n.t("ai.stats.reset"), role: .destructive) {
                                settingsManager.resetStatistics()
                            }
                            Button(l10n.t("common.cancel"), role: .cancel) {}
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            modelToDelete?.isCustom == true ? l10n.t("ai.model.custom.disconnectConfirm") : l10n.t("ai.model.deleteConfirm"),
            isPresented: $showDeleteAlert,
            titleVisibility: .visible
        ) {
            Button(
                modelToDelete?.isCustom == true ? l10n.t("ai.model.custom.disconnect") : l10n.t("ai.model.deleteButton"),
                role: .destructive
            ) {
                if let model = modelToDelete {
                    if model.id == settingsManager.selectedModelId {
                        inferenceEngine.stop()
                    }
                    modelManager.deleteModel(model: model)
                }
            }
            Button(l10n.t("common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(
            l10n.t("ai.personalization.clearConfirm"),
            isPresented: $showClearHistoryAlert,
            titleVisibility: .visible
        ) {
            Button(l10n.t("ai.personalization.clear"), role: .destructive) {
                textHistoryStore.clearHistory()
            }
            Button(l10n.t("common.cancel"), role: .cancel) {}
        }
    }

    // MARK: - Helper Views & Components

    private func pickerTitle(for model: RecommendedAIModel) -> String {
        let star = model.isDefault ? " ★" : ""
        let downloaded = modelManager.isDownloaded(model: model) ? " ✓" : ""
        let pro = (model.ramTier.contains("24") || model.id == "gemma-4-e2b") ? " [PRO]" : ""
        return "\(model.name) (\(model.localizedSize(using: l10n)))\(star)\(downloaded)\(pro)"
    }

    private var customPickerTitle: String {
        if settingsManager.customModelPath.isEmpty {
            return l10n.t("ai.model.custom.option")
        }
        let fileName = (settingsManager.customModelPath as NSString).lastPathComponent
        let size = modelManager.currentModel.isCustom ? modelManager.currentModel.localizedSize(using: l10n) : ""
        let sizePart = size.isEmpty ? "" : " (\(size))"
        return "📁 \(fileName)\(sizePart)"
    }

    @ViewBuilder
    private func selectedModelCard(_ model: RecommendedAIModel) -> some View {
        let isDownloaded = modelManager.isDownloaded(model: model)

        VStack(alignment: .leading, spacing: 8) {
            // Title & Badges
            HStack(alignment: .center, spacing: 6) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if !model.sizeText.isEmpty {
                    Text(model.localizedSize(using: l10n))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(6)
                }

                Text(l10n.t(model.ramTierKey))
                    .font(.caption2)
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.12))
                    .cornerRadius(6)

                if model.isDefault {
                    Text(l10n.t("ai.model.badge.recommended"))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(6)
                }

                if model.ramTier.contains("24") || model.id == "gemma-4-e2b" {
                    ProBadge()
                }

                Spacer()

                if isDownloaded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(l10n.t("ai.model.active"))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(10)
                }
            }

            // Description or Custom Path
            if model.isCustom {
                if settingsManager.customModelPath.isEmpty {
                    Text(l10n.t("ai.model.custom.noFileSelected"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(format: l10n.t("ai.model.custom.path"), settingsManager.customModelPath))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                Text(l10n.t(model.descriptionKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Action Controls
            HStack(spacing: 8) {
                if model.isCustom {
                    Button {
                        selectCustomModelFile()
                    } label: {
                        Label(
                            settingsManager.customModelPath.isEmpty ? l10n.t("ai.model.custom.chooseFile") : l10n.t("ai.model.custom.changeFile"),
                            systemImage: "folder"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !settingsManager.customModelPath.isEmpty {
                        Button(role: .destructive) {
                            modelToDelete = model
                            showDeleteAlert = true
                        } label: {
                            Text(l10n.t("ai.model.custom.disconnect"))
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    if case .downloading(let progress, _, _) = modelManager.state,
                       modelManager.currentModel.id == model.id {
                        Button(l10n.t("ai.model.cancelDownload")) {
                            modelManager.cancelDownload()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if isDownloaded {
                        Button {
                            modelToDelete = model
                            showDeleteAlert = true
                        } label: {
                            Label(l10n.t("ai.model.deleteButton"), systemImage: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    } else {
                        Button {
                            modelManager.startDownload(model: model)
                        } label: {
                            Label(
                                String(format: l10n.t("ai.model.downloadButton"), model.localizedSize(using: l10n)),
                                systemImage: "arrow.down.circle"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(modelManager.state.isDownloading)
                    }
                }

                Spacer()
            }
            .padding(.top, 2)

            // Downloading progress bar
            if case .downloading(let progress, _, _) = modelManager.state,
               modelManager.currentModel.id == model.id {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !modelManager.downloadSpeed.isEmpty {
                            Text("• \(modelManager.downloadSpeed)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
    }

    // MARK: - RAM Recommendations Guide

    @ViewBuilder
    private var ramRecommendationsGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "memorychip")
                    .foregroundStyle(.blue)
                    .font(.caption)
                Text(l10n.t("ai.ramGuide.title"))
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 5) {
                ramGuideRow(
                    tierBadge: "8 GB",
                    badgeColor: .green,
                    text: l10n.t("ai.ramGuide.8gb")
                )
                ramGuideRow(
                    tierBadge: "16 GB",
                    badgeColor: .blue,
                    text: l10n.t("ai.ramGuide.16gb")
                )
                ramGuideRow(
                    tierBadge: "24+ GB",
                    badgeColor: .purple,
                    text: l10n.t("ai.ramGuide.24gb")
                )
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func ramGuideRow(tierBadge: String, badgeColor: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(tierBadge)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(badgeColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(0.12))
                .cornerRadius(4)
                .frame(width: 50, alignment: .leading)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectCustomModelFile() {
        let panel = NSOpenPanel()
        panel.title = l10n.t("ai.customModel.openPanelTitle")
        panel.prompt = l10n.t("ai.customModel.openPanelPrompt")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let ggufType = UTType(filenameExtension: "gguf") {
            panel.allowedContentTypes = [ggufType, .data]
        } else {
            panel.allowedContentTypes = [.data]
        }

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            modelManager.selectCustomModel(path: url.path)
            Task {
                await inferenceEngine.ensureRunning()
            }
        } else {
            if settingsManager.customModelPath.isEmpty {
                settingsManager.selectedModelId = modelManager.currentModel.id
            }
        }
    }

    private var powerStatusText: String {
        if powerService.isOnBattery {
            return l10n.t("ai.battery.status.battery")
        } else {
            return l10n.t("ai.battery.status.ac")
        }
    }

    @ViewBuilder
    private func presetButton(titleKey: String, textKey: String) -> some View {
        Button {
            settingsManager.aiCustomInstructions = l10n.t(textKey)
        } label: {
            Text(l10n.t(titleKey))
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
    }
}
