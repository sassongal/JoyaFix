import Foundation
import AppKit
import Security

/// Errors that can occur when interacting with OpenRouter API
enum OpenRouterServiceError: LocalizedError {
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
    
    var errorDescription: String? {
        switch self {
        case .apiKeyNotFound:
            return "OpenRouter API key not found. Please configure it in Settings > API Configuration."
        case .invalidURL:
            return "Invalid API URL configuration. Please check your network settings."
        case .networkError(let error):
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet:
                    return "No internet connection. Please check your network and try again."
                case NSURLErrorTimedOut:
                    return "Request timed out. Please check your internet connection and try again."
                case NSURLErrorCannotFindHost:
                    return "Cannot reach OpenRouter servers. Please check your internet connection."
                default:
                    return "Network error: \(error.localizedDescription). Please check your internet connection."
                }
            }
            return "Network error: \(error.localizedDescription). Please check your internet connection."
        case .httpError(let code, let message):
            switch code {
            case 401:
                return "Invalid API key. Please check your OpenRouter API key in Settings > API Configuration."
            case 403:
                return "API key access forbidden. Please verify your OpenRouter API key has the correct permissions."
            case 429:
                return "Rate limit exceeded. Please wait a moment and try again, or upgrade your OpenRouter plan."
            case 500...599:
                return "OpenRouter server error (\(code)). Please try again in a few moments."
            default:
                return "HTTP error \(code): \(message ?? "Unknown error"). Please try again or contact support if the problem persists."
            }
        case .invalidResponse:
            return "Invalid response from OpenRouter API. The server returned an unexpected format. Please try again."
        case .emptyResponse:
            return "Empty response from OpenRouter API. The request was successful but no content was returned. Please try again."
        case .rateLimitExceeded(let waitTime):
            return "Rate limit exceeded. Please wait \(Int(waitTime)) seconds before trying again."
        case .maxRetriesExceeded:
            return "Maximum retry attempts reached. Please check your internet connection and try again later."
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription). Please try again or contact support."
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription). The server may have returned an unexpected format. Please try again."
        }
    }
}

// MARK: - Codable Structs

struct OpenRouterRequest: Encodable {
    struct Message: Encodable {
        let role: String // "user" or "system"
        let content: String // For text prompts
        let contentArray: [VisionContent]? // For vision prompts
        
        init(role: String, content: String) {
            self.role = role
            self.content = content
            self.contentArray = nil
        }
        
        init(role: String, visionContent: [VisionContent]) {
            self.role = role
            self.content = ""
            self.contentArray = visionContent
        }
        
        struct VisionContent: Encodable {
            let type: String
            let text: String?
            let imageUrl: ImageURL?
            
            struct ImageURL: Encodable {
                let url: String
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case role, content
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            if let contentArray = contentArray {
                try container.encode(contentArray, forKey: .content)
            } else {
                try container.encode(content, forKey: .content)
            }
        }
    }
    
    let model: String
    let messages: [Message]
}

struct OpenRouterResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }
        let message: Message?
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }
    
    struct Error: Decodable {
        let message: String
        let type: String?
        let code: Int?
    }
    
    let choices: [Choice]?
    let error: Error?
}

/// Service for interacting with OpenRouter API
/// Supports multiple AI models through OpenRouter's unified API
@MainActor
class OpenRouterService: NSObject, AIServiceProtocol {
    static let shared: OpenRouterService = {
        let instance = OpenRouterService()
        return instance
    }()
    
    private let settings = SettingsManager.shared
    private var urlSession: URLSession?
    
