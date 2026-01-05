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

    /// Improved detection: Analyzes text to determine conversion direction
    /// Handles mixed Hebrew/English text intelligently
    /// Optimized for large text with early termination
    private static func shouldConvertToEnglish(_ text: String) -> Bool {
        // FIX: Optimize for large text - sample first 1000 characters if text is very long
        let sampleText: String
        if text.count > JoyaFixConstants.largeTextOptimizationThreshold {
            // For very long text, analyze first portion to make decision faster
            sampleText = String(text.prefix(1000))
        } else {
            sampleText = text
        }
        
        var hebrewCount = 0
        var englishCount = 0
        var numberCount = 0
        var punctuationCount = 0
        var spaceCount = 0
        
        // FIX: More comprehensive character analysis
        for char in sampleText {
            if isHebrewCharacter(char) {
                hebrewCount += 1
            } else if isEnglishCharacter(char) {
                englishCount += 1
            } else if char.isNumber {
                numberCount += 1
            } else if char.isPunctuation {
                punctuationCount += 1
            } else if char.isWhitespace {
                spaceCount += 1
            }
        }
        
        // FIX: Improved decision logic for mixed text
        // If we have Hebrew characters, convert to English
        if hebrewCount > 0 {
            // If Hebrew is dominant (more than 30% of letters), convert to English
            let totalLetters = hebrewCount + englishCount
            if totalLetters > 0 {
                let hebrewRatio = Double(hebrewCount) / Double(totalLetters)
                if hebrewRatio > 0.3 {
                    return true
                }
            } else {
                // Only Hebrew, no English letters
                return true
            }
        }
        
        // If we have English characters and no Hebrew, convert to Hebrew
        if englishCount > 0 && hebrewCount == 0 {
            return false
        }
        
        // FIX: Handle edge case - only numbers/punctuation/spaces
        // Default: assume English -> convert to Hebrew
        return false
    }

    // MARK: - Conversion Function

    /// Converts text from one keyboard layout to another
    /// If text contains Hebrew characters -> converts to English keyboard layout
    /// If text contains English characters -> converts to Hebrew keyboard layout
    /// FIX: Optimized for large text with pre-allocated capacity
    static func convert(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        let convertToEnglish = shouldConvertToEnglish(text)
        let mapping = convertToEnglish ? hebrewToEnglish : englishToHebrew

        // FIX: Pre-allocate capacity for better performance with large text
        var result = ""
        result.reserveCapacity(text.count) // Pre-allocate to avoid multiple reallocations
        
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
    /// FIX: Optimized with pre-allocated capacity
    static func convertToHebrew(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
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
    /// FIX: Optimized with pre-allocated capacity
    static func convertToEnglish(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
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
