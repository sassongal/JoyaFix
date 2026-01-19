import Foundation
import AppKit

/// Represents an Ollama model from the /api/tags endpoint
struct OllamaModel: Codable, Identifiable {
    let name: String
    let model: String?
    let modifiedAt: String?
    let size: Int64?
    let digest: String?
    let details: OllamaModelDetails?
    
    var id: String { name }
    
    enum CodingKeys: String, CodingKey {
        case name, model, size, digest, details
        case modifiedAt = "modified_at"
    }
    
    /// Whether this model supports vision (based on name/family)
    var supportsVision: Bool {
        let visionModels = ["llava", "bakllava", "moondream", "cogvlm"]
        let lowerName = name.lowercased()
        return visionModels.contains { lowerName.contains($0) }
    }
    
    /// Display name for UI
    var displayName: String {
        // Remove tag if present (e.g., "llama3:latest" -> "Llama 3")
        let baseName = name.components(separatedBy: ":").first ?? name
        return baseName.capitalized
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }
    
    /// Formatted size for display
    var sizeFormatted: String {
        guard let size = size else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct OllamaModelDetails: Codable {
    let parentModel: String?
    let format: String?
    let family: String?
    let families: [String]?
    let parameterSize: String?
    let quantizationLevel: String?
    
    enum CodingKeys: String, CodingKey {
        case parentModel = "parent_model"
        case format, family, families
        case parameterSize = "parameter_size"
        case quantizationLevel = "quantization_level"
    }
}

/// Response from Ollama /api/tags endpoint
struct OllamaTagsResponse: Codable {
    let models: [OllamaModel]
}

/// Response from Ollama /api/generate endpoint
struct OllamaGenerateResponse: Codable {
    let model: String
    let createdAt: String?
    let response: String
    let done: Bool
    let context: [Int]?
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let promptEvalDuration: Int64?
    let evalCount: Int?
    let evalDuration: Int64?
    
    enum CodingKeys: String, CodingKey {
        case model, response, done, context
        case createdAt = "created_at"
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

/// Service for interacting with local Ollama installation
@MainActor
class OllamaService: AIServiceProtocol, ObservableObject {
    static let shared = OllamaService()
    
    // MARK: - Published Properties
    
    @Published var availableModels: [OllamaModel] = []
    @Published var isOllamaRunning: Bool = false
    @Published var lastError: Error?
    
    // MARK: - Private Properties
    
    private let settings = SettingsManager.shared
    private let session: URLSession
    
    // MARK: - Initialization
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config)
        
        // Check Ollama status on init
        Task {
            await checkOllamaStatus()
        }
    }
    
    // MARK: - AIServiceProtocol
    
    func generateResponse(prompt: String) async throws -> String {
        // Use default agent if not specified
        return try await generateResponse(prompt: prompt, agent: .default)
    }
    
    /// Generate response with a specific agent configuration
    func generateResponse(prompt: String, agent: JoyaAgent) async throws -> String {
        // Get selected model
        guard let modelName = settings.selectedOllamaModel else {
            throw AIServiceError.providerSpecific("No Ollama model selected. Please select a model in Settings.")
        }
        
        // Build request
        let endpoint = settings.ollamaEndpoint + JoyaFixConstants.API.ollamaGenerateEndpoint
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build prompt with agent's system instructions
        let fullPrompt = """
        System: \(agent.systemInstructions)
        
        User: \(prompt)
        
        Assistant:
        """
        
        let body: [String: Any] = [
            "model": modelName,
            "prompt": fullPrompt,
            "stream": false,
            "options": [
                "temperature": agent.temperature,
                "num_predict": agent.maxTokens
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        Logger.info("Sending request to Ollama: \(modelName)")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                
                if httpResponse.statusCode == 404 {
                    throw AIServiceError.providerSpecific("Model '\(modelName)' not found in Ollama. Please pull it first: ollama pull \(modelName)")
                }
                
                throw AIServiceError.httpError(httpResponse.statusCode, errorMessage)
            }
            
            let generateResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            
            let cleanedResponse = generateResponse.response.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !cleanedResponse.isEmpty else {
                throw AIServiceError.emptyResponse
            }
            
            // Log performance stats
            if let totalDuration = generateResponse.totalDuration {
                let durationMs = Double(totalDuration) / 1_000_000
                Logger.info("Ollama inference completed with agent '\(agent.name)' in \(String(format: "%.0f", durationMs))ms")
            }
            
            return cleanedResponse
            
        } catch let error as AIServiceError {
            throw error
        } catch let error as URLError {
            if error.code == .cannotConnectToHost || error.code == .timedOut {
                isOllamaRunning = false
                throw AIServiceError.providerSpecific("Cannot connect to Ollama. Make sure Ollama is running (ollama serve)")
            }
            throw AIServiceError.networkError(error)
        } catch {
            throw AIServiceError.networkError(error)
        }
    }
    
    func describeImage(image: NSImage) async throws -> String {
        // Get selected model
        guard let modelName = settings.selectedOllamaModel else {
            throw AIServiceError.providerSpecific("No Ollama model selected. Please select a model in Settings.")
        }
        
        // Check if model supports vision
        let model = availableModels.first { $0.name == modelName }
        if let model = model, !model.supportsVision {
            throw AIServiceError.providerSpecific(
                NSLocalizedString("ollama.vision.not.supported", comment: "Model doesn't support vision") +
                "\nCurrent model: \(modelName)\n" +
                NSLocalizedString("ollama.vision.suggestion", comment: "Use LLaVA or Gemini")
            )
        }
        
        // Convert image to base64
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw AIServiceError.encodingError(NSError(
                domain: "OllamaService",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"]
            ))
        }
        
        let base64Image = pngData.base64EncodedString()
        
        // Build request
        let endpoint = settings.ollamaEndpoint + JoyaFixConstants.API.ollamaGenerateEndpoint
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let visionPrompt = "Describe this image with extreme detail for an AI image generator. Include style, color palette, lighting, composition, and mood. Be concise yet vivid."
        
        let body: [String: Any] = [
            "model": modelName,
            "prompt": visionPrompt,
            "images": [base64Image],
            "stream": false,
            "options": [
                "temperature": 0.7,
                "num_predict": 1024
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        Logger.info("Sending vision request to Ollama: \(modelName)")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIServiceError.httpError(httpResponse.statusCode, errorMessage)
            }
            
            let generateResponse = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            
            let cleanedResponse = generateResponse.response.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !cleanedResponse.isEmpty else {
                throw AIServiceError.emptyResponse
            }
            
            return cleanedResponse
            
        } catch let error as AIServiceError {
            throw error
        } catch {
            throw AIServiceError.networkError(error)
        }
    }
    
    // MARK: - Ollama Management
    
    /// Checks if Ollama is running
    func checkOllamaStatus() async {
        let endpoint = settings.ollamaEndpoint + JoyaFixConstants.API.ollamaTagsEndpoint
        guard let url = URL(string: endpoint) else {
            isOllamaRunning = false
            return
        }
        
        do {
            let (_, response) = try await session.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                isOllamaRunning = httpResponse.statusCode == 200
            } else {
                isOllamaRunning = false
            }
        } catch {
            isOllamaRunning = false
            Logger.warning("Ollama not running: \(error.localizedDescription)")
        }
    }
    
