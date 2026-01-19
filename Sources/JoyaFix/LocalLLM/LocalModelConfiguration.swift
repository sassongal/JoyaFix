import Foundation

/// Represents a downloadable local LLM model
struct LocalModelInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let description: String
    let downloadURL: URL
    let fileSize: UInt64  // in bytes
    let requiredRAM: UInt64  // in bytes
    let supportsVision: Bool
    let quantization: String  // e.g., "Q4_K_M"
    let contextLength: Int
    
    /// SHA256 checksum for download integrity verification (optional for external/discovered models)
    let sha256Checksum: String?
    
    /// Tolerance percentage for file size verification (0.05 = 5%)
    let fileSizeTolerance: Double

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var requiredRAMFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(requiredRAM), countStyle: .memory)
    }
    
    /// Initialize with all parameters
    init(id: String, name: String, displayName: String, description: String, downloadURL: URL, fileSize: UInt64, requiredRAM: UInt64, supportsVision: Bool, quantization: String, contextLength: Int, sha256Checksum: String? = nil, fileSizeTolerance: Double = 0.01) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.description = description
        self.downloadURL = downloadURL
        self.fileSize = fileSize
        self.requiredRAM = requiredRAM
        self.supportsVision = supportsVision
        self.quantization = quantization
        self.contextLength = contextLength
        self.sha256Checksum = sha256Checksum
        self.fileSizeTolerance = fileSizeTolerance
    }
}

/// Source of a discovered model
enum ModelSource: String, Codable {
    case downloaded      // Downloaded via JoyaFix
    case ollama          // Discovered in Ollama
    case external        // Found in system (e.g., ~/.ollama/models or other GGUF files)
}

/// Represents a downloaded or discovered model on disk
struct DownloadedModel: Codable, Identifiable {
    let id: String
    let info: LocalModelInfo
    let localPath: String
    let downloadedAt: Date
    
    /// Whether this model was discovered externally (not downloaded through JoyaFix)
    var isExternal: Bool
    
    /// Source of the model
    var source: ModelSource
    
    /// Ollama model name (if from Ollama)
    var ollamaModelName: String?

    var exists: Bool {
        // For Ollama models, we check differently
        if source == .ollama {
            return true // Ollama manages existence
        }
        return FileManager.default.fileExists(atPath: localPath)
    }
    
    /// Display status for UI
    var statusDisplay: String {
        switch source {
        case .downloaded:
            return exists ? "Downloaded" : "File missing"
        case .ollama:
            return "Available in Ollama"
        case .external:
            return exists ? "Available on system" : "File missing"
        }
    }
    
    // Legacy initializer for backward compatibility
    init(id: String, info: LocalModelInfo, localPath: String, downloadedAt: Date) {
        self.id = id
        self.info = info
        self.localPath = localPath
        self.downloadedAt = downloadedAt
        self.isExternal = false
        self.source = .downloaded
        self.ollamaModelName = nil
    }
    
    // Full initializer
    init(id: String, info: LocalModelInfo, localPath: String, downloadedAt: Date, isExternal: Bool, source: ModelSource, ollamaModelName: String? = nil) {
        self.id = id
        self.info = info
        self.localPath = localPath
        self.downloadedAt = downloadedAt
        self.isExternal = isExternal
        self.source = source
        self.ollamaModelName = ollamaModelName
    }
}

/// Hardware optimization level for models
enum ModelOptimization: String, Codable {
    case appleSiliconOptimized = "apple_silicon"  // Best for M1/M2/M3
    case universal = "universal"                   // Works well on all hardware
    case intelCompatible = "intel"                 // Optimized for Intel
}

/// Registry of available models for download
struct LocalModelRegistry {
    static let availableModels: [LocalModelInfo] = [
        LocalModelInfo(
            id: "llama-3.2-3b-instruct",
            name: "llama-3.2-3b-instruct-q4_k_m",
            displayName: "Llama 3.2 3B Instruct",
            description: "Meta's efficient 3B parameter model, optimized for instruction following",
            downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf")!,
            fileSize: 2_100_000_000,  // ~2.1GB
            requiredRAM: 4_000_000_000,  // ~4GB
            supportsVision: false,
            quantization: "Q4_K_M",
            contextLength: 8192,
            sha256Checksum: nil,  // Placeholder - to be updated with actual checksum
            fileSizeTolerance: 0.01  // 1% tolerance for size verification
        ),
        LocalModelInfo(
            id: "gemma-2-2b-instruct",
            name: "gemma-2-2b-instruct-q4_k_m",
            displayName: "Gemma 2 2B Instruct",
            description: "Google's lightweight 2B model, fast and efficient",
            downloadURL: URL(string: "https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf")!,
            fileSize: 1_500_000_000,  // ~1.5GB
            requiredRAM: 3_000_000_000,  // ~3GB
            supportsVision: false,
            quantization: "Q4_K_M",
            contextLength: 8192,
            sha256Checksum: nil,  // Placeholder - to be updated with actual checksum
            fileSizeTolerance: 0.01  // 1% tolerance for size verification
        ),
        LocalModelInfo(
            id: "llava-1.5-7b",
            name: "llava-1.5-7b-q4_k",
            displayName: "LLaVA 1.5 7B (Vision)",
            description: "Multimodal model supporting image understanding",
            downloadURL: URL(string: "https://huggingface.co/mys/ggml_llava-v1.5-7b/resolve/main/ggml-model-q4_k.gguf")!,
            fileSize: 4_000_000_000,  // ~4GB
            requiredRAM: 8_000_000_000,  // ~8GB
            supportsVision: true,
            quantization: "Q4_K",
            contextLength: 4096,
            sha256Checksum: nil,  // Placeholder - to be updated with actual checksum
            fileSizeTolerance: 0.01  // 1% tolerance for size verification
        )
    ]

    static func model(withId id: String) -> LocalModelInfo? {
        availableModels.first { $0.id == id }
    }
    
    /// Gets the recommended model for the detected hardware
    static func recommendedModel() -> LocalModelInfo? {
        // Gemma 2B is recommended for all hardware - small, fast, efficient
        return model(withId: "gemma-2-2b-instruct")
    }
    
    /// Gets models sorted by recommendation for the hardware
    @MainActor
    static func modelsSortedByRecommendation() -> [LocalModelInfo] {
        let service = LocalLLMService.shared
        
        // Sort: recommended first, then by file size (smaller = faster)
        return availableModels.sorted { model1, model2 in
            let rec1 = service.isModelRecommended(model1)
            let rec2 = service.isModelRecommended(model2)
            
            if rec1 != rec2 {
                return rec1  // Recommended models first
            }
            
            // Then by file size (smaller first)
            return model1.fileSize < model2.fileSize
        }
    }
    
    /// Gets models that are suitable for Intel Macs
    static func intelCompatibleModels() -> [LocalModelInfo] {
        // Models under 2.5GB work reasonably well on Intel
        return availableModels.filter { $0.fileSize <= 2_500_000_000 }
    }
    
    /// Checks if a model is suitable for the current system's RAM
    static func isModelSuitableForSystem(_ model: LocalModelInfo) -> Bool {
        let availableRAM = ProcessInfo.processInfo.physicalMemory
        // Model should use at most 60% of physical RAM
        return model.requiredRAM <= UInt64(Double(availableRAM) * 0.6)
    }
}
