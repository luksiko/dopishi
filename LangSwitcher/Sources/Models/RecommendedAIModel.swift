import Foundation

// MARK: - Recommended AI Model

struct RecommendedAIModel: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let descriptionKey: String
    let sizeText: String
    let ramTier: String
    let ramTierKey: String
    let estimatedSizeBytes: Int64
    let fileName: String
    let downloadURL: URL
    let isDefault: Bool
    
    var isCustom: Bool {
        id == Self.customModelID
    }
    
    static let defaultModelID = "qwen2.5-0.5b"
    static let customModelID = "custom-gguf"
    
    static let allModels: [RecommendedAIModel] = [
        RecommendedAIModel(
            id: "qwen2.5-0.5b",
            name: "Qwen 2.5 0.5B Instruct",
            descriptionKey: "ai.model.desc.qwen05b",
            sizeText: "~390 MB",
            ramTier: "8 GB",
            ramTierKey: "ai.model.tier.8gb",
            estimatedSizeBytes: 491_400_032,
            fileName: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf")!,
            isDefault: true
        ),
        RecommendedAIModel(
            id: "smollm2-360m",
            name: "SmolLM2 360M Instruct",
            descriptionKey: "ai.model.desc.smollm360m",
            sizeText: "~229 MB",
            ramTier: "8 GB",
            ramTierKey: "ai.model.tier.8gb",
            estimatedSizeBytes: 240_000_000,
            fileName: "smollm2-360m-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q4_k_m.gguf")!,
            isDefault: false
        ),
        RecommendedAIModel(
            id: "llama-3.2-1b",
            name: "Llama 3.2 1B Instruct",
            descriptionKey: "ai.model.desc.llama1b",
            sizeText: "~770 MB",
            ramTier: "8–16 GB",
            ramTierKey: "ai.model.tier.8_16gb",
            estimatedSizeBytes: 808_000_000,
            fileName: "Llama-3.2-1B-Instruct-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf")!,
            isDefault: false
        ),
        RecommendedAIModel(
            id: "qwen2.5-coder-1.5b",
            name: "Qwen 2.5 Coder 1.5B",
            descriptionKey: "ai.model.desc.qwencoder15b",
            sizeText: "~986 MB",
            ramTier: "8–16 GB",
            ramTierKey: "ai.model.tier.8_16gb",
            estimatedSizeBytes: 1_030_000_000,
            fileName: "qwen2.5-coder-1.5b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf")!,
            isDefault: false
        ),
        RecommendedAIModel(
            id: "smollm2-1.7b",
            name: "SmolLM2 1.7B Instruct",
            descriptionKey: "ai.model.desc.smollm17b",
            sizeText: "~1.06 GB",
            ramTier: "8–16 GB",
            ramTierKey: "ai.model.tier.8_16gb",
            estimatedSizeBytes: 1_140_000_000,
            fileName: "smollm2-1.7b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/main/smollm2-1.7b-instruct-q4_k_m.gguf")!,
            isDefault: false
        ),
        RecommendedAIModel(
            id: "qwen2.5-1.5b",
            name: "Qwen 2.5 1.5B Instruct",
            descriptionKey: "ai.model.desc.qwen15b",
            sizeText: "~986 MB",
            ramTier: "8–16 GB",
            ramTierKey: "ai.model.tier.8_16gb",
            estimatedSizeBytes: 1_030_000_000,
            fileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
            isDefault: false
        ),
        RecommendedAIModel(
            id: "gemma-2-2b",
            name: "Gemma 2 2B Instruct",
            descriptionKey: "ai.model.desc.gemma2b",
            sizeText: "~1.6 GB",
            ramTier: "16–24 GB",
            ramTierKey: "ai.model.tier.16_24gb",
            estimatedSizeBytes: 1_750_000_000,
            fileName: "gemma-2-2b-it-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf")!,
            isDefault: false
        ),
        RecommendedAIModel(
            id: "gemma-4-e2b",
            name: "Gemma 4 E2B",
            descriptionKey: "ai.model.desc.gemma4e2b",
            sizeText: "~3.5 GB",
            ramTier: "16–24+ GB",
            ramTierKey: "ai.model.tier.16_24gb",
            estimatedSizeBytes: 3_467_429_152,
            fileName: "gemma-4-E2B-i1-Q4_K_M.gguf",
            downloadURL: URL(string: "https://huggingface.co/mradermacher/gemma-4-E2B-i1-GGUF/resolve/main/gemma-4-E2B-i1-Q4_K_M.gguf")!,
            isDefault: false
        ),
        RecommendedAIModel(
            id: "qwen2.5-3b",
            name: "Qwen 2.5 3B Instruct",
            descriptionKey: "ai.model.desc.qwen3b",
            sizeText: "~2.0 GB",
            ramTier: "24+ GB",
            ramTierKey: "ai.model.tier.24gb",
            estimatedSizeBytes: 2_100_000_000,
            fileName: "qwen2.5-3b-instruct-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf")!,
            isDefault: false
        )
    ]
    
    static func customModel(for path: String) -> RecommendedAIModel {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = (trimmed as NSString).lastPathComponent
        let displayName = fileName.isEmpty ? "Custom Model" : fileName
        
        var fileSize: Int64 = 0
        if !trimmed.isEmpty,
           let attrs = try? FileManager.default.attributesOfItem(atPath: trimmed),
           let size = attrs[.size] as? Int64 {
            fileSize = size
        }
        
        let sizeText: String
        if fileSize > 0 {
            let sizeGB = Double(fileSize) / (1024 * 1024 * 1024)
            if sizeGB >= 1.0 {
                sizeText = String(format: "~%.1f GB", sizeGB)
            } else {
                let sizeMB = Double(fileSize) / (1024 * 1024)
                sizeText = String(format: "~%.0f MB", sizeMB)
            }
        } else {
            sizeText = ""
        }
        
        return RecommendedAIModel(
            id: customModelID,
            name: displayName,
            descriptionKey: "ai.model.desc.custom",
            sizeText: sizeText,
            ramTier: "Custom",
            ramTierKey: "ai.model.tier.custom",
            estimatedSizeBytes: fileSize,
            fileName: trimmed,
            downloadURL: URL(fileURLWithPath: trimmed.isEmpty ? "/" : trimmed),
            isDefault: false
        )
    }
    
    static func model(for id: String) -> RecommendedAIModel {
        if id == customModelID {
            let customPath = UserDefaults.standard.string(forKey: "customModelPath") ?? ""
            return customModel(for: customPath)
        }
        return allModels.first(where: { $0.id == id }) ?? allModels[0]
    }
    
    func localizedSize(language: String) -> String {
        if language == "ru" {
            return sizeText
                .replacingOccurrences(of: "MB", with: "МБ")
                .replacingOccurrences(of: "GB", with: "ГБ")
        }
        return sizeText
    }
    
    @MainActor
    func localizedSize(using l10n: LocalizationManager) -> String {
        localizedSize(language: l10n.currentLanguage)
    }
}
