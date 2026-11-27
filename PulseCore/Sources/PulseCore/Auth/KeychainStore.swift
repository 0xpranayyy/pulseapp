import Foundation
#if canImport(Security)
import Security
#endif

/// Secure storage for wallet keys and CLOB credentials.
///
/// Everything secret the app holds goes here and nowhere else — never
/// `UserDefaults`, never a plist, never a log line. Items are stored with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` so they are unavailable
/// while the device is locked and are excluded from backups and device
/// transfers: a leaked iCloud backup must not contain a trading key.
public protocol SecretStore: Sendable {
    func set(_ value: Data, for key: String) throws
    func get(_ key: String) throws -> Data?
    func remove(_ key: String) throws
}

public enum SecretStoreError: Error, Sendable, Equatable {
    case unexpectedStatus(Int32)
    case encodingFailed
    case unavailable
}

public extension SecretStore {
    func setString(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else { throw SecretStoreError.encodingFailed }
        try set(data, for: key)
    }

    func getString(_ key: String) throws -> String? {
        guard let data = try get(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setCodable<T: Encodable>(_ value: T, for key: String) throws {
        try set(try JSONEncoder().encode(value), for: key)
    }

    func getCodable<T: Decodable>(_ type: T.Type, for key: String) throws -> T? {
        guard let data = try get(key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Well-known keys. Kept in one place so nothing is stored under an ad-hoc name.
public enum SecretKey {
    public static let walletPrivateKey = "pulse.wallet.privateKey"
    public static let clobCredentials = "pulse.clob.credentials"
    public static let proxyWalletAddress = "pulse.wallet.proxyAddress"
}

#if canImport(Security)
/// Keychain-backed implementation used on device.
public struct KeychainStore: SecretStore {
    private let service: String

    public init(service: String = "com.pulse.polymarket") {
        self.service = service
    }

    private func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    public func set(_ value: Data, for key: String) throws {
        var attributes = query(for: key)
        SecItemDelete(attributes as CFDictionary)

        attributes[kSecValueData as String] = value
        attributes[kSecAttrAccessible as String] =
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    public func get(_ key: String) throws -> Data? {
        var attributes = query(for: key)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        switch status {
        case errSecSuccess: return item as? Data
        case errSecItemNotFound: return nil
        default: throw SecretStoreError.unexpectedStatus(status)
        }
    }

    public func remove(_ key: String) throws {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }
}
#endif

/// In-memory store used by tests and previews. Never used on device: it is
/// explicitly not persistent, so a misconfiguration fails safe by losing the
/// secret rather than writing it somewhere insecure.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    public func set(_ value: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    public func get(_ key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func remove(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}
