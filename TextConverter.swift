import Foundation

struct TextConverter {

    // MARK: - English to Hebrew Mapping

    /// Maps QWERTY English keys to Hebrew keyboard layout
    private static let englishToHebrew: [Character: Character] = [
        // Lowercase letters
        "q": "/", "w": "'", "e": "ק", "r": "ר", "t": "א", "y": "ט", "u": "ו", "i": "ן", "o": "ם", "p": "פ",
        "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע", "h": "י", "j": "ח", "k": "ל", "l": "ך",
        "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ", "n": "מ", "m": "צ",

        // Uppercase letters (with Shift)
        "Q": "Q", "W": "W", "E": "E", "R": "R", "T": "T", "Y": "Y", "U": "U", "I": "I", "O": "O", "P": "P",
        "A": "A", "S": "S", "D": "D", "F": "F", "G": "G", "H": "H", "J": "J", "K": "K", "L": "L",
        "Z": "Z", "X": "X", "C": "C", "V": "V", "B": "B", "N": "N", "M": "M",

        // Numbers
        "1": "1", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6", "7": "7", "8": "8", "9": "9", "0": "0",

        // Punctuation and special characters (standard keyboard)
        ",": "ת", ".": "ץ", ";": "ף", "'": ",", "[": "]", "]": "[", "\\": "\\",
        "/": ".", "-": "-", "=": "=",

        // Shift + number keys
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

        // Final forms (sofit) that don't have regular equivalents
        "ף": ";", "ץ": ".",

        // Punctuation
        "ת": ",", ",": "'",

        // Pass through characters that are the same
        "1": "1", "2": "2", "3": "3", "4": "4", "5": "5", "6": "6", "7": "7", "8": "8", "9": "9", "0": "0",
        ".": "/", "-": "-", "=": "=", "[": "]", "]": "[", "\\": "\\",

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
    private static func shouldConvertToEnglish(_ text: String) -> Bool {
        for char in text {
            if isHebrewCharacter(char) {
                return true  // Has Hebrew -> convert to English
            }
            if isEnglishCharacter(char) {
                return false  // Has English -> convert to Hebrew
            }
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
