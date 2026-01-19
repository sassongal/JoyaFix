import Foundation
import Cocoa
import Cocoa

/// Manages AI-powered prompt enhancement
/// Converts user's raw input into professional, structured LLM prompts
@MainActor
class PromptEnhancerManager: ObservableObject {
    static let shared = PromptEnhancerManager()
    
    private let settings = SettingsManager.shared
    
    /// Loading state for prompt enhancement
    @Published var isEnhancing = false
    @Published var enhancementStatus: String = ""

    /// Task reference for cancellation support
    private var enhancementTask: Task<Void, Never>?

    private init() {}

    /// Cancels the current enhancement operation
    func cancelEnhancement() {
        enhancementTask?.cancel()
        isEnhancing = false
        enhancementStatus = ""
        AILoadingOverlayWindowController.dismiss()
        showToast("Enhancement cancelled", style: .info)
    }
    
    // MARK: - Meta-Prompt Template
    
    /// The system prompt used to enhance user input into professional prompts
    /// Enhanced with more detailed instructions for better results
    private func createMetaPrompt(userText: String) -> String {
        // "Prompt Cowboy" Level - CO-STAR Framework Implementation
        // This structural approach ensures maximum quality from the LLM.
        
        return """
You are an elite Prompt Engineer specializing in the CO-STAR framework. Your mission is to transform raw, potentially vague inputs into high-performance, structured prompts for LLMs.

**INPUT DATA:**
"\(userText)"

**INSTRUCTIONS:**
Analyze the input above and rewrite it into a powerful, structured prompt using the CO-STAR framework.

**CO-STAR FRAMEWORK:**
1. **C - Context:** Provide background information or setting. (Who is the user? What is the scenario?)
2. **O - Objective:** Define the task clearly. (What exactly do you want the AI to do?)
3. **S - Style:** Specify the writing style. (e.g., Professional, Academic, Creative, Concise).
4. **T - Tone:** Set the emotional tone. (e.g., Authoritative, Friendly, Empathetic).
5. **A - Audience:** Identify who the response is for. (e.g., Developers, Customers, Executives).
6. **R - Response:** Define the output format. (e.g., JSON, Markdown list, Boolean).

**CRITICAL RULES:**
1. **Language Preservation:** If the INPUT DATA is in Hebrew (or mostly Hebrew), the generated prompt MUST be in Hebrew (Context, Objective, etc. should be written in Hebrew). If English, use English.
2. **Expansion:** Infer missing details to make the prompt robust. Don't just copy the input; enhance it.
3. **No Meta-Talk:** Do NOT output "Here is your prompt". Output ONLY the structured prompt.
4. **Formatting:** Use Markdown headers for each section (# Context, # Objective, etc.).

**OUTPUT:**
Generate the CO-STAR prompt now.
"""
    }
    
    // MARK: - Public API
    