    /// Fetches available models from Ollama
    func fetchAvailableModels() async throws -> [OllamaModel] {
        let endpoint = settings.ollamaEndpoint + JoyaFixConstants.API.ollamaTagsEndpoint
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidURL
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIServiceError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw AIServiceError.httpError(httpResponse.statusCode, "Failed to fetch models")
            }
            
            let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            
            availableModels = tagsResponse.models
            isOllamaRunning = true
            
            Logger.info("Found \(tagsResponse.models.count) Ollama models")
            
            return tagsResponse.models
            
        } catch let error as URLError {
            isOllamaRunning = false
            
            if error.code == .cannotConnectToHost || error.code == .timedOut {
                throw AIServiceError.providerSpecific("Cannot connect to Ollama. Make sure Ollama is running:\n\n1. Open Terminal\n2. Run: ollama serve")
            }
            throw AIServiceError.networkError(error)
        } catch let error as AIServiceError {
            throw error
        } catch {
            throw AIServiceError.networkError(error)
        }
    }
    
    /// Gets model details from Ollama
    func getModelDetails(modelName: String) async throws -> OllamaModel? {
        let endpoint = settings.ollamaEndpoint + JoyaFixConstants.API.ollamaShowEndpoint
        guard let url = URL(string: endpoint) else {
            throw AIServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["name": modelName]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        
        // The /api/show endpoint returns model details
        // We extract what we need for our OllamaModel struct
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let details = OllamaModelDetails(
                parentModel: json["parent_model"] as? String,
                format: json["format"] as? String,
                family: json["family"] as? String,
                families: json["families"] as? [String],
                parameterSize: json["parameter_size"] as? String,
                quantizationLevel: json["quantization_level"] as? String
            )
            
            return OllamaModel(
                name: modelName,
                model: modelName,
                modifiedAt: nil,
                size: json["size"] as? Int64,
                digest: nil,
                details: details
            )
        }
        
        return nil
    }
    
    /// Checks if a specific model supports vision
    func modelSupportsVision(_ modelName: String) -> Bool {
        if let model = availableModels.first(where: { $0.name == modelName }) {
            return model.supportsVision
        }
        
        // Check by name pattern if not in cache
        let visionModels = ["llava", "bakllava", "moondream", "cogvlm"]
        return visionModels.contains { modelName.lowercased().contains($0) }
    }
}

// MARK: - Ollama Errors Extension

extension AIServiceError {
    static var ollamaNotRunning: AIServiceError {
        .providerSpecific(NSLocalizedString("ollama.not.running", comment: "Ollama is not running"))
    }
    
    static var ollamaModelNotSelected: AIServiceError {
        .providerSpecific(NSLocalizedString("ollama.model.not.selected", comment: "No Ollama model selected"))
    }
}
