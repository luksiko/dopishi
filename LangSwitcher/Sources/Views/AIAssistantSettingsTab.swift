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
    
    @State private var modelToDelete: RecommendedAIModel?
    @State private var showDeleteAlert = false
    @State private var showResetStatsAlert = false
    @State private var showClearHistoryAlert = false
    @State private var runningApps: [NSRunningApplication] = []
    @State private var expandedAppBundleID: String?
    @State private var vocabularyDrafts: [String: String] = [:]
    @State private var appMetadataCache: [String: (name: String, icon: NSImage?)] = [:]
    
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
                    
                    // Engine status indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(inferenceEngine.isRunning ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                        
                        if inferenceEngine.isStarting {
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
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }
            
            Section(l10n.t("ai.instructions.title")) {
                VStack(alignment: .leading, spacing: 8) {
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
                    
                    Toggle(l10n.t("ai.fieldAnchor.title"), isOn: $settingsManager.showFieldAnchorBadge)
                        .padding(.top, 6)
                    
                    Text(l10n.t("ai.fieldAnchor.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

            // MARK: - Section 6: Per-App Settings
            Section(l10n.t("ai.perApp.title")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("ai.perApp.desc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if settingsManager.perAppAISettings.isEmpty {
                        Text(l10n.t("ai.perApp.empty"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(Array(settingsManager.perAppAISettings.values.sorted(by: { $0.appName < $1.appName }))) { appSetting in
                            perAppCard(for: appSetting)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(runningApps, id: \.processIdentifier) { app in
                                if let bid = app.bundleIdentifier, settingsManager.perAppAISettings[bid] == nil {
                                    Button(app.localizedName ?? bid) {
                                        let name = app.localizedName ?? bid
                                        settingsManager.setAppAISettings(AppAISettings(bundleID: bid, appName: name))
                                        expandedAppBundleID = bid
                                    }
                                }
                            }
                        } label: {
                            Label(l10n.t("ai.perApp.addRunning"), systemImage: "plus")
                        }
                        .onAppear { refreshRunningApps() }
                        
                        Button(l10n.t("ai.perApp.addOther")) {
                            selectAppBundle()
                        }
                    }
                    .padding(.top, 4)
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
        .onAppear {
            refreshRunningApps()
            populateAppMetadataCache()
        }
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
        return "\(model.name) (\(model.localizedSize(using: l10n)))\(star)\(downloaded)"
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

    @ViewBuilder
    private func perAppCard(for appSetting: AppAISettings) -> some View {
        let isExpanded = expandedAppBundleID == appSetting.bundleID
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                let meta = appMetadata(for: appSetting.bundleID)
                if let icon = meta.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "app")
                        .frame(width: 18, height: 18)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(appSetting.appName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(appSetting.bundleID)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        expandedAppBundleID = isExpanded ? nil : appSetting.bundleID
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Button(role: .destructive) {
                    settingsManager.removeAppAISettings(bundleID: appSetting.bundleID)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(l10n.t("ai.perApp.enabled"), isOn: Binding(
                        get: { appSetting.isAIEnabled },
                        set: { val in
                            var updated = appSetting
                            updated.isAIEnabled = val
                            settingsManager.setAppAISettings(updated)
                        }
                    ))
                    .font(.caption)
                    
                    Text(l10n.t("ai.perApp.instructions"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    TextField("", text: Binding(
                        get: { appSetting.customInstructions },
                        set: { val in
                            var updated = appSetting
                            updated.customInstructions = val
                            settingsManager.setAppAISettings(updated)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    
                    Text(l10n.t("ai.perApp.vocabulary"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    TextField("", text: Binding(
                        get: {
                            vocabularyDrafts[appSetting.bundleID] ?? appSetting.customVocabulary.joined(separator: ", ")
                        },
                        set: { val in
                            vocabularyDrafts[appSetting.bundleID] = val
                            var updated = appSetting
                            updated.customVocabulary = val.components(separatedBy: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                            settingsManager.setAppAISettings(updated)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                }
                .padding(.top, 4)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }

    private func refreshRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        runningApps = apps
        for app in apps {
            if let bid = app.bundleIdentifier {
                let name = app.localizedName ?? bid
                let icon = app.icon
                appMetadataCache[bid] = (name, icon)
            }
        }
    }

    private func populateAppMetadataCache() {
        for bid in settingsManager.perAppAISettings.keys {
            if appMetadataCache[bid] == nil {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                    let name = FileManager.default.displayName(atPath: url.path)
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    appMetadataCache[bid] = (name, icon)
                }
            }
        }
    }

    private func appMetadata(for bundleID: String) -> (name: String, icon: NSImage?) {
        if let cached = appMetadataCache[bundleID] {
            return cached
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let result = (name, Optional(icon))
            return result
        } else {
            return (bundleID, nil as NSImage?)
        }
    }

    private func selectAppBundle() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
            let name = FileManager.default.displayName(atPath: url.path)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            appMetadataCache[bundleID] = (name, icon)
            settingsManager.setAppAISettings(AppAISettings(bundleID: bundleID, appName: name))
            expandedAppBundleID = bundleID
        }
    }
}
