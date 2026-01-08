import Foundation
import Security

/// Helper class for secure storage using macOS Keychain
class KeychainHelper {
    private static let service = JoyaFixConstants.Keychain.service
    private static let geminiKeyAccount = JoyaFixConstants.Keychain.geminiKeyAccount
    
    enum KeychainError: Error {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case invalidData
        case accessDenied
        
        var localizedDescription: String {
            switch self {
            case .itemNotFound: return "Item not found in Keychain"
            case .duplicateItem: return "Item already exists in Keychain"
            case .invalidData: return "Data is invalid or corrupted"
            case .accessDenied: return "Access to Keychain denied"
            case .unexpectedStatus(let status):
                if let msg = SecCopyErrorMessageString(status, nil) as String? {
                    return "Keychain Error: \(msg) (\(status))"
                }
                return "Unexpected Keychain Error: \(status)"
            }
        }
    }
    
    /// Stores a string value securely in the Keychain
    /// - Throws: KeychainError
    static func store(key: String, value: String) throws {
        // Delete existing item first to ensure clean state
        try? delete(key: key)
        
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem { throw KeychainError.duplicateItem }
            if status == errSecItemNotFound { throw KeychainError.itemNotFound }
            if status == errSecAuthFailed { throw KeychainError.accessDenied }
            throw KeychainError.unexpectedStatus(status)
        }
        
        print("✓ Successfully stored key in Keychain: \(key)")
    }
    
    /// Retrieves a string value from the Keychain
    /// - Throws: KeychainError
    /// - Returns: The stored string
    static func retrieve(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound { throw KeychainError.itemNotFound }
            throw KeychainError.unexpectedStatus(status)
        }
        
        guard let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return string
    }
    
    /// Deletes a key from the Keychain
    /// - Throws: KeychainError
    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    // MARK: - Gemini Key Specifics
    // Wrappers now handle the try-catch internally to maintain backward compatibility or exposing errors if needed.
    // Ideally, callers should handle errors. I will keep the signature somewhat compatible but throwing is better.
    // However, since we refactored GeminiService to use try?, we need to align.
    
    /// Stores the Gemini API key
    static func storeGeminiKey(_ key: String) throws {
        try store(key: geminiKeyAccount, value: key)
    }
    
    /// Retrieves the Gemini API key
    static func retrieveGeminiKey() throws -> String {
        return try retrieve(key: geminiKeyAccount)
    }
    
    /// Deletes the Gemini API key
    static func deleteGeminiKey() throws {
        try delete(key: geminiKeyAccount)
    }
}

