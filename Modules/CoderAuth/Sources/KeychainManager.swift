import Foundation
#if canImport(Security)
import Security
#endif

/// Protocol abstracting keychain operations for testability.
///
/// Implementations must be safe to call from multiple concurrent contexts.
public protocol KeychainStoring: Sendable {
    /// Stores a data value under the given key.
    /// - Parameters:
    ///   - data: The data to store.
    ///   - key: The keychain item key.
    /// - Throws: ``AuthError/keychainError(statusCode:)`` on failure.
    func store(data: Data, forKey key: String) throws

    /// Retrieves data for the given key.
    /// - Parameter key: The keychain item key.
    /// - Returns: The stored data, or `nil` if no item exists.
    /// - Throws: ``AuthError/keychainError(statusCode:)`` on failure.
    func retrieve(forKey key: String) throws -> Data?

    /// Deletes the item for the given key.
    ///
    /// It is not an error to delete a non-existent key.
    /// - Parameter key: The keychain item key.
    /// - Throws: ``AuthError/keychainError(statusCode:)`` on failure.
    func delete(forKey key: String) throws
}

/// The key used to store the session token in the keychain.
public enum KeychainKeys {
    /// The default keychain key for the Coder session token.
    public static let sessionToken = "com.coder.session.token"
}

/// A keychain store backed by the system Security framework.
///
/// Items are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// accessibility to prevent inclusion in device backups and restrict access
/// to this device only.
///
/// - Important: On non-Apple platforms, this type is unavailable. Use a
///   mock implementation for testing instead.
#if canImport(Security)
public final class SystemKeychainStore: KeychainStoring, Sendable {
    private let service: String

    /// Creates a new system keychain store.
    /// - Parameter service: The `kSecAttrService` value for all items.
    ///   Defaults to `"com.coder.ios"`.
    public init(service: String = "com.coder.ios") {
        self.service = service
    }

    public func store(data: Data, forKey key: String) throws {
        // Remove any existing item first
        try? delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthError.keychainError(statusCode: status)
        }
    }

    public func retrieve(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw AuthError.keychainError(statusCode: status)
        }
    }

    public func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.keychainError(statusCode: status)
        }
    }
}
#endif

/// An in-memory keychain store for testing on non-Apple platforms.
///
/// This implementation is thread-safe using a lock and is suitable for
/// use in unit tests on any platform.
public final class InMemoryKeychainStore: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    /// Creates a new empty in-memory keychain store.
    public init() {}

    public func store(data: Data, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = data
    }

    public func retrieve(forKey key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func delete(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }

    /// Returns the number of items currently stored. Useful for test assertions.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }

    /// Removes all stored items. Useful for test setup/teardown.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
