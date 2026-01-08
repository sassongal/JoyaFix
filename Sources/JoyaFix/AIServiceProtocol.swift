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
        }
    }
}

