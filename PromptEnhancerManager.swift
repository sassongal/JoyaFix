import Foundation
import Cocoa
import Carbon

/// Manages AI-powered prompt enhancement
/// Converts user's raw input into professional, structured LLM prompts
@MainActor
class PromptEnhancerManager {
    static let shared = PromptEnhancerManager()
    
    private let settings = SettingsManager.shared
    
    private init() {}
    
    // MARK: - Meta-Prompt Template
    
    /// The system prompt used to enhance user input into professional prompts
    private func createMetaPrompt(userText: String) -> String {
        return """
You are an expert Prompt Engineer.
**Task:** Rewrite the user's raw, amateur input into a highly effective, structured LLM prompt (using frameworks like CO-STAR or CREATE).
**Input:** "\(userText)"
**Rules:**
1. **Detect Language:** If input is Hebrew, output MUST be in Hebrew (but you may use English headers like # Role, # Task). If English, output in English.
2. **Structure:**
   # Role: [Assign an expert persona]
   # Context: [Clarify the situation]
   # Task: [Define precise goal]
   # Constraints: [Add limitations/style]
   # Output Format: [Table/Code/List/etc]
3. **Refinement:** Fill in missing gaps logically. Make it professional and concise.
4. **Output:** Return ONLY the refined prompt. No "Here is the prompt" prefixes.
"""
    }
    
    // MARK: - Public API
    
    /// Enhances selected text by converting it to a professional prompt
    /// Flow: Copy → Enhance → Paste
    func enhanceSelectedText() {
        // Step 1: Check Accessibility permissions
        guard PermissionManager.shared.isAccessibilityTrusted() else {
            print("⚠️ Accessibility permission missing for prompt enhancement")
            showPermissionRequiredAlert()
            return
        }
        
        // Step 2: Check if API key is available
        guard hasAPIKey() else {
            print("⚠️ Gemini API key not found")
            showAPIKeyRequiredAlert()
            return
        }
        
        // Step 3: Simulate Cmd+C to copy selected text
        simulateCopy()
        
        // Step 4: Wait for clipboard to update
        DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.textConversionClipboardDelay) {
            // Step 5: Read from clipboard
            guard let selectedText = self.readFromClipboard(), !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                print("❌ No text selected or clipboard is empty")
                self.showErrorAlert(message: NSLocalizedString("prompt.enhancer.error.no.text", comment: "No text selected"))
                return
            }
            
            print("📝 Original text: '\(selectedText.prefix(100))...'")
            
            // Step 6: Create meta-prompt and send to Gemini
            let metaPrompt = self.createMetaPrompt(userText: selectedText)
            
            Task { @MainActor in
                GeminiService.shared.sendPrompt(metaPrompt) { enhancedPrompt in
                    guard let enhancedPrompt = enhancedPrompt, !enhancedPrompt.isEmpty else {
                        print("❌ Failed to enhance prompt")
                        self.showErrorAlert(message: NSLocalizedString("prompt.enhancer.error.api.failed", comment: "API request failed"))
                        return
                    }
                    
                    print("✅ Enhanced prompt: '\(enhancedPrompt.prefix(100))...'")
                    
                    // Step 7: Show review window instead of pasting immediately
                    Task { @MainActor in
                        self.showReviewWindow(enhancedPrompt: enhancedPrompt, originalText: selectedText)
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
        
        // Write enhanced prompt to clipboard
        writeToClipboard(prompt)
        print("📋 Enhanced prompt written to clipboard")
        
        // Play success sound
        SoundManager.shared.playSuccess()
        
        // Delete selected text, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.clipboardPasteDelay) {
            // Delete the selected text first
            print("🗑️ Deleting selected text...")
            self.simulateDelete()
            
            // Wait a bit before pasting
            DispatchQueue.main.asyncAfter(deadline: .now() + JoyaFixConstants.textConversionDeleteDelay) {
                print("📋 Simulating paste...")
                self.simulatePaste()
            }
        }
    }
    
    /// Refines the prompt based on user request
    private func refinePrompt(currentPrompt: String, originalText: String, refineRequest: String, completion: @escaping (String?) -> Void) {
        let refinePrompt = """
You are an expert Prompt Engineer.
**Task:** Refine the following enhanced prompt based on the user's refinement request.
**Original User Input:** "\(originalText)"
**Current Enhanced Prompt:**
\(currentPrompt)
**User's Refinement Request:** "\(refineRequest)"
**Rules:**
1. Apply the refinement request to the current enhanced prompt.
2. Maintain the structured format (Role, Context, Task, Constraints, Output Format).
3. Return ONLY the refined prompt. No explanations or prefixes.
"""
        
        Task { @MainActor in
            GeminiService.shared.sendPrompt(refinePrompt) { refinedPrompt in
                completion(refinedPrompt)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func hasAPIKey() -> Bool {
        // Check Keychain first, then settings
        if let keychainKey = KeychainHelper.retrieveGeminiKey(), !keychainKey.isEmpty {
            return true
        }
        
        return !settings.geminiKey.isEmpty
    }
    
    private func readFromClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string)
    }
    
    private func writeToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    // MARK: - Key Simulation
    
    private func simulateCopy() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }
    
    private func simulatePaste() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }
    
    private func simulateDelete() {
        simulateKeyPress(keyCode: CGKeyCode(kVK_ForwardDelete), flags: [])
    }
    
    private func simulateKeyPress(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else {
            print("Failed to create key down event")
            return
        }
        keyDownEvent.flags = flags
        
        guard let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            print("Failed to create key up event")
            return
        }
        keyUpEvent.flags = flags
        
        let location = CGEventTapLocation.cghidEventTap
        keyDownEvent.post(tap: location)
        usleep(10000) // 10ms
        keyUpEvent.post(tap: location)
    }
    
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
}

