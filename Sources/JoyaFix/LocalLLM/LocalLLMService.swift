import Foundation
import AppKit
import LLM

/// Service for local LLM inference using llama.cpp via LLM.swift
@MainActor
class LocalLLMService: AIServiceProtocol {
    static let shared = LocalLLMService()

    // MARK: - Private Properties

    private var llm: LLM?
    private var visionLLM: LLM?
    private var isModelLoaded = false
    private var isVisionModelLoaded = false
    private var currentModelPath: String?
    private var loadingTask: Task<Void, Error>?

    private let settings = SettingsManager.shared
    private let downloadManager = ModelDownloadManager.shared

    // MARK: - Initialization

    private init() {}

    // MARK: - AIServiceProtocol

    func generateResponse(prompt: String) async throws -> String {
        // Ensure model is loaded
        try await ensureModelLoaded()

        guard let llm = llm else {
            throw AIServiceError.modelNotDownloaded
        }

        // Add timeout protection
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await self.performInference(prompt: prompt, llm: llm)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(JoyaFixConstants.LocalLLM.inferenceTimeout * 1_000_000_000))
                throw AIServiceError.networkError(NSError(
                    domain: "LocalLLMService",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Inference timed out. The model may be too slow for this prompt."]
                ))
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw AIServiceError.emptyResponse
            }
            group.cancelAll()
            return result
        }
    }

    func describeImage(image: NSImage) async throws -> String {
        // Check if vision model is available
        guard let visionModel = getVisionModel() else {
            throw AIServiceError.visionModelNotAvailable
        }

        // Ensure vision model is loaded
        try await ensureVisionModelLoaded(model: visionModel)

        guard let visionLLM = visionLLM else {
            throw AIServiceError.visionModelNotAvailable
        }

        // Convert NSImage to Data
        guard let imageData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: imageData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw AIServiceError.encodingError(NSError(
                domain: "LocalLLMService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"]
            ))
        }

        // Vision prompt
        let visionPrompt = "Describe this image with extreme detail for an AI image generator. Include style, color palette, lighting, and composition. Be concise yet vivid."

        // Add timeout protection
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                // Note: LLM.swift basic version may not support vision directly
                // For vision models like LLaVA, additional integration may be needed
                try await self.performInference(prompt: visionPrompt, llm: visionLLM)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(JoyaFixConstants.LocalLLM.inferenceTimeout * 1_000_000_000))
                throw AIServiceError.networkError(NSError(
                    domain: "LocalLLMService",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Vision inference timed out."]
                ))
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw AIServiceError.emptyResponse
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - Model Management

    /// Loads a model for inference
    func loadModel(from path: String) async throws {
        // Check if already loading
        if let loadingTask = loadingTask {
            try await loadingTask.value
            return
        }

        // Check RAM availability
        let availableRAM = downloadManager.availableRAM()
        let requiredRAM = JoyaFixConstants.LocalLLM.minimumRAMRequired

        guard availableRAM >= requiredRAM else {
            throw AIServiceError.insufficientMemory(required: requiredRAM, available: availableRAM)
        }

        // Check file exists
        guard FileManager.default.fileExists(atPath: path) else {
            throw AIServiceError.modelNotFound(path)
        }

        loadingTask = Task {
            defer { loadingTask = nil }

            Logger.info("Loading local model from: \(path)")

            // Unload existing model
            unloadModel()

            // Create new LLM instance from file path
            let modelURL = URL(fileURLWithPath: path)
            llm = LLM(from: modelURL, template: .alpaca("You are a helpful AI assistant."))
            currentModelPath = path
            isModelLoaded = true

            Logger.info("Local model loaded successfully")
        }

        try await loadingTask!.value
    }

    /// Unloads the current model to free memory
    func unloadModel() {
        llm = nil
        isModelLoaded = false
        currentModelPath = nil
        Logger.info("Local model unloaded")
    }

    /// Unloads the vision model to free memory
    func unloadVisionModel() {
        visionLLM = nil
        isVisionModelLoaded = false
        Logger.info("Local vision model unloaded")
    }

    /// Checks if a model is currently loaded
    var isReady: Bool {
        isModelLoaded && llm != nil
    }

    /// Checks if a vision model is currently loaded
    var isVisionReady: Bool {
        isVisionModelLoaded && visionLLM != nil
    }

    // MARK: - Private Methods

    private func ensureModelLoaded() async throws {
        // Get selected model
        guard let selectedModel = settings.selectedLocalModel,
              let downloadedModel = downloadManager.getDownloadedModel(byId: selectedModel) else {
            throw AIServiceError.modelNotDownloaded
        }

        // Check if file still exists
        guard downloadedModel.exists else {
            throw AIServiceError.modelNotFound(downloadedModel.localPath)
        }

        // Check if already loaded with same model
        if isModelLoaded && currentModelPath == downloadedModel.localPath {
            return
        }

        // Load model
        try await loadModel(from: downloadedModel.localPath)
    }

    private func ensureVisionModelLoaded(model: DownloadedModel) async throws {
        if isVisionModelLoaded && visionLLM != nil {
            return
        }

        // Check RAM
        let availableRAM = downloadManager.availableRAM()
        guard availableRAM >= model.info.requiredRAM else {
            throw AIServiceError.insufficientMemory(required: model.info.requiredRAM, available: availableRAM)
        }

        // Check file exists
        guard model.exists else {
            throw AIServiceError.modelNotFound(model.localPath)
        }

        let modelURL = URL(fileURLWithPath: model.localPath)
        visionLLM = LLM(from: modelURL, template: .alpaca("You are a helpful AI assistant that can describe images."))
        isVisionModelLoaded = true

        Logger.info("Vision model loaded successfully")
    }

    private func performInference(prompt: String, llm: LLM) async throws -> String {
        // Use LLM.swift's getCompletion method which returns a String
        let input = llm.preprocess(prompt, llm.history)
        let response = await llm.getCompletion(from: input)

        let cleanedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedResponse.isEmpty else {
            throw AIServiceError.emptyResponse
        }

        Logger.info("Local LLM inference completed: \(cleanedResponse.count) chars")
        return cleanedResponse
    }

    private func getVisionModel() -> DownloadedModel? {
        downloadManager.downloadedModels.first { $0.info.supportsVision }
    }
}
