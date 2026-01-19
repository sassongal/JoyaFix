import Foundation
import AppKit

/// Protocol for AI service providers
/// All AI services must conform to this protocol to ensure consistent interface
@MainActor
protocol AIServiceProtocol {
    /// Generates a response from the AI service given a prompt
    /// - Parameter prompt: The text prompt to send to the AI service
    /// - Returns: The generated response text
    /// - Throws: An error if the request fails
    func generateResponse(prompt: String) async throws -> String
    
    /// Describes an image using vision capabilities
    /// - Parameter image: The NSImage to describe
    /// - Returns: A detailed description of the image suitable for image generation prompts
    /// - Throws: An error if the request fails
    func describeImage(image: NSImage) async throws -> String
}

/// Common error type for AI services
enum AIServiceError: LocalizedError {
    case apiKeyNotFound
    case invalidURL
    case networkError(Error)
    case httpError(Int, String?)
    case invalidResponse
    case emptyResponse
    case rateLimitExceeded(TimeInterval)
    case maxRetriesExceeded
    case encodingError(Error)
    case decodingError(Error)
    case providerSpecific(String)

    // Local LLM specific errors
    case modelNotFound(String)
    case modelLoadFailed(String)
    case insufficientMemory(required: UInt64, available: UInt64)
    case inferenceError(String)
    case modelNotDownloaded
    case visionModelNotAvailable

    var errorDescription: String? {
        switch self {
        case .apiKeyNotFound:
            return "API key not found. Please configure it in Settings."
        case .invalidURL:
            return "Invalid API URL configuration."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message ?? "Unknown error")"
        case .invalidResponse:
            return "Invalid response from AI service."
        case .emptyResponse:
            return "Empty response from AI service."
        case .rateLimitExceeded(let waitTime):
            return "Rate limit exceeded. Please wait \(Int(waitTime)) seconds."
        case .maxRetriesExceeded:
            return "Maximum retry attempts reached."
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .providerSpecific(let message):
            return message
        case .modelNotFound(let path):
            return "Model file not found at: \(path)"
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .insufficientMemory(let required, let available):
            let requiredGB = Double(required) / 1_073_741_824
            let availableGB = Double(available) / 1_073_741_824
            return String(format: "Insufficient memory. Required: %.1fGB, Available: %.1fGB", requiredGB, availableGB)
        case .inferenceError(let reason):
            return "Inference error: \(reason)"
        case .modelNotDownloaded:
            return "No local model downloaded. Please download a model in Settings."
        case .visionModelNotAvailable:
            return "Vision model not available. Please download a vision-capable model (LLaVA) in Settings."
        }
    }
}

