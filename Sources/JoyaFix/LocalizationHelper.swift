import Foundation

/// Helper for localization that works both in production and development (swift run)
enum LocalizationHelper {

    /// Get localized string with fallback to source files for development mode
    static func localized(_ key: String, comment: String = "") -> String {
        // Always try to load from source directory first (development mode with swift run)
        // This ensures localization works in both production and development
        let currentLanguage = Locale.preferredLanguages.first?.prefix(2) ?? "en"
        let language = currentLanguage == "he" ? "he" : "en"

        // Build path to source localization file
        let sourcePath = #file.replacingOccurrences(
            of: "/LocalizationHelper.swift",
            with: "/Resources/\(language).lproj/Localizable.strings"
        )

        // Try loading from source file first (development mode)
        if let strings = loadStringsFile(at: sourcePath) {
            if let value = strings[key], !value.isEmpty {
                return value
            }
        }

        // Try English as fallback if current language is Hebrew and key not found
        if language == "he" {
            let englishPath = #file.replacingOccurrences(
                of: "/LocalizationHelper.swift",
                with: "/Resources/en.lproj/Localizable.strings"
            )
            if let englishStrings = loadStringsFile(at: englishPath),
               let englishValue = englishStrings[key], !englishValue.isEmpty {
                Logger.warning("⚠️ Localization key '\(key)' not found in Hebrew, using English fallback")
                return englishValue
            }
        }

        // Try standard localization as fallback (works in production if source files not found)
        let localized = Bundle.main.localizedString(forKey: key, value: nil, table: nil)

        // If it returns the key itself, localization failed
        if localized != key && !localized.isEmpty {
            return localized
        }

        // Last resort: try to provide a human-readable version of the key
        // Convert "menu.convert.selection" to "Convert Selection" for better UX
        if key.contains(".") {
            let readableKey = key.components(separatedBy: ".").last?.replacingOccurrences(of: "_", with: " ").capitalized ?? key
            Logger.warning("⚠️ Localization key '\(key)' not found, using readable fallback: '\(readableKey)'")
            return readableKey
        }

        // Absolute last resort: return the key itself
        Logger.warning("⚠️ Localization key '\(key)' not found, returning key as-is")
        return key
    }

    /// Load .strings file and parse it
    private static func loadStringsFile(at path: String) -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        var dict: [String: String] = [:]

        // Parse .strings file format: "key" = "value";
        let pattern = #"\"([^\"]+)\"\s*=\s*\"([^\"]+)\";"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))

        for match in matches {
            if match.numberOfRanges == 3 {
                let key = nsContent.substring(with: match.range(at: 1))
                let value = nsContent.substring(with: match.range(at: 2))
                dict[key] = value
            }
        }

        return dict
    }
}

/// Convenience function to replace NSLocalizedString
func L(_ key: String, comment: String = "") -> String {
    return LocalizationHelper.localized(key, comment: comment)
}

/// Global override for NSLocalizedString to work in development mode
func NSLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = Bundle.main, value: String = "", comment: String) -> String {
    return LocalizationHelper.localized(key, comment: comment)
}
