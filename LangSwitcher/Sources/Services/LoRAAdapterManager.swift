import Foundation
import SwiftUI

// MARK: - LoRA Adapter & Persona Descriptor

public struct LoRAAdapterDescriptor: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let icon: String
    public let systemPromptRu: String
    public let systemPromptEn: String
    public let temperature: Float
    public let filePath: String?
    public var scale: Float

    public init(
        id: String,
        name: String,
        icon: String,
        systemPromptRu: String,
        systemPromptEn: String,
        temperature: Float = 0.3,
        filePath: String? = nil,
        scale: Float = 1.0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.systemPromptRu = systemPromptRu
        self.systemPromptEn = systemPromptEn
        self.temperature = temperature
        self.filePath = filePath
        self.scale = scale
    }
}

// MARK: - LoRA Adapter Manager
// Coordinates persona fine-tuning, domain system prompt steering, and external GGUF LoRA adapters.

@MainActor
public final class LoRAAdapterManager: ObservableObject {
    public static let shared = LoRAAdapterManager()

    private let defaults = UserDefaults.standard
    private let activeKey = "dopishi.ai.activePersonaId"
    private let customAdaptersKey = "dopishi.ai.customAdapters"

    @Published public var activeAdapterId: String {
        didSet {
            defaults.set(activeAdapterId, forKey: activeKey)
        }
    }

    @Published public private(set) var builtInAdapters: [LoRAAdapterDescriptor] = []
    @Published public private(set) var customAdapters: [LoRAAdapterDescriptor] = []

    public var allAdapters: [LoRAAdapterDescriptor] {
        builtInAdapters + customAdapters
    }

    public var activeAdapter: LoRAAdapterDescriptor? {
        allAdapters.first { $0.id == activeAdapterId } ?? builtInAdapters.first
    }

    public init() {
        self.activeAdapterId = defaults.string(forKey: activeKey) ?? "engineering"
        setupBuiltIns()
        loadCustomAdapters()
    }

    private func setupBuiltIns() {
        builtInAdapters = [
            LoRAAdapterDescriptor(
                id: "engineering",
                name: "Software Engineering",
                icon: "chevron.left.forwardslash.chevron.right",
                systemPromptRu: "Стиль: Разработка ПО. Отдавай предпочтение точным техническим терминам, именам функций, Markdown, Git коммитам и лаконичным фразам без лишней воды.",
                systemPromptEn: "Style: Software Engineering. Prefer technical precision, code identifiers, Markdown syntax, Git conventions, and concise expressions without filler.",
                temperature: 0.2
            ),
            LoRAAdapterDescriptor(
                id: "executive",
                name: "Executive & Business",
                icon: "briefcase.fill",
                systemPromptRu: "Стиль: Деловая переписка. Формулируй вежливо, дипломатично, структурированно, без фамильярности.",
                systemPromptEn: "Style: Executive & Business. Formulate politely, diplomatically, and structured, maintaining a professional corporate tone.",
                temperature: 0.25
            ),
            LoRAAdapterDescriptor(
                id: "casual",
                name: "Casual & Friendly",
                icon: "bubble.left.and.bubble.right.fill",
                systemPromptRu: "Стиль: Дружеский чат. Пиши естественно, непринужденно, живо, используя разговорные фразы.",
                systemPromptEn: "Style: Casual & Friendly. Write naturally, conversationally, and warmly.",
                temperature: 0.6
            ),
            LoRAAdapterDescriptor(
                id: "legal",
                name: "Legal & Contracts",
                icon: "scalemass.fill",
                systemPromptRu: "Стиль: Юридический. Используй строгие формулировки договоров, юридические термины, избегай двусмысленности.",
                systemPromptEn: "Style: Legal & Contracts. Use strict contractual terminology, precise legal phrasing, and eliminate ambiguities.",
                temperature: 0.15
            ),
            LoRAAdapterDescriptor(
                id: "marketing",
                name: "Marketing & Creative",
                icon: "sparkles",
                systemPromptRu: "Стиль: Маркетинг и копирайтинг. Пиши вовлекающе, выразительно, подчеркивая выгоды и эмоциональный отклик.",
                systemPromptEn: "Style: Marketing & Creative. Write engagingly, expressively, highlighting benefits and emotional resonance.",
                temperature: 0.5
            )
        ]
    }

    private func loadCustomAdapters() {
        guard let data = defaults.data(forKey: customAdaptersKey),
              let list = try? JSONDecoder().decode([LoRAAdapterDescriptor].self, from: data) else {
            return
        }
        self.customAdapters = list
    }

    public func addCustomAdapter(_ adapter: LoRAAdapterDescriptor) {
        customAdapters.removeAll { $0.id == adapter.id }
        customAdapters.append(adapter)
        if let data = try? JSONEncoder().encode(customAdapters) {
            defaults.set(data, forKey: customAdaptersKey)
        }
    }

    public func removeCustomAdapter(id: String) {
        customAdapters.removeAll { $0.id == id }
        if activeAdapterId == id {
            activeAdapterId = "engineering"
        }
        if let data = try? JSONEncoder().encode(customAdapters) {
            defaults.set(data, forKey: customAdaptersKey)
        }
    }

    public func personaPrompt(for isCyrillic: Bool) -> String? {
        guard let active = activeAdapter else { return nil }
        return isCyrillic ? active.systemPromptRu : active.systemPromptEn
    }

    public func effectiveTemperature(base: Float = 0.3) -> Float {
        return activeAdapter?.temperature ?? base
    }
}
