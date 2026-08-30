import Foundation

/// Where the Anthropic API key lives. Abstracted so tests never touch the real
/// Keychain, and so nothing outside the app target needs the Security framework.
public protocol APIKeyStore: AnyObject {
    func read() -> String?
    func write(_ key: String) -> Bool
    func clear()
}

public final class InMemoryAPIKeyStore: APIKeyStore {
    private var value: String?
    public init(value: String? = nil) { self.value = value }
    public func read() -> String? { value }
    public func write(_ key: String) -> Bool { value = key; return true }
    public func clear() { value = nil }
}
