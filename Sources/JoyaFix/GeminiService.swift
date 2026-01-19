import Foundation
import CoreGraphics
import AppKit
import Security

/// Errors that can occur when interacting with Gemini API
enum GeminiServiceError: LocalizedError {
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
            return "Gemini API key not found. Please configure it in Settings."
        case .invalidURL:
            return "Invalid API URL configuration."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message ?? "Unknown error")"
        case .invalidResponse:
            return "Invalid response from Gemini API."
        case .emptyResponse:
            return "Empty response from Gemini API."
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

struct GeminiRequest: Encodable {
    struct Content: Encodable {
        struct Part: Encodable {
            let text: String?
            let inlineData: InlineData?
            
            enum CodingKeys: String, CodingKey {
                case text
                case inlineData = "inline_data"
            }
            
            // Custom encoding to ensure only one field is encoded at a time
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                
                // Only encode text if inlineData is nil
                if let text = text, inlineData == nil {
                    try container.encode(text, forKey: .text)
                }
                
                // Only encode inlineData if text is nil
                if let inlineData = inlineData, text == nil {
                    try container.encode(inlineData, forKey: .inlineData)
                }
                
                // If both are set, prioritize inlineData (for image parts)
                if let inlineData = inlineData, text != nil {
                    try container.encode(inlineData, forKey: .inlineData)
                }
            }
        }
        
        struct InlineData: Encodable {
            let mimeType: String
            let data: String
            
            enum CodingKeys: String, CodingKey {
                case mimeType = "mime_type"
                case data
            }
        }
        
        let parts: [Part]
    }
    
    struct GenerationConfig: Encodable {
        let temperature: Double
        let topK: Int
        let topP: Double
        let maxOutputTokens: Int
    }
    
    let contents: [Content]
    let generationConfig: GenerationConfig?
}

struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }
            let parts: [Part]?
        }
        let content: Content?
    }
    
    struct APIError: Decodable {
        let code: Int
        let message: String
    }
    
    let candidates: [Candidate]?
    let error: APIError?
}

/// Service for interacting with Google Gemini API
/// Handles both text-only and image-based requests
@MainActor
class GeminiService: NSObject, AIServiceProtocol {
    static let shared: GeminiService = {
        let instance = GeminiService()
        return instance
    }()
    
    private let settings = SettingsManager.shared
    private var urlSession: URLSession?
    
    private override init() {
        super.init()
        // Create URLSession with certificate pinning delegate
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        self.urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - Public API (AIServiceProtocol)
    
    /// Generates a response from Gemini API (async/await) with timeout protection
    func generateResponse(prompt: String) async throws -> String {
        // Add timeout protection to prevent indefinite hanging
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    Task { @MainActor in
                        self.sendPrompt(prompt) { result in
                            switch result {
                            case .success(let text):
                                continuation.resume(returning: text)
                            case .failure(let error):
                                // Convert GeminiServiceError to AIServiceError
                                let aiError = self.convertToAIServiceError(error)
                                continuation.resume(throwing: aiError)
                            }
                        }
                    }
                }
            }

            // Timeout task - 90 seconds max (includes URLSession's 60s timeout + buffer)
            group.addTask {
                try await Task.sleep(nanoseconds: 90_000_000_000)
                throw AIServiceError.networkError(NSError(
                    domain: "GeminiService",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Request timed out. Please try again."]
                ))
            }

