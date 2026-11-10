import Foundation
import Security

public protocol SecretStore: AnyObject {
    func read() -> String?
    func write(_ value: String) throws
    func delete()
}

public final class InMemorySecretStore: SecretStore {
    private var value: String?
    public init(_ value: String? = nil) { self.value = value }
    public func read() -> String? { value }
    public func write(_ value: String) throws { self.value = value }
    public func delete() { value = nil }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public var errorDescription: String? { "Keychain error \(status)" }
}

public final class KeychainSecretStore: SecretStore {
    private let service: String, account: String
    public init(service: String = "dev.sofia.app", account: String = "session-cookie") {
        self.service = service; self.account = account
    }
    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    public func read() -> String? {
        var q = base; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    public func write(_ value: String) throws {
        delete()
        var q = base
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let s = SecItemAdd(q as CFDictionary, nil)
        if s != errSecSuccess { throw KeychainError(status: s) }
    }
    public func delete() { SecItemDelete(base as CFDictionary) }
}