    private override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        self.urlSession = URLSession(configuration: configuration)
    }
    
    // MARK: - AIServiceProtocol
    
    func generateResponse(prompt: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            sendPrompt(prompt, attempt: 0) { result in
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    let aiError = self.convertToAIServiceError(error)
                    continuation.resume(throwing: aiError)
                }
            }
        }
    }
    
    /// Describes an image using OpenRouter's vision-capable models
    func describeImage(image: NSImage) async throws -> String {
        // Convert NSImage to base64
        guard let imageData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: imageData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw AIServiceError.encodingError(NSError(domain: "OpenRouterService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"]))
        }
        
        let base64Image = pngData.base64EncodedString()
        
        // Create vision prompt for "Nano Banano Style" description
        let visionPrompt = "Describe this image with extreme detail for an AI image generator. Focus on lighting, style, lens, and composition. Style: Nano Banano artistic style (vivid and high-end)."
        
        return try await withCheckedThrowingContinuation { continuation in
            sendImagePrompt(imageBase64: base64Image, prompt: visionPrompt, attempt: 0) { result in
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    let aiError = self.convertToAIServiceError(error)
                    continuation.resume(throwing: aiError)
                }
            }
        }
    }
    
    // MARK: - Internal Logic
    
    /// Sends an image with a prompt to OpenRouter API using a vision-capable model
    private func sendImagePrompt(imageBase64: String, prompt: String, attempt: Int, completion: @escaping (Result<String, OpenRouterServiceError>) -> Void) {
        guard let apiKey = getAPIKey() else {
            Logger.security("OpenRouter API key not found", level: .error)
            completion(.failure(.apiKeyNotFound))
            return
        }
        
        // Use a vision-capable model (gemini-1.5-flash supports vision)
        let model = "google/gemini-1.5-flash"
        
        // For OpenRouter vision models, we need to format the content as an array
        // with text and image_url objects
        let imageDataUrl = "data:image/png;base64,\(imageBase64)"
        
        // For OpenRouter vision models, use the vision content format
        let visionContent = [
            OpenRouterRequest.Message.VisionContent(
                type: "text",
                text: prompt,
                imageUrl: nil
            ),
            OpenRouterRequest.Message.VisionContent(
                type: "image_url",
                text: nil,
                imageUrl: OpenRouterRequest.Message.VisionContent.ImageURL(url: imageDataUrl)
            )
        ]
        
        let requestBody = OpenRouterRequest(
            model: model,
            messages: [
                OpenRouterRequest.Message(role: "user", visionContent: visionContent)
            ]
        )
        
        performRequest(requestBody: requestBody, apiKey: apiKey, attempt: attempt, context: "Vision Image Description", completion: completion)
    }
    
    private func sendPrompt(_ prompt: String, attempt: Int, completion: @escaping (Result<String, OpenRouterServiceError>) -> Void) {
        guard let apiKey = getAPIKey() else {
            Logger.security("OpenRouter API key not found", level: .error)
            completion(.failure(.apiKeyNotFound))
            return
        }
        
        let model = settings.openRouterModel.isEmpty ? "deepseek/deepseek-chat" : settings.openRouterModel
        
        let requestBody = OpenRouterRequest(
            model: model,
            messages: [
                OpenRouterRequest.Message(role: "user", content: prompt)
            ]
        )
        
        performRequest(requestBody: requestBody, apiKey: apiKey, attempt: attempt, context: "OpenRouter Request", completion: completion)
    }
    
    private func performRequest(requestBody: OpenRouterRequest, apiKey: String, attempt: Int, context: String, completion: @escaping (Result<String, OpenRouterServiceError>) -> Void) {
        guard let url = URL(string: JoyaFixConstants.API.openRouterBaseURL) else {
            Logger.network("Invalid OpenRouter API URL: \(JoyaFixConstants.API.openRouterBaseURL)", level: .error)
            completion(.failure(.invalidURL))
            return
        }
        
        Logger.network("OpenRouter API Request URL: \(url.absoluteString)", level: .debug)
        Logger.network("OpenRouter API key found (length: \(apiKey.count) chars)", level: .info)
        Logger.network("Using model: \(requestBody.model)", level: .info)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("JoyaFix", forHTTPHeaderField: "X-Title")
        request.setValue("https://joyafix.app", forHTTPHeaderField: "HTTP-Referer")
        
        #if DEBUG
        Logger.network("Request headers: Content-Type=application/json, Authorization=Bearer ***\(apiKey.suffix(4)), X-Title=JoyaFix", level: .debug)
        #else
        Logger.network("Request headers: Content-Type=application/json, Authorization=Bearer [REDACTED], X-Title=JoyaFix", level: .debug)
        #endif
        
        do {
            let requestBodyData = try JSONEncoder().encode(requestBody)
            request.httpBody = requestBodyData
            
            if let requestBodyString = String(data: requestBodyData, encoding: .utf8) {
                Logger.network("Request body size: \(requestBodyData.count) bytes", level: .debug)
                Logger.network("Request body (first 500 chars): \(requestBodyString.prefix(500))", level: .debug)
            }
        } catch {
            Logger.network("Failed to encode request body: \(error.localizedDescription)", level: .error)
            completion(.failure(.encodingError(error)))
            return
        }
        
        let session = urlSession ?? URLSession.shared
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let error = error {
                    self.handleNetworkError(error, attempt: attempt, context: context, requestBody: requestBody, apiKey: apiKey, completion: completion)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.network("Invalid response type - not HTTPURLResponse", level: .error)
                    completion(.failure(.networkError(NSError(domain: "InvalidResponse", code: 0))))
                    return
                }
                
                Logger.network("HTTP Status Code: \(httpResponse.statusCode)", level: .info)
                Logger.network("Response headers: \(httpResponse.allHeaderFields)", level: .debug)
                
                guard let data = data else {
                    Logger.network("Response data is nil", level: .error)
                    completion(.failure(.emptyResponse))
                    return
                }
                
                Logger.network("Response body size: \(data.count) bytes", level: .debug)
                
                if httpResponse.statusCode != 200 {
                    if let responseString = String(data: data, encoding: .utf8) {
                        Logger.network("HTTP Error Response Body (first 1000 chars): \(responseString.prefix(1000))", level: .error)
                    }
                    self.handleHTTPError(statusCode: httpResponse.statusCode, data: data, attempt: attempt, context: context, requestBody: requestBody, apiKey: apiKey, completion: completion)
                    return
                }
                
                // Success Path
                do {
                    let openRouterResponse = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
                    
                    if let error = openRouterResponse.error {
                        Logger.network("OpenRouter API error: \(error.message)", level: .error)
                        completion(.failure(.httpError(error.code ?? 0, error.message)))
                        return
                    }
                    
                    guard let text = openRouterResponse.choices?.first?.message?.content else {
                        Logger.network("Invalid response structure from OpenRouter API", level: .error)
                        if let responseString = String(data: data, encoding: .utf8) {
                            Logger.network("Response: \(responseString.prefix(500))", level: .debug)
                        }
                        completion(.failure(.invalidResponse))
                        return
                    }
                    
                    let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanedText.isEmpty {
                        completion(.failure(.emptyResponse))
                    } else {
                        Logger.network("\(context) success: \(cleanedText.count) chars", level: .info)
                        completion(.success(cleanedText))
                    }
                    
                } catch {
                    Logger.network("Failed to decode JSON response: \(error.localizedDescription)", level: .error)
                    if let responseString = String(data: data, encoding: .utf8) {
                        Logger.network("Response: \(responseString.prefix(500))", level: .debug)
                    }
                    completion(.failure(.decodingError(error)))
                }
            }
        }
        task.resume()
    }
    
    // MARK: - Error Handling Helpers
    
    private func handleNetworkError(_ error: Error, attempt: Int, context: String, requestBody: OpenRouterRequest, apiKey: String, completion: @escaping (Result<String, OpenRouterServiceError>) -> Void) {
        Logger.network("\(context) network error (attempt \(attempt + 1)): \(error.localizedDescription)", level: .error)
        
        if attempt < 2 {
            let delay = min(1.0 * pow(2.0, Double(attempt)), 5.0)
            Logger.network("Retrying in \(Int(delay)) seconds...", level: .info)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.performRequest(requestBody: requestBody, apiKey: apiKey, attempt: attempt + 1, context: context, completion: completion)
            }
        } else {
            completion(.failure(.networkError(error)))
        }
    }
    
    private func handleHTTPError(statusCode: Int, data: Data, attempt: Int, context: String, requestBody: OpenRouterRequest, apiKey: String, completion: @escaping (Result<String, OpenRouterServiceError>) -> Void) {
        let errorMessage = String(data: data, encoding: .utf8)
        Logger.network("\(context) HTTP error: \(statusCode) - \(errorMessage ?? "No message")", level: .error)
        
        if statusCode >= 500 && attempt < 2 {
            let delay = min(1.0 * pow(2.0, Double(attempt)), 5.0)
            Logger.network("Server error, retrying in \(Int(delay)) seconds...", level: .info)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.performRequest(requestBody: requestBody, apiKey: apiKey, attempt: attempt + 1, context: context, completion: completion)
            }
        } else {
            completion(.failure(.httpError(statusCode, errorMessage)))
        }
    }
    
    // MARK: - Private Helpers
    
    private func getAPIKey() -> String? {
        // Priority 1: Try Keychain first (user's custom key)
        if let keychainKey = try? KeychainHelper.retrieveOpenRouterKey(), !keychainKey.isEmpty {
            Logger.network("OpenRouter API key retrieved from Keychain (length: \(keychainKey.count))", level: .debug)
            return keychainKey
        }
        
        // Priority 2: Fallback to Settings
        let settingsKey = settings.openRouterKey
        if !settingsKey.isEmpty {
            Logger.network("OpenRouter API key retrieved from Settings (length: \(settingsKey.count))", level: .debug)
            return settingsKey
        }
        
        // Priority 3: Check environment variable (for development use only)
        if let envKey = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !envKey.isEmpty {
            Logger.network("OpenRouter API key retrieved from environment variable", level: .debug)
            return envKey
        }

        Logger.network("OpenRouter API key not found in any source", level: .debug)
        return nil
    }
    
    // MARK: - Error Conversion
    
    private func convertToAIServiceError(_ error: OpenRouterServiceError) -> AIServiceError {
        switch error {
        case .apiKeyNotFound:
            return .apiKeyNotFound
        case .invalidURL:
            return .invalidURL
        case .networkError(let err):
            return .networkError(err)
        case .httpError(let code, let message):
            return .httpError(code, message)
        case .invalidResponse:
            return .invalidResponse
        case .emptyResponse:
            return .emptyResponse
        case .rateLimitExceeded(let waitTime):
            return .rateLimitExceeded(waitTime)
        case .maxRetriesExceeded:
            return .maxRetriesExceeded
        case .encodingError(let err):
            return .encodingError(err)
        case .decodingError(let err):
            return .decodingError(err)
        }
    }
}

