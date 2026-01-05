import Foundation

/// Handles export and import of JoyaFix settings and snippets
class SettingsExporter {
    
    // MARK: - Export Data Structure
    
    struct ExportData: Codable {
        let version: String
        let exportDate: Date
        let snippets: [Snippet]
        let hotkeyKeyCode: UInt32
        let hotkeyModifiers: UInt32
        let ocrHotkeyKeyCode: UInt32
        let ocrHotkeyModifiers: UInt32
        let maxHistoryCount: Int
        let playSoundOnConvert: Bool
        let autoPasteAfterConvert: Bool
        let useCloudOCR: Bool
        // Note: Gemini API key is NOT exported for security reasons
    }
    
    // MARK: - Export
    
    /// Exports current settings and snippets to a JSON file
    /// - Parameter url: The file URL to save the export to
    /// - Returns: true if export was successful, false otherwise
    static func export(to url: URL) -> Bool {
        let settings = SettingsManager.shared
        let snippetManager = SnippetManager.shared
        
        let exportData = ExportData(
            version: "1.0.0",
            exportDate: Date(),
            snippets: snippetManager.snippets,
            hotkeyKeyCode: settings.hotkeyKeyCode,
            hotkeyModifiers: settings.hotkeyModifiers,
            ocrHotkeyKeyCode: settings.ocrHotkeyKeyCode,
            ocrHotkeyModifiers: settings.ocrHotkeyModifiers,
            maxHistoryCount: settings.maxHistoryCount,
            playSoundOnConvert: settings.playSoundOnConvert,
            autoPasteAfterConvert: settings.autoPasteAfterConvert,
            useCloudOCR: settings.useCloudOCR
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let jsonData = try encoder.encode(exportData)
            try jsonData.write(to: url, options: .atomic)
            print("✓ Settings exported successfully to: \(url.path)")
            return true
        } catch {
            print("❌ Failed to export settings: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Import
    
    /// Imports settings and snippets from a JSON file
    /// - Parameter url: The file URL to import from
    /// - Returns: true if import was successful, false otherwise
    static func importSettings(from url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Import file does not exist: \(url.path)")
            return false
        }
        
        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            let exportData = try decoder.decode(ExportData.self, from: jsonData)
            
            // Validate version (for future compatibility)
            if exportData.version != "1.0.0" {
                print("⚠️ Import file version (\(exportData.version)) may not be compatible")
                // Continue anyway - try to import what we can
            }
            
            // Import snippets - clear existing and add new ones
            // First remove all existing snippets
            let existingSnippets = SnippetManager.shared.snippets
            for snippet in existingSnippets {
                SnippetManager.shared.removeSnippet(snippet)
            }
            // Then add imported snippets
            for snippet in exportData.snippets {
                SnippetManager.shared.addSnippet(snippet)
            }
            
            // Import settings (but don't save yet - user needs to click "Save Changes")
            let settings = SettingsManager.shared
            settings.hotkeyKeyCode = exportData.hotkeyKeyCode
            settings.hotkeyModifiers = exportData.hotkeyModifiers
            settings.ocrHotkeyKeyCode = exportData.ocrHotkeyKeyCode
            settings.ocrHotkeyModifiers = exportData.ocrHotkeyModifiers
            settings.maxHistoryCount = exportData.maxHistoryCount
            settings.playSoundOnConvert = exportData.playSoundOnConvert
            settings.autoPasteAfterConvert = exportData.autoPasteAfterConvert
            settings.useCloudOCR = exportData.useCloudOCR
            
            // Settings are saved automatically when properties are set
            
            // Rebind hotkeys
            let result = HotkeyManager.shared.rebindHotkeys()
            if result.convertSuccess && result.ocrSuccess {
                print("✓ Settings imported and hotkeys rebound successfully")
            } else {
                print("⚠️ Settings imported but some hotkeys failed to bind")
            }
            
            print("✓ Settings imported successfully from: \(url.path)")
            print("   - \(exportData.snippets.count) snippets imported")
            print("   - Export date: \(exportData.exportDate)")
            
            return true
        } catch {
            print("❌ Failed to import settings: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Validation
    
    /// Validates if a file is a valid JoyaFix export file
    /// - Parameter url: The file URL to validate
    /// - Returns: true if valid, false otherwise
    static func isValidExportFile(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }
        
        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Try to decode - if it succeeds, it's valid
            let _ = try decoder.decode(ExportData.self, from: jsonData)
            return true
        } catch {
            return false
        }
    }
}

