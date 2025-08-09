import Foundation
import Security

// MARK: - Keychain Service

// Simple Keychain service class using static methods for saving and loading the API key.
// Based on common Swift Keychain wrapper patterns.

class KeychainService {

    // Define service and account keys used to identify the keychain item.
    // Using Bundle Identifier guarantees uniqueness.
    private static let service = Bundle.main.bundleIdentifier ?? "com.example.notebooksaver.apikey"
    private static let account = "cloudAPIKey"

    // MARK: - Save API Key

    static func saveAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else {
            print("Keychain Error: Could not convert key string to data.")
            return false
        }

        // Delete existing item before saving, to ensure we update correctly.
        _ = deleteAPIKey()

        // Attributes dictionary for the new keychain item.
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Set accessibility: Key can only be accessed when the device is unlocked.
            // This is a common security level for API keys.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        #if !targetEnvironment(macCatalyst)
        query[kSecAttrAccessGroup as String] = "$(AppIdentifierPrefix)com.daviddegner.NotebookSaver"
        #endif

        // Add the item to the keychain.
        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            print("Keychain: API Key saved successfully.")
            return true
        } else {
            print("Keychain Error: Failed to save API Key. Status code: \(status) - \(keychainErrorString(status))")
            return false
        }
    }

    // MARK: - Load API Key

    static func loadAPIKey() -> String? {
        // Query to find the keychain item.
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne // We only expect one item.
        ]
        #if !targetEnvironment(macCatalyst)
        query[kSecAttrAccessGroup as String] = "$(AppIdentifierPrefix)com.daviddegner.NotebookSaver"
        #endif

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            guard let retrievedData = dataTypeRef as? Data,
                  let key = String(data: retrievedData, encoding: .utf8) else {
                print("Keychain Error: Could not convert retrieved data to String.")
                return nil
            }
            print("Keychain: API Key loaded successfully.")
            return key
        } else if status == errSecItemNotFound {
             print("Keychain: API Key not found.")
             return nil // Normal case if key hasn't been saved yet.
         } else {
            print("Keychain Error: Failed to load API Key. Status code: \(status) - \(keychainErrorString(status))")
            return nil
        }
    }

    // MARK: - Delete API Key (Helper)

    static func deleteAPIKey() -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        #if !targetEnvironment(macCatalyst)
        query[kSecAttrAccessGroup as String] = "$(AppIdentifierPrefix)com.daviddegner.NotebookSaver"
        #endif

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
             if status == errSecSuccess {
                 print("Keychain: Existing Cloud API Key deleted.")
             }
            return true
        } else {
            print("Keychain Error: Failed to delete Cloud API Key. Status code: \(status) - \(keychainErrorString(status))")
            return false
        }
    }

    // MARK: - Error Helper
    private static func keychainErrorString(_ status: OSStatus) -> String {
         return SecCopyErrorMessageString(status, nil) as String? ?? "Unknown OSStatus code."
     }
}
