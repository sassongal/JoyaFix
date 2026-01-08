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
        }
    }
}

