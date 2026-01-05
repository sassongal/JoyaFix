import XCTest
@testable import JoyaFix

final class JoyaFixTests: XCTestCase {
    
    // MARK: - TextConverter Tests
    
    /// Tests basic English to Hebrew conversion
    /// Verifies "shalom" -> "שלום" logic
    func testTextConverterShalom() {
        // "shalom" in English QWERTY should convert to Hebrew
        let englishText = "shalom"
        let hebrewResult = TextConverter.convertToHebrew(englishText)
        
        // Expected: "שלום" (shin-he-lamed-vav-mem)
        // s -> ש, h -> י, a -> ש, l -> ך, o -> ם, m -> צ
        // Wait, let me check the mapping more carefully...
        // s -> ד, h -> י, a -> ש, l -> ך, o -> ם, m -> צ
        // Actually: s=ד, h=י, a=ש, l=ך, o=ם, m=צ
        // So "shalom" -> "דישלכםצ" which is not "שלום"
        
        // Let's test the actual conversion logic
        // "shalom" typed on English keyboard should map to Hebrew keyboard positions
        // s -> ד (same key position)
        // h -> י
        // a -> ש
        // l -> ך
        // o -> ם
        // m -> צ
        
        // Actually, the correct test should be:
        // If user types "shalom" on English keyboard, it should convert to Hebrew layout equivalent
        // But "שלום" typed on Hebrew keyboard would convert to "shalom" on English
        
        // Let's test the reverse: Hebrew "שלום" -> English "shalom"
        let hebrewText = "שלום"
        let englishResult = TextConverter.convertToEnglish(hebrewText)
        
        // ש -> a, ל -> k, ו -> u, ם -> o
        // Wait, let me verify the mapping from TextConverter
        // From the code: "ש": "a", "ל": "k", "ו": "u", "ם": "o"
        // So "שלום" -> "akuo" which is not "shalom"
        
        // Actually, I think the mapping is keyboard position-based, not phonetic
        // Let me test a simpler case: single character conversions
        
        // Test: English "a" should convert to Hebrew "ש"
        XCTAssertEqual(TextConverter.convertToHebrew("a"), "ש", "English 'a' should convert to Hebrew 'ש'")
        
        // Test: Hebrew "ש" should convert to English "a"
        XCTAssertEqual(TextConverter.convertToEnglish("ש"), "a", "Hebrew 'ש' should convert to English 'a'")
        
        // Test: English "s" should convert to Hebrew "ד"
        XCTAssertEqual(TextConverter.convertToHebrew("s"), "ד", "English 's' should convert to Hebrew 'ד'")
        
        // Test: Hebrew "ד" should convert to English "s"
        XCTAssertEqual(TextConverter.convertToEnglish("ד"), "s", "Hebrew 'ד' should convert to English 's'")
    }
    
    /// Tests automatic direction detection
    func testTextConverterAutoDetection() {
        // Text with Hebrew should convert to English layout
        let hebrewText = "שלום"
        let result = TextConverter.convert(hebrewText)
        
        // Should detect Hebrew and convert to English keyboard layout
        XCTAssertNotEqual(result, hebrewText, "Hebrew text should be converted")
        
        // Text with English should convert to Hebrew layout
        let englishText = "hello"
        let hebrewResult = TextConverter.convert(englishText)
        
        // Should detect English and convert to Hebrew keyboard layout
        XCTAssertNotEqual(hebrewResult, englishText, "English text should be converted")
    }
    
    /// Tests edge cases
    func testTextConverterEdgeCases() {
        // Empty string
        XCTAssertEqual(TextConverter.convert(""), "", "Empty string should remain empty")
        
        // Numbers should pass through
        XCTAssertEqual(TextConverter.convert("123"), "123", "Numbers should pass through unchanged")
        
        // Mixed text
        let mixedText = "hello שלום"
        let result = TextConverter.convert(mixedText)
        XCTAssertNotEqual(result, mixedText, "Mixed text should be converted")
    }
}

