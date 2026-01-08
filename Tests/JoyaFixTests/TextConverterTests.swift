import XCTest
@testable import JoyaFix

final class TextConverterTests: XCTestCase {
    
    // MARK: - English to Hebrew Tests
    
    func testConvertToHebrew_BasicConversion() {
        // Test basic character conversion
        let english = "a"
        let hebrew = TextConverter.convertToHebrew(english)
        
        // 'a' on English keyboard maps to 'ש' on Hebrew keyboard
        XCTAssertEqual(hebrew, "ש", "English 'a' should convert to Hebrew 'ש'")
    }
    
    func testConvertToHebrew_EmptyString_ReturnsEmpty() {
        let result = TextConverter.convertToHebrew("")
        XCTAssertEqual(result, "", "Empty string should return empty")
    }
    
    func testConvertToHebrew_MultipleCharacters() {
        let english = "abc"
        let hebrew = TextConverter.convertToHebrew(english)
        
        // Should convert each character
        XCTAssertFalse(hebrew.isEmpty, "Should convert multiple characters")
        XCTAssertEqual(hebrew.count, english.count, "Should preserve character count")
    }
    
    // MARK: - Hebrew to English Tests
    
    func testConvertToEnglish_BasicConversion() {
        // Test basic character conversion
        let hebrew = "ש"
        let english = TextConverter.convertToEnglish(hebrew)
        
        // 'ש' on Hebrew keyboard maps to 'a' on English keyboard
        XCTAssertEqual(english, "a", "Hebrew 'ש' should convert to English 'a'")
    }
    
    func testConvertToEnglish_EmptyString_ReturnsEmpty() {
        let result = TextConverter.convertToEnglish("")
        XCTAssertEqual(result, "", "Empty string should return empty")
    }
    
    func testConvertToEnglish_MultipleCharacters() {
        let hebrew = "שלום"
        let english = TextConverter.convertToEnglish(hebrew)
        
        // Should convert each character
        XCTAssertFalse(english.isEmpty, "Should convert multiple characters")
        XCTAssertEqual(english.count, hebrew.count, "Should preserve character count")
    }
    
    // MARK: - Round Trip Tests
    
    func testRoundTrip_EnglishToHebrewToEnglish() {
        let original = "hello"
        let hebrew = TextConverter.convertToHebrew(original)
        let backToEnglish = TextConverter.convertToEnglish(hebrew)
        
        // Should get back to original (or close to it)
        XCTAssertEqual(backToEnglish, original, "Round trip should preserve text")
    }
    
    func testRoundTrip_HebrewToEnglishToHebrew() {
        let original = "שלום"
        let english = TextConverter.convertToEnglish(original)
        let backToHebrew = TextConverter.convertToHebrew(english)
        
        // Should get back to original (or close to it)
        XCTAssertEqual(backToHebrew, original, "Round trip should preserve text")
    }
    
    // MARK: - Special Characters Tests
    
    func testConvertToHebrew_SpecialCharacters_Preserved() {
        let text = "hello@world.com"
        let result = TextConverter.convertToHebrew(text)
        
        // Special characters should be preserved
        XCTAssertTrue(result.contains("@"), "Should preserve @")
    }
    
    func testConvertToEnglish_SpecialCharacters_Preserved() {
        let text = "שלום@עולם.com"
        let result = TextConverter.convertToEnglish(text)
        
        // Special characters should be preserved
        XCTAssertTrue(result.contains("@"), "Should preserve @")
    }
    
    // MARK: - Numbers Tests
    
    func testConvertToHebrew_Numbers_Preserved() {
        let text = "test123"
        let result = TextConverter.convertToHebrew(text)
        
        // Numbers should be preserved
        XCTAssertTrue(result.contains("1"), "Should preserve numbers")
        XCTAssertTrue(result.contains("2"), "Should preserve numbers")
        XCTAssertTrue(result.contains("3"), "Should preserve numbers")
    }
    
    func testConvertToEnglish_Numbers_Preserved() {
        let text = "בדיקה123"
        let result = TextConverter.convertToEnglish(text)
        
        // Numbers should be preserved
        XCTAssertTrue(result.contains("1"), "Should preserve numbers")
        XCTAssertTrue(result.contains("2"), "Should preserve numbers")
        XCTAssertTrue(result.contains("3"), "Should preserve numbers")
    }
}

