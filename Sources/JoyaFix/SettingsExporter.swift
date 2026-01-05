import Foundation

/// Handles export and import of JoyaFix settings and snippets
class SettingsExporter {
    
    // MARK: - Version Management
    
    /// Current export format version
    static let currentVersion = "1.0.0"
    
    /// Minimum supported import version
    static let minimumSupportedVersion = "1.0.0"
    
    /// Maximum supported import version (for future compatibility)
    static let maximumSupportedVersion = "1.0.0"
    
    /// Version compatibility check result
    enum VersionCompatibility {
        case compatible
        case tooOld(minimumVersion: String)
        case tooNew(maximumVersion: String)
        case unknown(version: String)
    }
    
    /// Checks if a version string is compatible with the current importer
    static func checkVersionCompatibility(_ version: String) -> VersionCompatibility {
        // Parse version string (format: "major.minor.patch")
        let versionComponents = version.split(separator: ".").compactMap { Int($0) }
        let minComponents = minimumSupportedVersion.split(separator: ".").compactMap { Int($0) }
        let maxComponents = maximumSupportedVersion.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentVersion.split(separator: ".").compactMap { Int($0) }
        
        guard versionComponents.count >= 2 else {
            return .unknown(version: version)
        }
        
        // Compare with minimum version
        if versionComponents.count >= minComponents.count {
            for i in 0..<min(minComponents.count, versionComponents.count) {
                if versionComponents[i] < minComponents[i] {
                    return .tooOld(minimumVersion: minimumSupportedVersion)
                } else if versionComponents[i] > minComponents[i] {
                    break
                }
            }
        }
        
        // Compare with maximum version (for future versions)
        if versionComponents.count >= maxComponents.count {
            for i in 0..<min(maxComponents.count, versionComponents.count) {
                if versionComponents[i] > maxComponents[i] {
                    return .tooNew(maximumVersion: maximumSupportedVersion)
                } else if versionComponents[i] < maxComponents[i] {
                    break
                }
            }
        }
        
        return .compatible
    }
    
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
            version: currentVersion,
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
            
            // First, try to decode just the version to check compatibility
            struct VersionOnly: Codable {
                let version: String
            }
            
            let versionDecoder = JSONDecoder()
            let versionInfo = try? versionDecoder.decode(VersionOnly.self, from: jsonData)
            
            // Check version compatibility before attempting full decode
            if let version = versionInfo?.version {
                let compatibility = checkVersionCompatibility(version)
                
                switch compatibility {
                case .compatible:
                    print("✓ Import file version (\(version)) is compatible")
                case .tooOld(let minimumVersion):
                    print("❌ Import file version (\(version)) is too old. Minimum supported: \(minimumVersion)")
                    return false
                case .tooNew(let maximumVersion):
                    print("❌ Import file version (\(version)) is too new. Maximum supported: \(maximumVersion)")
                    print("   Please update JoyaFix to import this file.")
                    return false
                case .unknown(let version):
                    print("⚠️ Unknown version format: \(version). Attempting import anyway...")
                }
            } else {
                print("⚠️ Could not determine file version. Attempting import with current format...")
            }
            
            // Decode full export data
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Use version-specific migration if needed
            let exportData = try decodeWithMigration(jsonData: jsonData, version: versionInfo?.version ?? currentVersion)
            
            // Import snippets atomically - validate all first, then replace in one operation
            // This prevents data loss if validation fails mid-way
            guard SnippetManager.shared.replaceAllSnippets(exportData.snippets) else {
                print("❌ Failed to import snippets: validation failed")
                return false
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
    
    // MARK: - Migration
    
    /// Decodes export data with version-specific migration support
    /// - Parameters:
    ///   - jsonData: The JSON data to decode
    ///   - version: The version string from the export file
    /// - Returns: Decoded ExportData
    /// - Throws: DecodingError if migration fails
    private static func decodeWithMigration(jsonData: Data, version: String) throws -> ExportData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // For now, all versions use the same format
        // In the future, add version-specific migration logic here
        // Example:
        // if version == "1.0.0" {
        //     return try decoder.decode(ExportData.self, from: jsonData)
        // } else if version == "1.1.0" {
        //     let v1_1_0 = try decoder.decode(ExportDataV1_1_0.self, from: jsonData)
        //     return migrateFromV1_1_0ToCurrent(v1_1_0)
        // }
        
        return try decoder.decode(ExportData.self, from: jsonData)
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
            
            // Check version compatibility first
            struct VersionOnly: Codable {
                let version: String
            }
            let versionDecoder = JSONDecoder()
            if let versionInfo = try? versionDecoder.decode(VersionOnly.self, from: jsonData) {
                let compatibility = checkVersionCompatibility(versionInfo.version)
                if case .compatible = compatibility {
                    // Version is compatible, try full decode
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let _ = try decoder.decode(ExportData.self, from: jsonData)
                    return true
                } else {
                    // Version is not compatible
                    return false
                }
            } else {
                // No version info - try to decode anyway (might be old format)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let _ = try decoder.decode(ExportData.self, from: jsonData)
                return true
            }
        } catch {
            return false
        }
    }
    
    /// Gets version information from an export file without full validation
    /// - Parameter url: The file URL to check
    /// - Returns: Version string if available, nil otherwise
    static func getExportFileVersion(_ url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        do {
            let jsonData = try Data(contentsOf: url)
            struct VersionOnly: Codable {
                let version: String
            }
            let decoder = JSONDecoder()
            let versionInfo = try? decoder.decode(VersionOnly.self, from: jsonData)
            return versionInfo?.version
        } catch {
            return nil
        }
    }
}

