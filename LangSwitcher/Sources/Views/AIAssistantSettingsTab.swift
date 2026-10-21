import SwiftUI

// MARK: - AI Assistant Settings Tab

struct AIAssistantSettingsTab: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var l10n: LocalizationManager
    
    @StateObject private var modelManager = AIModelManager.shared
    @StateObject private var powerService = PowerService.shared
    @StateObject private var inferenceEngine = AIInferenceEngine.shared
    
    @State private var modelToDelete: RecommendedAIModel?
    @State private var showDeleteAlert = false
    @State private var showResetStatsAlert = false
    
    var body: some View {
        Form {
            // MARK: - Header
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 26))
                            .foregroundStyle(.tint)
                            .padding(.trailing, 4)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text(l10n.t("ai.title"))
                                .font(.headline)
                            Text(l10n.t("ai.subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // MARK: - Section 1: Custom Instructions
            Section(l10n.t("ai.instructions.title")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("ai.instructions.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ZStack(alignment: .topLeading) {
                        if settingsManager.aiCustomInstructions.isEmpty {
                            Text(l10n.t("ai.instructions.placeholder"))
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 8)
                        }
                        
                        TextEditor(text: $settingsManager.aiCustomInstructions)
                            .font(.body)
                            .frame(minHeight: 64, maxHeight: 90)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    
                    // Preset pills
                    HStack(spacing: 8) {
                        presetButton(titleKey: "ai.instructions.preset.coder", textKey: "ai.instructions.preset.coder.text")
                        presetButton(titleKey: "ai.instructions.preset.concise", textKey: "ai.instructions.preset.concise.text")
                        presetButton(titleKey: "ai.instructions.preset.business", textKey: "ai.instructions.preset.business.text")
                        
                        Spacer()
                        
                        if !settingsManager.aiCustomInstructions.isEmpty {
                            Button(l10n.t("ai.instructions.clear")) {
                                settingsManager.aiCustomInstructions = ""
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }
            
            // MARK: - Section 2: Recommended Models
            Section(l10n.t("ai.model.recommended")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(l10n.t("ai.model.recommended.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(RecommendedAIModel.allModels) { model in
                        modelRow(for: model)
                        if model.id != RecommendedAIModel.allModels.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            // MARK: - Section 3: Predictive Text Continuation
            Section(l10n.t("ai.predictive.enable")) {
                Toggle(l10n.t("ai.predictive.enable"), isOn: $settingsManager.aiPredictiveEnabled)
                
                Text(l10n.t("ai.predictive.desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if settingsManager.aiPredictiveEnabled {
                    Picker(l10n.t("ai.predictive.wordCount"), selection: $settingsManager.aiMaxContinuationWords) {
                        Text(String(format: l10n.t("ai.predictive.words"), 2)).tag(2)
                        Text(String(format: l10n.t("ai.predictive.words"), 3)).tag(3)
                        Text(String(format: l10n.t("ai.predictive.words"), 4)).tag(4)
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 4)
                    
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
                }
            }
            
            // MARK: - Section 4: Battery Mode
            Section(l10n.t("ai.battery.title")) {
                Toggle(l10n.t("ai.battery.title"), isOn: $settingsManager.aiBatteryModeEnabled)
                
                Text(l10n.t("ai.battery.desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Circle()
                        .fill(powerService.isOnBattery ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    
                    Text(powerStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            
            // MARK: - Section 5: Extended Statistics
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
            l10n.t("ai.model.deleteConfirm"),
            isPresented: $showDeleteAlert,
            titleVisibility: .visible
        ) {
            Button(l10n.t("ai.model.deleteButton"), role: .destructive) {
                if let model = modelToDelete {
                    if model.id == settingsManager.selectedModelId {
                        inferenceEngine.stop()
                    }
                    modelManager.deleteModel(model: model)
                }
            }
            Button(l10n.t("common.cancel"), role: .cancel) {}
        }
    }
    
    // MARK: - Helper Views
    
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
    
    @ViewBuilder
    private func modelRow(for model: RecommendedAIModel) -> some View {
        let isDownloaded = modelManager.isDownloaded(model: model)
        let isCurrent = (settingsManager.selectedModelId == model.id)
        
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(model.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(model.sizeText)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12))
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
                    }
                    
                    Text(l10n.t(model.descriptionKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Controls
                if case .downloading(let progress, _, _) = modelManager.state,
                   modelManager.currentModel.id == model.id {
                    Button(l10n.t("ai.model.cancelDownload")) {
                        modelManager.cancelDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if isDownloaded {
                    HStack(spacing: 8) {
                        if isCurrent {
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
                        } else {
                            Button(l10n.t("ai.model.select")) {
                                modelManager.selectModel(model)
                                Task {
                                    await inferenceEngine.ensureRunning()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Button {
                            modelToDelete = model
                            showDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(l10n.t("ai.model.deleteButton"))
                    }
                } else {
                    Button {
                        modelManager.startDownload(model: model)
                    } label: {
                        Label(l10n.t("ai.model.downloadButton"), systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(modelManager.state.isDownloading)
                }
            }
            
            // If this specific model is downloading, show progress bar
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
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var powerStatusText: String {
        if powerService.isOnBattery {
            return l10n.t("ai.battery.status.battery")
        } else {
            return l10n.t("ai.battery.status.ac")
        }
    }
}