    /// Enhances selected text by converting it to a professional prompt
    /// Flow: Copy → Enhance → Paste
    func enhanceSelectedText() {
        // Step 0: Ensure app is hidden to capture correct selection
        NSApp.hide(nil)
        
        // Step 1: Check Accessibility permissions (with fresh check)
        // Force refresh to ensure we have the latest permission status
        let hasAccessibility = PermissionManager.shared.refreshAccessibilityStatus()
        
        guard hasAccessibility else {
            Logger.error("Accessibility permission required but not granted")
            showToast("Accessibility permission required for prompt enhancement", style: .warning)
            showPermissionRequiredAlert()
            return
        }
        
        // Step 2: Check if API key is available
        if hasAPIKey() {
            let providerName = settings.selectedAIProvider == .gemini ? "Gemini" : "OpenRouter"
            Logger.info("✅ \(providerName) API Key verified. Starting enhancement process.")
        } else {
            let providerName = settings.selectedAIProvider == .gemini ? "Gemini" : "OpenRouter"
            Logger.error("❌ \(providerName) API Key NOT found in Settings or Keychain.")
            showToast("\(providerName) API key required. Please configure in Settings.", style: .error)
            showAPIKeyRequiredAlert()
            return
        }
        
        // Set loading state
        isEnhancing = true
        enhancementStatus = "Copying selected text..."

        // Show prominent loading overlay
        AILoadingOverlayWindowController.show(
            initialStatus: "Copying selected text...",
            onCancel: { [weak self] in
                self?.cancelEnhancement()
            }
        )
        
        Task {
            // Step 3: Double-check permissions before attempting to copy (in case they changed)
            // This is important because the user might have granted permission after the initial check
            let stillHasAccessibility = PermissionManager.shared.refreshAccessibilityStatus()
            guard stillHasAccessibility else {
                Task { @MainActor in
                    isEnhancing = false
                    enhancementStatus = ""
                    AILoadingOverlayWindowController.dismiss()
                    showToast("Accessibility permission required. Please grant it in System Settings.", style: .error)
                    showPermissionRequiredAlert()
                }
                return
            }
            
            // Step 4 & 5: Copy and Read (Async)
            Task { @MainActor in
                enhancementStatus = "Reading selected text..."
                AILoadingOverlayWindowController.updateStatus("Reading selected text...")
            }
            
            guard let selectedText = await ClipboardHelper.getSelectedText() else {
                Task { @MainActor in
                    isEnhancing = false
                    enhancementStatus = ""
                    AILoadingOverlayWindowController.dismiss()
                    showToast("No text selected. Please select text to enhance.", style: .warning)
                    self.showErrorAlert(message: NSLocalizedString("prompt.enhancer.error.no.text", comment: "No text selected"))
                }
                return
            }

            if selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Task { @MainActor in
                    isEnhancing = false
                    enhancementStatus = ""
                    AILoadingOverlayWindowController.dismiss()
                    showToast("Selected text is empty", style: .warning)
                    self.showErrorAlert(message: NSLocalizedString("prompt.enhancer.error.no.text", comment: "No text selected"))
                }
                return
            }
            
            // Step 6: Create meta-prompt and send to AI service
            let metaPrompt = self.createMetaPrompt(userText: selectedText)
            let providerName = settings.selectedAIProvider == .gemini ? "Gemini" : "OpenRouter"
            
            Task { @MainActor in
                enhancementStatus = "Enhancing with \(providerName)..."
                AILoadingOverlayWindowController.updateStatus("AI is analyzing your text...")
            }
            
            Task { @MainActor in
                do {
                    let service = AIServiceFactory.createService()
                    let enhancedPrompt = try await service.generateResponse(prompt: metaPrompt)
                    
                    Logger.info("Enhanced prompt: '\(enhancedPrompt.prefix(100))...'")

                    // Play success sound when enhancement succeeds
                    SoundManager.shared.playSuccess()

                    // Clear loading state and dismiss overlay
                    isEnhancing = false
                    enhancementStatus = ""
                    AILoadingOverlayWindowController.dismiss()

                    showToast("Prompt enhanced successfully!", style: .success)

                    // Step 7: Show review window instead of pasting immediately
                    self.showReviewWindow(enhancedPrompt: enhancedPrompt, originalText: selectedText)
                } catch {
                    Logger.network("Failed to enhance prompt: \(error.localizedDescription)", level: .error)
                    isEnhancing = false
                    enhancementStatus = ""
                    AILoadingOverlayWindowController.dismiss()
                    showToast("Failed to enhance prompt. Please try again.", style: .error)
                    // Convert to GeminiServiceError for backward compatibility with error handling
                    let geminiError = self.convertToGeminiServiceError(error)
                    self.showErrorAlertWithDetails(error: geminiError)
                }
            }
        }
    }
    
    /// Shows the review window for the enhanced prompt
    private func showReviewWindow(enhancedPrompt: String, originalText: String) {
        // Store original text for refine operations
        let storedOriginalText = originalText
        
        // Create a mutable reference for the prompt
        class PromptHolder {
            var value: String
            init(_ value: String) { self.value = value }
        }
        let promptHolder = PromptHolder(enhancedPrompt)
        
        func showWindowWithPrompt(_ prompt: String) {
            PromptReviewWindowController.show(
                promptText: prompt,
                onConfirm: {
                    // User confirmed - paste the prompt
                    self.confirmAndPaste(prompt: promptHolder.value)
                },
                onCancel: {
                    // User cancelled - do nothing
                },
                onRefine: { refineRequest in
                    // User wants to refine the prompt
                    self.refinePrompt(currentPrompt: promptHolder.value, originalText: storedOriginalText, refineRequest: refineRequest) { refinedPrompt in
                        if let refined = refinedPrompt {
                            promptHolder.value = refined
                            // Update the window with new prompt
                            showWindowWithPrompt(refined)
                        }
                    }
                }
            )
        }
        
        showWindowWithPrompt(enhancedPrompt)
    }
    
    /// Confirms and pastes the prompt
    private func confirmAndPaste(prompt: String) {
        // Notify clipboard manager to ignore this write
        ClipboardHistoryManager.shared.notifyInternalWrite()
        
        Task {
            // Write enhanced prompt to clipboard
            ClipboardHelper.writeToClipboard(prompt)
            
            // Play success sound
            SoundManager.shared.playSuccess()
            
            // Delete selected text first (Async wait) + Paste
            NSApp.hide(nil)
            
            // Wait for app hide
            try? await Task.sleep(nanoseconds: 100 * 1_000_000)
            
            ClipboardHelper.simulateDelete()
            
            // Wait a bit before pasting
            try? await Task.sleep(nanoseconds: 200 * 1_000_000)
            
            ClipboardHelper.simulatePaste()
        }
    }
    
    /// Refines the prompt based on user request
    private func refinePrompt(currentPrompt: String, originalText: String, refineRequest: String, completion: @escaping (String?) -> Void) {
        let role = NSLocalizedString("prompt.enhancer.meta.role", comment: "Meta prompt role")
        let refineTask = NSLocalizedString("prompt.enhancer.refine.task", comment: "Refine prompt task")
        let originalInput = NSLocalizedString("prompt.enhancer.refine.original.input", comment: "Refine prompt original input")
        let currentPromptLabel = NSLocalizedString("prompt.enhancer.refine.current.prompt", comment: "Refine prompt current prompt")
        let refineRequestLabel = NSLocalizedString("prompt.enhancer.refine.request", comment: "Refine prompt request")
        let rules = NSLocalizedString("prompt.enhancer.meta.rules", comment: "Meta prompt rules label")
        let refineRule1 = NSLocalizedString("prompt.enhancer.refine.rule1", comment: "Refine prompt rule 1")
        let refineRule2 = NSLocalizedString("prompt.enhancer.refine.rule2", comment: "Refine prompt rule 2")
        let refineRule3 = NSLocalizedString("prompt.enhancer.refine.rule3", comment: "Refine prompt rule 3")
        
        let refinePrompt = """
\(role)
\(refineTask)
\(originalInput): "\(originalText)"
\(currentPromptLabel):
\(currentPrompt)
\(refineRequestLabel): "\(refineRequest)"
\(rules):
1. \(refineRule1)
2. \(refineRule2)
3. \(refineRule3)
"""
        
        Task { @MainActor in
            enhancementStatus = "Refining prompt..."
            showToast("Refining prompt...", style: .info)
            do {
                let service = AIServiceFactory.createService()
                let refinedPrompt = try await service.generateResponse(prompt: refinePrompt)

                // Play success sound when refinement succeeds
                SoundManager.shared.playSuccess()
                showToast("Prompt refined successfully!", style: .success)
                enhancementStatus = ""
                completion(refinedPrompt)
            } catch {
                Logger.network("Failed to refine prompt: \(error.localizedDescription)", level: .error)
                showToast("Failed to refine prompt. Please try again.", style: .error)
                enhancementStatus = ""
                completion(nil)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func hasAPIKey() -> Bool {
        // Check API key based on selected provider
        switch settings.selectedAIProvider {
        case .gemini:
            // Check Keychain first, then settings
            if let keychainKey = try? KeychainHelper.retrieveGeminiKey(), !keychainKey.isEmpty {
                return true
            }
            return !settings.geminiKey.isEmpty
        case .openRouter:
            // Check Keychain first, then settings
            if let keychainKey = try? KeychainHelper.retrieveOpenRouterKey(), !keychainKey.isEmpty {
                return true
            }
            return !settings.openRouterKey.isEmpty
        case .local:
            // Local models don't require an API key, just check if a model is selected
            return settings.selectedLocalModel != nil
        }
    }
    
    // MARK: - Helper Methods Removed
    // Code moved to ClipboardHelper.swift to prevent duplication

    
    // MARK: - Alerts
    
    private func showPermissionRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.accessibility.title", comment: "Accessibility Permission Required")
        alert.informativeText = """
        JoyaFix needs Accessibility permission to use the AI Prompt Enhancer.
        
        This permission allows the app to:
        • Copy selected text automatically
        • Simulate keyboard shortcuts (Cmd+C, Cmd+V, Delete)
        • Replace text with the enhanced prompt
        
        To grant permission:
        1. Click "Open Settings" below
        2. Check the box next to "JoyaFix" in the list
        3. Return to this app and try again
        
        Note: You may need to restart JoyaFix after granting permission.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Invalidate cache before opening settings
            PermissionManager.shared.invalidateCache()
            PermissionManager.shared.openAccessibilitySettings()
            
            // Show a follow-up message after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let followUpAlert = NSAlert()
                followUpAlert.messageText = "Permission Granted?"
                followUpAlert.informativeText = """
                If you've granted Accessibility permission, please:
                
                1. Return to JoyaFix
                2. Try the Prompt Enhancer again (⌘⌥P or from menu)
                
                If the permission was already granted, you may need to restart JoyaFix.
                """
                followUpAlert.alertStyle = .informational
                followUpAlert.addButton(withTitle: "OK")
                followUpAlert.runModal()
                
                // Refresh permission status after user returns
                _ = PermissionManager.shared.refreshAccessibilityStatus()
            }
        }
    }
    
    private func showAPIKeyRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("prompt.enhancer.error.api.key.title", comment: "API key required")
        alert.informativeText = NSLocalizedString("prompt.enhancer.error.api.key.message", comment: "API key required message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("alert.button.open.settings", comment: "Open settings"))
        alert.addButton(withTitle: NSLocalizedString("alert.button.cancel", comment: "Cancel"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            SettingsWindowController.shared.show()
        }
    }
    
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.error.title", comment: "Error alert title")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
        alert.runModal()
    }
    
    /// Converts AIServiceError to GeminiServiceError for backward compatibility
    private func convertToGeminiServiceError(_ error: Error) -> GeminiServiceError {
        if let aiError = error as? AIServiceError {
            switch aiError {
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
            case .providerSpecific(let message):
                return .httpError(0, message)
            case .modelNotFound(let path):
                return .httpError(0, "Model not found at: \(path)")
            case .modelLoadFailed(let reason):
                return .httpError(0, "Failed to load model: \(reason)")
            case .insufficientMemory(let required, let available):
                let requiredGB = Double(required) / 1_073_741_824
                let availableGB = Double(available) / 1_073_741_824
                return .httpError(0, String(format: "Insufficient memory. Required: %.1fGB, Available: %.1fGB", requiredGB, availableGB))
            case .inferenceError(let reason):
                return .httpError(0, "Inference error: \(reason)")
            case .modelNotDownloaded:
                return .httpError(0, "No local model downloaded. Please download a model in Settings.")
            case .visionModelNotAvailable:
                return .httpError(0, "Vision model not available.")
            }
        }
        // Fallback for unknown errors
        return .networkError(error)
    }
    
    /// Shows a user-friendly error alert with specific guidance based on error type
    private func showErrorAlertWithDetails(error: GeminiServiceError) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("prompt.enhancer.error.title", comment: "Prompt Enhancement Error")
        
        var informativeText: String
        var showSettingsButton = false
        
        switch error {
        case .apiKeyNotFound:
            informativeText = NSLocalizedString("prompt.enhancer.error.api.key.detailed", comment: "API key not found detailed")
            showSettingsButton = true
        case .invalidURL:
            informativeText = NSLocalizedString("prompt.enhancer.error.invalid.url", comment: "Invalid URL error")
        case .networkError(let underlyingError):
            informativeText = String(format: NSLocalizedString("prompt.enhancer.error.network.detailed", comment: "Network error detailed"), underlyingError.localizedDescription)
        case .httpError(let code, let message):
            if code == 401 {
                informativeText = NSLocalizedString("prompt.enhancer.error.api.key.invalid", comment: "API key invalid")
                showSettingsButton = true
            } else if code == 403 {
                informativeText = NSLocalizedString("prompt.enhancer.error.api.key.forbidden", comment: "API key forbidden")
                showSettingsButton = true
            } else if code == 429 {
                informativeText = NSLocalizedString("prompt.enhancer.error.rate.limit", comment: "Rate limit error")
            } else {
                informativeText = String(format: NSLocalizedString("prompt.enhancer.error.http", comment: "HTTP error"), code, message ?? "Unknown")
            }
        case .rateLimitExceeded(let waitTime):
            informativeText = String(format: NSLocalizedString("prompt.enhancer.error.rate.limit.wait", comment: "Rate limit wait"), Int(waitTime))
        case .invalidResponse, .emptyResponse:
            informativeText = NSLocalizedString("prompt.enhancer.error.invalid.response", comment: "Invalid response")
        case .maxRetriesExceeded:
            informativeText = NSLocalizedString("prompt.enhancer.error.max.retries", comment: "Max retries exceeded")
        case .encodingError(let error):
            informativeText = "Encoding Error: \(error.localizedDescription)"
        case .decodingError(let error):
            informativeText = "Decoding Error: \(error.localizedDescription)"
        }
        
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        
        if showSettingsButton {
            alert.addButton(withTitle: NSLocalizedString("alert.button.open.settings", comment: "Open Settings"))
            alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                SettingsWindowController.shared.show()
            }
        } else {
            alert.addButton(withTitle: NSLocalizedString("alert.button.ok", comment: "OK"))
            alert.runModal()
        }
    }
}

