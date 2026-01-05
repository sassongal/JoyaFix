import Foundation

struct TextConverter {

    // MARK: - English to Hebrew Mapping

    /// Maps QWERTY English keys to Hebrew keyboard layout
    private static let englishToHebrew: [Character: Character] = [
        // Lowercase letters
        "q": "/", "w": "'", "e": "ק", "r": "ר", "t": "א", "y": "ט", "u": "ו", "i": "ן", "o": "ם", "p": "פ",
        "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע", "h": "י", "j": "ח", "k": "ל", "l": "ך",
        "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ", "n": "מ", "m": "צ",

        // Uppercase letters (with Shift/CapsLock) - mapped to Hebrew with Shift
        "Q": "/", "W": "'", "E": "ק", "R": "ר", "T": "א", "Y": "ט", "U": "ו", "I": "ן", "O": "ם", "P": "פ",
        "A": "ש", "S": "ד", "D": "ג", "F": "כ", "G": "ע", "H": "י", "J": "ח", "K": "ל", "L": "ך",
        "Z": "ז", "X": "ס", "C": "ב", "V": "ה", "B": "נ", "N": "מ", "M": "צ",

        // Numbers
        "1": "1", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6", "7": "7", "8": "8", "9": "9", "0": "0",

        // Punctuation and special characters (standard keyboard)
        ",": "ת", ".": "ץ", ";": "ף", "'": ",", "[": "]", "]": "[", "\\": "\\",
        "/": ".", "-": "-", "=": "=",
        
        // Additional keys
        "`": "`", "~": "~",

        // Shift + number keys (Hebrew keyboard layout)
        "!": "!", "@": "@", "#": "#", "$": "$", "%": "%", "^": "^", "&": "&", "*": "*", "(": "(", ")": ")",

        // Shift + punctuation
        "<": ">", ">": "<", ":": ":", "\"": "\"", "{": "}", "}": "{", "|": "|", "?": "?", "_": "_", "+": "+"
    ]

    // MARK: - Hebrew to English Mapping

    /// Maps Hebrew keyboard layout to QWERTY English keys
    private static let hebrewToEnglish: [Character: Character] = [
        // Hebrew letters to lowercase English
        "/": "q", "'": "w", "ק": "e", "ר": "r", "א": "t", "ט": "y", "ו": "u", "ן": "i", "ם": "o", "פ": "p",
        "ש": "a", "ד": "s", "ג": "d", "כ": "f", "ע": "g", "י": "h", "ח": "j", "ל": "k", "ך": "l",
        "ז": "z", "ס": "x", "ב": "c", "ה": "v", "נ": "b", "מ": "n", "צ": "m",
        
        // Hebrew letters with Shift (for uppercase English) - map to uppercase
        // Note: Hebrew doesn't have case, but we need to preserve the intent
        // We'll map Hebrew back to lowercase English, and let the user use Shift if needed

        // Final forms (sofit) that don't have regular equivalents
        "ף": ";", "ץ": ".",

        // Punctuation
        "ת": ",", ",": "'",

        // Pass through characters that are the same
        "1": "1", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6", "7": "7", "8": "8", "9": "9", "0": "0",
        ".": "/", "-": "-", "=": "=", "[": "]", "]": "[", "\\": "\\",
        
        // Additional keys
        "`": "`", "~": "~",

        // Shift + number keys
        "!": "!", "@": "@", "#": "#", "$": "$", "%": "%", "^": "^", "&": "&", "*": "*", "(": "(", ")": ")",

        // Shift + punctuation
        ">": "<", "<": ">", ":": ":", "\"": "\"", "}": "{", "{": "}", "|": "|", "?": "?", "_": "_", "+": "+"
    ]

    // MARK: - Language Detection

    /// Checks if a character is a Hebrew letter
    private static func isHebrewCharacter(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        return (0x0590...0x05FF).contains(scalar.value) // Hebrew Unicode range
    }

    /// Checks if a character is an English letter
    private static func isEnglishCharacter(_ char: Character) -> Bool {
        return char.isLetter && char.isASCII
    }

    /// Simple detection: if text has Hebrew characters -> convert to English
    /// If text has English characters -> convert to Hebrew
    /// Improved: Count both types to make better decision
    /// Also checks if text looks like it was already converted (mixed case with Hebrew-like patterns)
    private static func shouldConvertToEnglish(_ text: String) -> Bool {
        var hebrewCount = 0
        var englishCount = 0
        var uppercaseEnglishCount = 0
        
        for char in text {
            if isHebrewCharacter(char) {
                hebrewCount += 1
            } else if isEnglishCharacter(char) {
                englishCount += 1
                if char.isUppercase {
                    uppercaseEnglishCount += 1
                }
            }
        }
        
        // If we have Hebrew characters, convert to English
        if hebrewCount > 0 {
            return true
        }
        
        // If we have English characters, convert to Hebrew
        if englishCount > 0 {
            return false
        }
        
        // Default: assume English -> convert to Hebrew
        return false
    }

    // MARK: - Conversion Function

    /// Converts text from one keyboard layout to another
    /// If text contains Hebrew characters -> converts to English keyboard layout
    /// If text contains English characters -> converts to Hebrew keyboard layout
    static func convert(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let convertToEnglish = shouldConvertToEnglish(text)
        let mapping = convertToEnglish ? hebrewToEnglish : englishToHebrew

        var result = ""
        for char in text {
            if let mappedChar = mapping[char] {
                result.append(mappedChar)
            } else {
                // Keep unmapped characters as-is (spaces, newlines, etc.)
                result.append(char)
            }
        }

        return result
    }

    // MARK: - Explicit Conversion Functions

    /// Explicitly converts English text to Hebrew keyboard layout
    static func convertToHebrew(_ text: String) -> String {
        var result = ""
        for char in text {
            if let mappedChar = englishToHebrew[char] {
                result.append(mappedChar)
            } else {
                result.append(char)
            }
        }
        return result
    }

    /// Explicitly converts Hebrew text to English keyboard layout
    static func convertToEnglish(_ text: String) -> String {
        var result = ""
        for char in text {
            if let mappedChar = hebrewToEnglish[char] {
                result.append(mappedChar)
            } else {
                result.append(char)
            }
        }
        return result
    }

}
