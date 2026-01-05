import Foundation
import Security

/// Helper class for secure storage using macOS Keychain
class KeychainHelper {
    private static let service = JoyaFixConstants.Keychain.service
    private static let geminiKeyAccount = JoyaFixConstants.Keychain.geminiKeyAccount
    
    /// Stores a string value securely in the Keychain
    static func store(key: String, value: String) -> Bool {
        // Delete existing item if it exists
        _ = delete(key: key)
        
        // Convert string to data
        guard let data = value.data(using: .utf8) else {
            print("❌ Failed to convert string to data")
            return false
        }
        
        // Create query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Add item to Keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✓ Successfully stored key in Keychain")
            return true
        } else {
            print("❌ Failed to store key in Keychain: \(status)")
            return false
        }
    }
    
    /// Retrieves a string value from the Keychain
    static func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            if let data = result as? Data,
               let string = String(data: data, encoding: .utf8) {
                return string
            }
        } else if status == errSecItemNotFound {
            // Item doesn't exist, return nil
            return nil
        } else {
            print("❌ Failed to retrieve key from Keychain: \(status)")
        }
        
        return nil
    }
    
    /// Deletes a key from the Keychain
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        } else {
            print("⚠️ Failed to delete key from Keychain: \(status)")
            return false
        }
    }
    
    /// Stores the Gemini API key
    static func storeGeminiKey(_ key: String) -> Bool {
        return store(key: geminiKeyAccount, value: key)
    }
    
    /// Retrieves the Gemini API key
    static func retrieveGeminiKey() -> String? {
        return retrieve(key: geminiKeyAccount)
    }
    
    /// Deletes the Gemini API key
    static func deleteGeminiKey() -> Bool {
        return delete(key: geminiKeyAccount)
    }
}