            // Return first completed result or throw first error
            guard let result = try await group.next() else {
                group.cancelAll()
                throw AIServiceError.networkError(NSError(
                    domain: "GeminiService",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Request completed with no result. Please try again."]
                ))
            }
            group.cancelAll()
            return result
        }
    }
    
    /// Generates a response with agent configuration
    /// Gemini doesn't have a separate system role, so we inject agent instructions into the prompt
    func generateResponse(prompt: String, agent: JoyaAgent) async throws -> String {
        // Construct the full prompt with agent's system instructions
        let fullPrompt = """
        System: \(agent.systemInstructions)
        
        User: \(prompt)
        
        Assistant:
        """
        Logger.info("Gemini: Using agent '\(agent.name)' with injected system instructions")
        return try await generateResponse(prompt: fullPrompt)
    }
    
    /// Describes an image using Gemini's vision capabilities with timeout protection
    func describeImage(image: NSImage) async throws -> String {
        // Convert NSImage to base64
        guard let imageData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: imageData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            throw AIServiceError.encodingError(NSError(domain: "GeminiService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"]))
        }
        
        let base64Image = pngData.base64EncodedString()
        
        // Create vision prompt for "Nano Banano Style" description
        let visionPrompt = "Describe this image with extreme detail for an AI image generator. Include style, color palette, lighting (e.g., Rembrandt, volumetric), and lens info. Follow the 'Nano Banano' artistic style: concise yet vivid."
        
        // Add timeout protection to prevent indefinite hanging
        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    Task { @MainActor in
                        self.sendImagePrompt(imageBase64: base64Image, prompt: visionPrompt, attempt: 0) { result in
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
            }

            // Timeout task - 90 seconds max (includes URLSession's 60s timeout + buffer)
            group.addTask {
                try await Task.sleep(nanoseconds: 90_000_000_000)
                throw AIServiceError.networkError(NSError(
                    domain: "GeminiService",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Request timed out. Please try again."]
                ))
            }

            // Return first completed result or throw first error
            guard let result = try await group.next() else {
                group.cancelAll()
                throw AIServiceError.networkError(NSError(
                    domain: "GeminiService",
                    code: -1001,
                    userInfo: [NSLocalizedDescriptionKey: "Request completed with no result. Please try again."]
                ))
            }
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Public API (Result-based - deprecated)
    
    /// Sends a text prompt to Gemini API with retry logic
    @available(*, deprecated, message: "Use generateResponse(prompt:) async throws instead")
    func sendPrompt(_ prompt: String, completion: @escaping (Result<String, GeminiServiceError>) -> Void) {
        sendPromptWithRetry(prompt, attempt: 0, completion: completion)
    }
    
    
    // MARK: - Internal Logic
    
    /// Sends an image with a prompt to Gemini API
    /// FIXED: Separates text and image into separate parts to avoid oneof conflict
    private func sendImagePrompt(imageBase64: String, prompt: String, attempt: Int, completion: @escaping (Result<String, GeminiServiceError>) -> Void) {
        // Create separate parts: one for text, one for image
        // This avoids the "oneof field 'data' is already set. Cannot set 'inline_data'" error
        let parts: [GeminiRequest.Content.Part] = [
            // Text part (prompt)
            GeminiRequest.Content.Part(
                text: prompt,
                inlineData: nil
            ),
            // Image part (separate)
            GeminiRequest.Content.Part(
                text: nil,
                inlineData: GeminiRequest.Content.InlineData(
                    mimeType: "image/png",
                    data: imageBase64
                )
            )
        ]
        
        let requestBody = GeminiRequest(
            contents: [
                GeminiRequest.Content(parts: parts)
            ],
            generationConfig: GeminiRequest.GenerationConfig(
                temperature: 0.7,
                topK: 40,
                topP: 0.95,
                maxOutputTokens: 2048
            )
        )
        
        performRequest(requestBody: requestBody, attempt: attempt, context: "Vision Image Description", completion: completion)
    }
    
    private func sendPromptWithRetry(_ prompt: String, attempt: Int, completion: @escaping (Result<String, GeminiServiceError>) -> Void) {
        let requestBody = GeminiRequest(
            contents: [
                GeminiRequest.Content(parts: [GeminiRequest.Content.Part(text: prompt, inlineData: nil)])
            ],
            generationConfig: GeminiRequest.GenerationConfig(
                temperature: 0.7,
                topK: 40,
                topP: 0.95,
                maxOutputTokens: 2048
            )
        )
        
        performRequest(requestBody: requestBody, attempt: attempt, context: "Text Prompt", completion: completion)
    }
    
    
    private func performRequest(requestBody: GeminiRequest, attempt: Int, context: String, completion: @escaping (Result<String, GeminiServiceError>) -> Void) {
        // Enhanced logging: API Key verification
        let (apiKey, keySource) = getAPIKeyWithSource()
        guard let apiKey = apiKey else {
            Logger.security("Gemini API key not found - checked both Keychain and Settings", level: .error)
            completion(.failure(.apiKeyNotFound))
            return
        }
        
        // Log API key presence (length only, not the key itself)
        Logger.network("Gemini API key found (length: \(apiKey.count) chars, source: \(keySource))", level: .info)
        
        // Validate API key format (Gemini keys typically start with "AI" or are base64-like)
        if apiKey.count < 20 {
            Logger.security("Warning: API key seems too short (\(apiKey.count) chars). Expected ~39+ chars for Gemini keys.", level: .warning)
        }
        
        guard let url = URL(string: JoyaFixConstants.API.geminiBaseURL) else {
            Logger.network("Invalid Gemini API URL: \(JoyaFixConstants.API.geminiBaseURL)", level: .error)
            completion(.failure(.invalidURL))
            return
        }
        
        // Log full request URL
        Logger.network("Gemini API Request URL: \(url.absoluteString)", level: .debug)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // SECURITY FIX: Send API Key in Header instead of URL
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        
        // Log request headers (sanitized)
        #if DEBUG
        Logger.network("Request headers: Content-Type=application/json, x-goog-api-key=***\(apiKey.suffix(4))", level: .debug)
        #else
        Logger.network("Request headers: Content-Type=application/json, x-goog-api-key=[REDACTED]", level: .debug)
        #endif
        
        do {
            let requestBodyData = try JSONEncoder().encode(requestBody)
            request.httpBody = requestBodyData
            
            // Log request body structure (sanitized)
            if let requestBodyString = String(data: requestBodyData, encoding: .utf8) {
                let sanitized = requestBodyString.replacingOccurrences(of: apiKey, with: "***REDACTED***")
                Logger.network("Request body size: \(requestBodyData.count) bytes", level: .debug)
                Logger.network("Request body (first 500 chars): \(sanitized.prefix(500))", level: .debug)
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
                    self.handleNetworkError(error, attempt: attempt, context: context, requestBody: requestBody, completion: completion)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.network("Invalid response type - not HTTPURLResponse", level: .error)
                    completion(.failure(.networkError(NSError(domain: "InvalidResponse", code: 0))))
                    return
                }
                
                // Log HTTP status code and response headers
                Logger.network("HTTP Status Code: \(httpResponse.statusCode)", level: .info)
                Logger.network("Response headers: \(httpResponse.allHeaderFields)", level: .debug)
                
                guard let data = data else {
                    Logger.network("Response data is nil", level: .error)
                    completion(.failure(.emptyResponse))
                    return
                }
                
                // Log response body size
                Logger.network("Response body size: \(data.count) bytes", level: .debug)
                
                // Handle HTTP Errors
                if httpResponse.statusCode != 200 {
                    // Log raw response body for debugging (first 1000 chars)
                    if let responseString = String(data: data, encoding: .utf8) {
                        Logger.network("HTTP Error Response Body (first 1000 chars): \(responseString.prefix(1000))", level: .error)
                    }
                    self.handleHTTPError(statusCode: httpResponse.statusCode, data: data, attempt: attempt, context: context, requestBody: requestBody, completion: completion)
                    return
                }
                
                // Success Path
                do {
                    let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
                    
                    if let error = geminiResponse.error {
                        completion(.failure(.httpError(error.code, error.message)))
                        return
                    }
                    
                    guard let text = geminiResponse.candidates?.first?.content?.parts?.first?.text else {
                        Logger.network("Invalid response structure from Gemini API", level: .error)
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
    
    private func handleNetworkError(_ error: Error, attempt: Int, context: String, requestBody: GeminiRequest, completion: @escaping (Result<String, GeminiServiceError>) -> Void) {
        Logger.network("\(context) network error (attempt \(attempt + 1)): \(error.localizedDescription)", level: .error)
        
        if attempt < 2 {
            let delay = min(1.0 * pow(2.0, Double(attempt)), 5.0)
            Logger.network("Retrying in \(Int(delay)) seconds...", level: .info)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.performRequest(requestBody: requestBody, attempt: attempt + 1, context: context, completion: completion)
            }
        } else {
            completion(.failure(.networkError(error)))
        }
    }
    
    private func handleHTTPError(statusCode: Int, data: Data, attempt: Int, context: String, requestBody: GeminiRequest, completion: @escaping (Result<String, GeminiServiceError>) -> Void) {
        let errorMessage = String(data: data, encoding: .utf8)
        Logger.network("\(context) HTTP error: \(statusCode) - \(errorMessage ?? "No message")", level: .error)
        
        if statusCode >= 500 && attempt < 2 {
            let delay = min(1.0 * pow(2.0, Double(attempt)), 5.0)
            Logger.network("Server error, retrying in \(Int(delay)) seconds...", level: .info)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.performRequest(requestBody: requestBody, attempt: attempt + 1, context: context, completion: completion)
            }
        } else {
            completion(.failure(.httpError(statusCode, errorMessage)))
        }
    }
    
    // MARK: - Backward Compatibility (Legacy API)
    
    func sendPrompt(_ prompt: String, completion: @escaping (String?) -> Void) {
        sendPrompt(prompt) { result in
            switch result {
            case .success(let text): completion(text)
            case .failure: completion(nil)
            }
        }
    }
    
    
    // MARK: - Private Helpers
    
    private func getAPIKey() -> String? {
        let (key, _) = getAPIKeyWithSource()
        return key
    }
    
    private func getAPIKeyWithSource() -> (key: String?, source: String) {
        // Try Keychain first
        if let keychainKey = try? KeychainHelper.retrieveGeminiKey(), !keychainKey.isEmpty {
            Logger.network("API key retrieved from Keychain (length: \(keychainKey.count))", level: .debug)
            return (keychainKey, "Keychain")
        }
        
        // Fallback to Settings
        let settingsKey = settings.geminiKey
        if !settingsKey.isEmpty {
            Logger.network("API key retrieved from Settings (length: \(settingsKey.count))", level: .debug)
            return (settingsKey, "Settings")
        }
        
        Logger.network("API key not found in Keychain or Settings", level: .debug)
        return (nil, "None")
    }
    
    // MARK: - Error Conversion
    
    private func convertToAIServiceError(_ error: GeminiServiceError) -> AIServiceError {
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

// MARK: - URLSessionDelegate for Certificate Pinning
extension GeminiService: URLSessionDelegate {
    nonisolated func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.host == "generativelanguage.googleapis.com" else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // Use modern certificate validation API (macOS 10.14+)
        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            let errorDescription = error?.localizedDescription ?? "unknown"
            Logger.network("Certificate validation failed: \(errorDescription)", level: .error)
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
