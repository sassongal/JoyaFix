import Foundation
import CoreGraphics
import AppKit

/// Service for interacting with Google Gemini API
/// Handles both text-only and image-based requests
@MainActor
class GeminiService {
    static let shared = GeminiService()
    
    private let settings = SettingsManager.shared
    
    private init() {}
    
    // MARK: - Public API
    
    /// Sends a text prompt to Gemini API
    /// - Parameters:
    ///   - prompt: The text prompt to send
    ///   - completion: Called with the response text or nil on error
    func sendPrompt(_ prompt: String, completion: @escaping (String?) -> Void) {
        guard let apiKey = getAPIKey() else {
            print("❌ Gemini API key not found")
            completion(nil)
            return
        }
        
        guard let url = URL(string: "\(JoyaFixConstants.API.geminiBaseURL)?key=\(apiKey)") else {
            print("❌ Invalid API URL")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [ "text": prompt ]
                    ]
                ]
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Failed to create JSON request body")
            completion(nil)
            return
        }
        
        request.httpBody = jsonData
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Gemini API network error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    print("❌ Gemini API HTTP error: \(httpResponse.statusCode)")
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("   Response: \(errorString.prefix(200))")
                    }
                    completion(nil)
                    return
                }
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    print("⚠️ Gemini API: Invalid response structure")
                    completion(nil)
                    return
                }
                
                let responseText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if responseText.isEmpty {
                    print("⚠️ Gemini API: Empty response")
                    completion(nil)
                } else {
                    print("✓ Gemini API success: \(responseText.count) characters")
                    completion(responseText)
                }
            } catch {
                print("❌ Failed to parse JSON response: \(error.localizedDescription)")
                completion(nil)
            }
        }
        
        task.resume()
    }
    
    /// Sends an image with optional text prompt to Gemini API for OCR
    /// - Parameters:
    ///   - image: The CGImage to process
    ///   - prompt: Optional text prompt (defaults to OCR prompt)
    ///   - completion: Called with the extracted text or nil on error
    func performOCR(image: CGImage, prompt: String? = nil, completion: @escaping (String?) -> Void) {
        // Check rate limiting
        guard OCRRateLimiter.shared.canMakeRequest() else {
            let waitTime = OCRRateLimiter.shared.timeUntilNextRequest()
            let requestCount = OCRRateLimiter.shared.currentRequestCount
            print("⚠️ Cloud OCR rate limit reached. Please wait \(Int(waitTime)) seconds.")
            
            // Show user-friendly alert
            showRateLimitAlert(waitTime: Int(waitTime), requestCount: requestCount)
            completion(nil)
            return
        }
        
        // Record the request
        OCRRateLimiter.shared.recordRequest()
        
        guard let apiKey = getAPIKey() else {
            print("❌ Gemini API key not found")
            completion(nil)
            return
        }
        
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: JoyaFixConstants.cloudOCRCompressionFactor]) else {
            print("❌ Failed to convert image to JPEG")
            completion(nil)
            return
        }
        
        let base64Image = jpegData.base64EncodedString()
        
        guard let url = URL(string: "\(JoyaFixConstants.API.geminiBaseURL)?key=\(apiKey)") else {
            print("❌ Invalid API URL")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        let ocrPrompt = prompt ?? "Extract text from this image exactly as it appears. Preserve Hebrew perfectly. Output ONLY the raw text."
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [ "text": ocrPrompt ],
                        [ "inline_data": [ "mime_type": "image/jpeg", "data": base64Image ] ]
                    ]
                ]
            ]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            print("❌ Failed to create JSON request body")
            completion(nil)
            return
        }
        
        request.httpBody = jsonData
        
        // Perform OCR with retry logic
        performOCRWithRetry(request: request, attempt: 0, completion: completion)
    }
    
    // MARK: - Private Helpers
    
    private func getAPIKey() -> String? {
        // Try Keychain first, then fallback to settings
        if let keychainKey = KeychainHelper.retrieveGeminiKey(), !keychainKey.isEmpty {
            return keychainKey
        }
        
        let settingsKey = settings.geminiKey
        if !settingsKey.isEmpty {
            return settingsKey
        }
        
        return nil
    }
    
    private func performOCRWithRetry(request: URLRequest, attempt: Int, completion: @escaping (String?) -> Void) {
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                print("❌ Cloud OCR network error (attempt \(attempt + 1)): \(error.localizedDescription)")
                
                // Retry with exponential backoff
                if attempt < JoyaFixConstants.ocrMaxRetryAttempts {
                    let delay = min(
                        JoyaFixConstants.ocrRetryInitialDelay * pow(2.0, Double(attempt)),
                        JoyaFixConstants.ocrRetryMaxDelay
                    )
                    print("🔄 Retrying in \(Int(delay)) seconds...")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self?.performOCRWithRetry(request: request, attempt: attempt + 1, completion: completion)
                    }
                } else {
                    print("❌ Max retry attempts reached")
                    completion(nil)
                }
                return
            }
            
            // Handle HTTP status codes
            if let httpResponse = response as? HTTPURLResponse {
                // Handle rate limit (429)
                if httpResponse.statusCode == 429 {
                    print("⚠️ Cloud OCR rate limit exceeded (HTTP 429)")
                    let waitTime = OCRRateLimiter.shared.timeUntilNextRequest()
                    let requestCount = OCRRateLimiter.shared.currentRequestCount
                    Task { @MainActor in
                        self.showRateLimitAlert(waitTime: Int(waitTime), requestCount: requestCount)
                    }
                    completion(nil)
                    return
                }
                
                // Handle other errors
                if httpResponse.statusCode != 200 {
                    print("❌ Cloud OCR HTTP error: \(httpResponse.statusCode)")
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        print("   Response: \(errorString.prefix(200))")
                    }
                    completion(nil)
                    return
                }
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let firstCandidate = candidates.first,
                      let content = firstCandidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let firstPart = parts.first,
                      let text = firstPart["text"] as? String else {
                    print("⚠️ Cloud OCR: Invalid response structure")
                    completion(nil)
                    return
                }
                
                let extractedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if extractedText.isEmpty {
                    print("⚠️ Cloud OCR: Empty text extracted")
                    completion(nil)
                } else {
                    print("✓ Cloud OCR success (attempt \(attempt + 1)): \(extractedText.count) characters")
                    completion(extractedText)
                }
            } catch {
                print("❌ Failed to parse JSON response: \(error.localizedDescription)")
                completion(nil)
            }
        }
        
        task.resume()
    }
    
    /// Shows a user-friendly alert when rate limit is reached
    private func showRateLimitAlert(waitTime: Int, requestCount: Int) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.rate.limit.title", comment: "Cloud OCR Rate Limit")
        alert.informativeText = String(format: NSLocalizedString("alert.rate.limit.message", comment: "Rate limit message"),
                                       JoyaFixConstants.maxCloudOCRRequestsPerMinute,
                                       waitTime)
        alert.alertStyle = .warning
        
        // Add "Open Settings" button to switch to Local OCR
        alert.addButton(withTitle: NSLocalizedString("alert.button.open.settings", comment: "Open Settings"))
        alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open Settings window
            SettingsWindowController.shared.show()
        }
    }
}

