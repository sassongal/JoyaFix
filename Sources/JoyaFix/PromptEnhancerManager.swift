import Foundation
import Cocoa
import Cocoa

/// Manages AI-powered prompt enhancement
/// Converts user's raw input into professional, structured LLM prompts
@MainActor
class PromptEnhancerManager {
    static let shared = PromptEnhancerManager()
    
    private let settings = SettingsManager.shared
    
    private init() {}
    
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
        
        // Step 1: Check Accessibility permissions
        guard PermissionManager.shared.isAccessibilityTrusted() else {
            print("⚠️ Accessibility permission missing for prompt enhancement")
            showPermissionRequiredAlert()
            return
        }
        
        // Step 2: Check if API key is available
        if hasAPIKey() {
            Logger.info("✅ Gemini API Key verified. Starting enhancement process.")
        } else {
            Logger.error("❌ Gemini API Key NOT found in Settings or Keychain.")
            print("⚠️ Gemini API key not found")
            showAPIKeyRequiredAlert()
            return
        }
        
        Task {
            // Step 3 & 4 & 5: Copy and Read (Async)
            guard let selectedText = await ClipboardHelper.getSelectedText() else {
                print("❌ No text selected or clipboard is empty")
                Task { @MainActor in
                    self.showErrorAlert(message: NSLocalizedString("prompt.enhancer.error.no.text", comment: "No text selected"))
                }
                return
            }
            
            if selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("❌ Text is empty")
                 Task { @MainActor in
                    self.showErrorAlert(message: NSLocalizedString("prompt.enhancer.error.no.text", comment: "No text selected"))
                }
                return
            }
            
            print("📝 Original text: '\(selectedText.prefix(100))...'")
            
            // Step 6: Create meta-prompt and send to Gemini
            let metaPrompt = self.createMetaPrompt(userText: selectedText)
            
            Task { @MainActor in
                GeminiService.shared.sendPrompt(metaPrompt) { result in
                    switch result {
                    case .success(let enhancedPrompt):
                        Logger.info("Enhanced prompt: '\(enhancedPrompt.prefix(100))...'")
                        
                        // Play success sound when enhancement succeeds
                        SoundManager.shared.playSuccess()
                        
                        // Step 7: Show review window instead of pasting immediately
                        Task { @MainActor in
                            self.showReviewWindow(enhancedPrompt: enhancedPrompt, originalText: selectedText)
                        }
                    case .failure(let error):
                        Logger.network("Failed to enhance prompt: \(error.localizedDescription)", level: .error)
                        // Ensure alert is shown on Main Thread with user-friendly message
                        Task { @MainActor in
                            self.showErrorAlertWithDetails(error: error)
                        }
                    }
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
                    print("❌ User cancelled prompt review")
                },
                onRefine: { refineRequest in
                    // User wants to refine the prompt
                    print("🔄 Refining prompt: \(refineRequest)")
                    self.refinePrompt(currentPrompt: promptHolder.value, originalText: storedOriginalText, refineRequest: refineRequest) { refinedPrompt in
                        if let refined = refinedPrompt {
                            print("✅ Prompt refined successfully")
                            promptHolder.value = refined
                            // Update the window with new prompt
                            showWindowWithPrompt(refined)
                        } else {
                            print("❌ Failed to refine prompt")
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
            print("📋 Enhanced prompt written to clipboard")
            
            // Play success sound
            SoundManager.shared.playSuccess()
            
            // Delete selected text first (Async wait) + Paste
            NSApp.hide(nil)
            
            // Wait for app hide
            try? await Task.sleep(nanoseconds: 100 * 1_000_000)
            
            print("🗑️ Deleting selected text...")
            ClipboardHelper.simulateDelete()
            
            // Wait a bit before pasting
            try? await Task.sleep(nanoseconds: 200 * 1_000_000)
            
            print("📋 Simulating paste...")
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
            GeminiService.shared.sendPrompt(refinePrompt) { result in
                switch result {
                case .success(let refinedPrompt):
                    // Play success sound when refinement succeeds
                    SoundManager.shared.playSuccess()
                    completion(refinedPrompt)
                case .failure(let error):
                    Logger.network("Failed to refine prompt: \(error.localizedDescription)", level: .error)
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func hasAPIKey() -> Bool {
        // Check Keychain first, then settings
        if let keychainKey = try? KeychainHelper.retrieveGeminiKey(), !keychainKey.isEmpty {
            return true
        }
        
        return !settings.geminiKey.isEmpty
    }
    
    // MARK: - Helper Methods Removed
    // Code moved to ClipboardHelper.swift to prevent duplication

    
    // MARK: - Alerts
    
    private func showPermissionRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.accessibility.title", comment: "Accessibility alert title")
        alert.informativeText = NSLocalizedString("alert.accessibility.message", comment: "Accessibility alert message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("alert.button.open.settings", comment: "Open settings"))
        alert.addButton(withTitle: NSLocalizedString("alert.button.cancel", comment: "Cancel"))
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            PermissionManager.shared.openAccessibilitySettings()
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

