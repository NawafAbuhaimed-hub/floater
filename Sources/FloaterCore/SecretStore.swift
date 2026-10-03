import Foundation

public enum SecretName: String, CaseIterable, Sendable {
    case anthropic
    case slack
}

/// Where Floater's credentials live. Abstracted so tests never touch real
/// storage, and so the app can choose where that is.
public protocol SecretStore: AnyObject {
    func secret(_ name: SecretName) -> String?
    @discardableResult
    func setSecret(_ value: String?, for name: SecretName) -> Bool
}

public extension SecretStore {
    func has(_ name: SecretName) -> Bool {
        !(secret(name) ?? "").isEmpty
    }
}

public final class InMemorySecretStore: SecretStore {
    private var values: [SecretName: String] = [:]

    public init(_ seed: [SecretName: String] = [:]) {
        values = seed
    }

    public func secret(_ name: SecretName) -> String? { values[name] }

    @discardableResult
    public func setSecret(_ value: String?, for name: SecretName) -> Bool {
        if let value, !value.isEmpty { values[name] = value } else { values[name] = nil }
        return true
    }
}
