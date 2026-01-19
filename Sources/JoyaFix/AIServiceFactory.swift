import Foundation

/// Factory for creating AI service instances based on user settings
@MainActor
class AIServiceFactory {
    /// Creates and returns the appropriate AI service based on SettingsManager configuration
    /// - Returns: An instance conforming to AIServiceProtocol
    static func createService() -> AIServiceProtocol {
        let settings = SettingsManager.shared
        switch settings.selectedAIProvider {
        case .gemini:
            return GeminiService.shared
        case .openRouter:
            return OpenRouterService.shared
        case .local:
            return LocalLLMService.shared
        case .ollama:
            return OllamaService.shared
        }
    }
    
    /// Creates a service for vision tasks (image description)
    /// Falls back to best available option if selected provider doesn't support vision
    static func createVisionService() -> AIServiceProtocol {
        let settings = SettingsManager.shared
        
        switch settings.selectedAIProvider {
        case .gemini:
            // Gemini supports vision
            return GeminiService.shared
        case .openRouter:
            // Check if selected OpenRouter model supports vision
            let model = JoyaFixConstants.OpenRouterModel.fromModelID(settings.openRouterModel)
            if model.supportsVision {
                return OpenRouterService.shared
            }
            // Fall back to Gemini for vision
            return GeminiService.shared
        case .local:
            // Check if a vision model (LLaVA) is available
            let downloadManager = ModelDownloadManager.shared
            if downloadManager.downloadedModels.contains(where: { $0.info.supportsVision && $0.exists }) {
                return LocalLLMService.shared
            }
            // Fall back to Gemini
            return GeminiService.shared
        case .ollama:
            // Check if selected Ollama model supports vision
            if let selectedModel = settings.selectedOllamaModel,
               OllamaService.shared.modelSupportsVision(selectedModel) {
                return OllamaService.shared
            }
            // Check if any Ollama model supports vision
            if OllamaService.shared.availableModels.contains(where: { $0.supportsVision }) {
                return OllamaService.shared
            }
            // Fall back to Gemini
            return GeminiService.shared
        }
    }
    
    /// Checks if the current provider supports vision capabilities
    static func currentProviderSupportsVision() -> Bool {
        let settings = SettingsManager.shared
        
        switch settings.selectedAIProvider {
        case .gemini:
            return true  // Gemini always supports vision
        case .openRouter:
            let model = JoyaFixConstants.OpenRouterModel.fromModelID(settings.openRouterModel)
            return model.supportsVision
        case .local:
            let downloadManager = ModelDownloadManager.shared
            if let selectedId = settings.selectedLocalModel,
               let model = downloadManager.getDownloadedModel(byId: selectedId) {
                return model.info.supportsVision
            }
            return false
        case .ollama:
            if let selectedModel = settings.selectedOllamaModel {
                return OllamaService.shared.modelSupportsVision(selectedModel)
            }
            return false
        }
    }
    
    /// Gets a user-friendly message about vision capability
    static func getVisionCapabilityMessage() -> String? {
        if currentProviderSupportsVision() {
            return nil
        }
        
        let settings = SettingsManager.shared
        
        switch settings.selectedAIProvider {
        case .local:
            return NSLocalizedString("vision.local.not.supported", comment: "Download LLaVA for vision")
        case .ollama:
            return NSLocalizedString("vision.ollama.not.supported", comment: "Use LLaVA or Gemini for vision")
        case .openRouter:
            return NSLocalizedString("vision.openrouter.not.supported", comment: "Select a vision model")
        case .gemini:
            return nil  // Gemini always supports vision
        }
    }
}

