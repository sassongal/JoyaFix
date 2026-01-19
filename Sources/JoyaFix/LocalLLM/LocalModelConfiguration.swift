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

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    var requiredRAMFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(requiredRAM), countStyle: .memory)
    }
}

/// Represents a downloaded model on disk
struct DownloadedModel: Codable, Identifiable {
    let id: String
    let info: LocalModelInfo
    let localPath: String
    let downloadedAt: Date

    var exists: Bool {
        FileManager.default.fileExists(atPath: localPath)
    }
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
            contextLength: 8192
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
            contextLength: 8192
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
            contextLength: 4096
        )
    ]

    static func model(withId id: String) -> LocalModelInfo? {
        availableModels.first { $0.id == id }
    }
}
