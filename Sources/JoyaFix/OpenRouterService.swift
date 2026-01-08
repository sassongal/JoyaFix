import Foundation
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
            return "OpenRouter API key not found. Please configure it in Settings."
        case .invalidURL:
            return "Invalid API URL configuration."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message ?? "Unknown error")"
        case .invalidResponse:
            return "Invalid response from OpenRouter API."
        case .emptyResponse:
            return "Empty response from OpenRouter API."
        case .rateLimitExceeded(let waitTime):
            return "Rate limit exceeded. Please wait \(Int(waitTime)) seconds."
        case .maxRetriesExceeded:
            return "Maximum retry attempts reached."
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

// MARK: - Codable Structs

struct OpenRouterRequest: Encodable {
    struct Message: Encodable {
        let role: String // "user" or "system"
        let content: String
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
    
    // MARK: - Internal Logic
    
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
        
        Logger.network("Request headers: Content-Type=application/json, Authorization=Bearer ***\(apiKey.suffix(4)), X-Title=JoyaFix", level: .debug)
        
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
        // Try Keychain first
        if let keychainKey = try? KeychainHelper.retrieveOpenRouterKey(), !keychainKey.isEmpty {
            Logger.network("OpenRouter API key retrieved from Keychain (length: \(keychainKey.count))", level: .debug)
            return keychainKey
        }
        
        // Fallback to Settings
        let settingsKey = settings.openRouterKey
        if !settingsKey.isEmpty {
            Logger.network("OpenRouter API key retrieved from Settings (length: \(settingsKey.count))", level: .debug)
            return settingsKey
        }
        
        Logger.network("OpenRouter API key not found in Keychain or Settings", level: .debug)
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

