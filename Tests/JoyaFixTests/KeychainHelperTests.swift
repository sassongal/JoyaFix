import XCTest
@testable import JoyaFix
import Security

final class KeychainHelperTests: XCTestCase {
    
    let testKey = "test_keychain_key"
    let testValue = "test_value_123456789"
    
    override func setUp() {
        super.setUp()
        // Clean up any existing test data
        try? KeychainHelper.delete(key: testKey)
        try? KeychainHelper.deleteGeminiKey()
    }
    
    override func tearDown() {
        // Clean up test data
        try? KeychainHelper.delete(key: testKey)
        try? KeychainHelper.deleteGeminiKey()
        super.tearDown()
    }
    
    // MARK: - Store Tests
    
    func testStore_ValidKeyValue_Succeeds() {
        XCTAssertNoThrow(try KeychainHelper.store(key: testKey, value: testValue), "Should successfully store valid key-value pair")
    }
    
    func testStore_OverwritesExistingValue() {
        // Store initial value
        XCTAssertNoThrow(try KeychainHelper.store(key: testKey, value: "initial_value"))
        
        // Store new value
        let newValue = "new_value"
        XCTAssertNoThrow(try KeychainHelper.store(key: testKey, value: newValue), "Should successfully overwrite existing value")
        
        // Verify new value is stored
        do {
            let retrieved = try KeychainHelper.retrieve(key: testKey)
            XCTAssertEqual(retrieved, newValue, "Should retrieve the new value")
        } catch {
            XCTFail("Failed to retrieve value: \(error)")
        }
    }
    
    // MARK: - Retrieve Tests
    
    func testRetrieve_ExistingKey_ReturnsValue() {
        // Store a value first
        XCTAssertNoThrow(try KeychainHelper.store(key: testKey, value: testValue))
        
        // Retrieve it
        do {
            let retrieved = try KeychainHelper.retrieve(key: testKey)
            XCTAssertEqual(retrieved, testValue, "Should retrieve the stored value")
        } catch {
            XCTFail("Failed to retrieve value: \(error)")
        }
    }
    
    func testRetrieve_NonExistentKey_ThrowsItemNotFound() {
        XCTAssertThrowsError(try KeychainHelper.retrieve(key: "non_existent_key_12345")) { error in
            guard let keychainError = error as? KeychainHelper.KeychainError else {
                XCTFail("Expected KeychainError, but got \(error)")
                return
            }
            
            if case .itemNotFound = keychainError {
                // Success
            } else {
                XCTFail("Expected .itemNotFound error, but got \(keychainError)")
            }
        }
    }
    
    // MARK: - Delete Tests
    
    func testDelete_ExistingKey_Succeeds() {
        // Store a value first
        XCTAssertNoThrow(try KeychainHelper.store(key: testKey, value: testValue))
        
        // Delete it
        XCTAssertNoThrow(try KeychainHelper.delete(key: testKey), "Should successfully delete existing key")
        
        // Verify it's deleted
        XCTAssertThrowsError(try KeychainHelper.retrieve(key: testKey), "Should throw error when retrieving deleted key")
    }
    
    // MARK: - Gemini Key Tests
    
    func testStoreGeminiKey_StoresCorrectly() {
        let apiKey = "test_gemini_api_key_12345"
        XCTAssertNoThrow(try KeychainHelper.storeGeminiKey(apiKey), "Should successfully store Gemini API key")
        
        do {
            let retrieved = try KeychainHelper.retrieveGeminiKey()
            XCTAssertEqual(retrieved, apiKey, "Should retrieve the stored Gemini API key")
        } catch {
            XCTFail("Failed to retrieve Gemini Key: \(error)")
        }
    }
    
    func testRetrieveGeminiKey_WhenNotStored_ThrowsItemNotFound() {
        // Delete any existing key
        try? KeychainHelper.deleteGeminiKey()
        
        XCTAssertThrowsError(try KeychainHelper.retrieveGeminiKey(), "Should throw error when key is not stored")
    }
    
    func testDeleteGeminiKey_DeletesCorrectly() {
        // Store a key first
        XCTAssertNoThrow(try KeychainHelper.storeGeminiKey("test_key"))
        
        // Delete it
        XCTAssertNoThrow(try KeychainHelper.deleteGeminiKey(), "Should successfully delete Gemini API key")
        
        // Verify it's deleted
        XCTAssertThrowsError(try KeychainHelper.retrieveGeminiKey(), "Should throw error after deletion")
    }
    
    // MARK: - Security Tests
    
    func testStore_SpecialCharacters_HandlesCorrectly() {
        let specialValue = "test@#$%^&*()_+-=[]{}|;':\",./<>?`~"
        XCTAssertNoThrow(try KeychainHelper.store(key: testKey, value: specialValue), "Should handle special characters")
        
        do {
            let retrieved = try KeychainHelper.retrieve(key: testKey)
            XCTAssertEqual(retrieved, specialValue, "Should preserve special characters")
        } catch {
            XCTFail("Failed to retrieve special value: \(error)")
        }
    }
}

