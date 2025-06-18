import Foundation
import Security

/// Secure storage service for API keys and sensitive data using macOS Keychain
class SecureStorage {
    
    // MARK: - Error Types
    enum SecureStorageError: Error, LocalizedError {
        case keyNotFound
        case duplicateKey
        case invalidData
        case keychainError(OSStatus)
        case encodingError
        
        var errorDescription: String? {
            switch self {
            case .keyNotFound:
                return "API key not found in secure storage"
            case .duplicateKey:
                return "API key already exists in secure storage"
            case .invalidData:
                return "Invalid data format"
            case .keychainError(let status):
                return "Keychain error: \(SecureStorage.keychainErrorString(status))"
            case .encodingError:
                return "Failed to encode/decode data"
            }
        }
    }
    
    // MARK: - Service Identifier
    private static let service = "com.whonext.apikeys"
    
    // MARK: - Helper Functions
    private static func keychainErrorString(_ status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            return "Success"
        case errSecUnimplemented:
            return "Function not implemented"
        case errSecParam:
            return "Invalid parameter"
        case errSecAllocate:
            return "Memory allocation failure"
        case errSecNotAvailable:
            return "No keychain available"
        case errSecDuplicateItem:
            return "Duplicate item"
        case errSecItemNotFound:
            return "Item not found"
        case errSecInteractionNotAllowed:
            return "User interaction not allowed"
        case errSecDecode:
            return "Unable to decode data"
        case errSecAuthFailed:
            return "Authentication failed"
        default:
            return "Unknown error (\(status))"
        }
    }
    
    // MARK: - API Key Management
    
    /// Store an API key securely in the Keychain
    static func storeAPIKey(_ key: String, for provider: AIProvider) throws {
        guard !key.isEmpty else {
            throw SecureStorageError.invalidData
        }
        
        let account = provider.rawValue
        let data = key.data(using: .utf8)!
        
        // Check if key already exists
        if keyExists(for: provider) {
            // Update existing key
            try updateAPIKey(key, for: provider)
            return
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainError(status)
        }
        
        print("🔐 [SecureStorage] Stored API key for \(provider.displayName)")
    }
    
    /// Retrieve an API key from the Keychain
    static func retrieveAPIKey(for provider: AIProvider) throws -> String {
        let account = provider.rawValue
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw SecureStorageError.keyNotFound
            }
            throw SecureStorageError.keychainError(status)
        }
        
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw SecureStorageError.invalidData
        }
        
        return key
    }
    
    /// Update an existing API key in the Keychain
    static func updateAPIKey(_ key: String, for provider: AIProvider) throws {
        guard !key.isEmpty else {
            throw SecureStorageError.invalidData
        }
        
        let account = provider.rawValue
        let data = key.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainError(status)
        }
        
        print("🔐 [SecureStorage] Updated API key for \(provider.displayName)")
    }
    
    /// Delete an API key from the Keychain
    static func deleteAPIKey(for provider: AIProvider) throws {
        let account = provider.rawValue
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStorageError.keychainError(status)
        }
        
        print("🔐 [SecureStorage] Deleted API key for \(provider.displayName)")
    }
    
    /// Check if an API key exists for a provider
    static func keyExists(for provider: AIProvider) -> Bool {
        do {
            _ = try retrieveAPIKey(for: provider)
            return true
        } catch {
            return false
        }
    }
    
    /// Get all providers that have stored API keys
    static func getProvidersWithKeys() -> [AIProvider] {
        return AIProvider.allCases.filter { keyExists(for: $0) }
    }
    
    // MARK: - Migration from UserDefaults
    
    /// Migrate API keys from UserDefaults to secure Keychain storage
    static func migrateFromUserDefaults() {
        print("🔐 [SecureStorage] Starting migration from UserDefaults...")
        
        let userDefaults = UserDefaults.standard
        var migrated = 0
        
        // Migrate OpenAI key
        if let openaiKey = userDefaults.string(forKey: "openaiApiKey"), !openaiKey.isEmpty {
            do {
                try storeAPIKey(openaiKey, for: .openai)
                userDefaults.removeObject(forKey: "openaiApiKey")
                migrated += 1
                print("🔐 [SecureStorage] Migrated OpenAI API key")
            } catch {
                print("❌ [SecureStorage] Failed to migrate OpenAI key: \(error)")
            }
        }
        
        // Migrate Claude key
        if let claudeKey = userDefaults.string(forKey: "claudeApiKey"), !claudeKey.isEmpty {
            do {
                try storeAPIKey(claudeKey, for: .claude)
                userDefaults.removeObject(forKey: "claudeApiKey")
                migrated += 1
                print("🔐 [SecureStorage] Migrated Claude API key")
            } catch {
                print("❌ [SecureStorage] Failed to migrate Claude key: \(error)")
            }
        }
        
        // Migrate OpenRouter key
        if let openrouterKey = userDefaults.string(forKey: "openrouterApiKey"), !openrouterKey.isEmpty {
            do {
                try storeAPIKey(openrouterKey, for: .openrouter)
                userDefaults.removeObject(forKey: "openrouterApiKey")
                migrated += 1
                print("🔐 [SecureStorage] Migrated OpenRouter API key")
            } catch {
                print("❌ [SecureStorage] Failed to migrate OpenRouter key: \(error)")
            }
        }
        
        if migrated > 0 {
            print("🔐 [SecureStorage] Successfully migrated \(migrated) API keys to secure storage")
        } else {
            print("🔐 [SecureStorage] No API keys found to migrate")
        }
    }
    
    // MARK: - Debugging (Development Only)
    
    /// List all stored API keys (for debugging only)
    static func debugListKeys() -> [String: Bool] {
        var keys: [String: Bool] = [:]
        for provider in AIProvider.allCases {
            keys[provider.displayName] = keyExists(for: provider)
        }
        return keys
    }
}

// MARK: - Convenience Extensions
extension SecureStorage {
    
    /// Get API key with fallback to empty string (for compatibility)
    static func getAPIKey(for provider: AIProvider) -> String {
        do {
            return try retrieveAPIKey(for: provider)
        } catch {
            return ""
        }
    }
    
    /// Store API key with error logging
    static func setAPIKey(_ key: String, for provider: AIProvider) {
        do {
            try storeAPIKey(key, for: provider)
        } catch {
            print("❌ [SecureStorage] Failed to store \(provider.displayName) key: \(error)")
        }
    }
    
    /// Clear API key with error logging  
    static func clearAPIKey(for provider: AIProvider) {
        do {
            try deleteAPIKey(for: provider)
        } catch {
            print("❌ [SecureStorage] Failed to delete \(provider.displayName) key: \(error)")
        }
    }
}