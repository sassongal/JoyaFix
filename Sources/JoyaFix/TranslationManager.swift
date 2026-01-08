import Cocoa
import Foundation
import SwiftUI
import Carbon

@MainActor
class TranslationManager {
    static let shared = TranslationManager(geminiService: GeminiService.shared)
    
    private let geminiService: GeminiService
    
    // MARK: - Initialization
    
    init(geminiService: GeminiService) {
        self.geminiService = geminiService
    }
    
    // MARK: - Public API
    
    func translateSelectedText() {
        print("🌍 Translation Flow Initiated")
        
        // Hide app to restore focus to original window (critical for Menu Bar usage)
        NSApp.hide(nil)
        
        Task {
            // 1. Get Selected Text (Async)
            guard let originalText = await ClipboardHelper.getSelectedText() else {
                print("⚠️ Failed to get selected text")
                // Only show alert if we really failed to get text after trying
                // Don't show alert if text was empty string
                return
            }
            
            if originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("⚠️ Text is empty")
                return
            }
            
            print("📝 Original text for translation: \(originalText.prefix(50))...")
            
            // 2. Prepare Prompt
            let prompt = createSmartTranslationPrompt(userText: originalText)
            
            do {
                // Show sound indicator
                if SettingsManager.shared.playSoundOnConvert {
                    NSSound(named: "Pop")?.play()
                }
                
                // 3. Send to Gemini (using async wrapper)
                let translatedText = try await sendPromptToGemini(prompt)
                
                print("✅ Translation received: \(translatedText.prefix(50))...")
                
                // 4. Paste back
                if !translatedText.isEmpty {
                    await ClipboardHelper.pasteText(translatedText)
                    
                    if SettingsManager.shared.playSoundOnConvert {
                        SoundManager.shared.playSuccess()
                    }
                }
                
            } catch {
                print("❌ Translation failed: \(error.localizedDescription)")
                showErrorAlert(message: "Translation failed: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Gemini Integration
    
    private func sendPromptToGemini(_ prompt: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            geminiService.sendPrompt(prompt) { result in
                switch result {
                case .success(let text):
                    continuation.resume(returning: text)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Prompt Engineering
    
    private func createSmartTranslationPrompt(userText: String) -> String {
        return """
You are a world-class Translator and Linguist with native-level proficiency in both Hebrew and English.
Your goal is to provide a perfect, context-aware translation that captures the nuance, tone, and intent of the original text.

**INPUT TEXT:**
"\(userText)"

**INSTRUCTIONS:**
1. **Detect Language:** Identify if the Input Text is primarily Hebrew or English.
2. **Translate:**
   - If Hebrew -> Translate to idiomatic, high-quality American English.
   - If English -> Translate to idiomatic, high-quality Hebrew.
3. **Style & Tone:** Maintain the original style and tone (e.g., if casual, be casual; if formal, be formal). Be "Visionary" and professional.
4. **Accuracy:** Avoid literal "Google Translate" errors. Use culturally appropriate idioms.
5. **Formatting:** Preserve the original formatting (line breaks, lists, etc.) exactly.

**OUTPUT:**
Return ONLY the translated text. Do not add explanations, notes, or quotes.
"""
    }
    
    // MARK: - Helpers
    
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Translation Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
