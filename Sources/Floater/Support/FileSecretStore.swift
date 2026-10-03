import FloaterCore
import Foundation

/// Credentials in a file only this user account can read.
///
/// The Keychain is the safer home, but it identifies an app by its code
/// signature, and an ad-hoc signed app gets a new signature on every build — so
/// macOS asked for a password after each rebuild. This trades that away: the
/// file is 0600 inside a 0700 directory, so another user on the machine cannot
/// read it, but anything running as this user can.
final class FileSecretStore: SecretStore {
    private let url: URL
    private var cache: [String: String]?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Floater", isDirectory: true)
        url = base.appendingPathComponent("credentials.json")
        try? FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    func secret(_ name: SecretName) -> String? {
        let value = load()[name.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty ?? true) ? nil : value
    }

    @discardableResult
    func setSecret(_ value: String?, for name: SecretName) -> Bool {
        var values = load()
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            values[name.rawValue] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            values.removeValue(forKey: name.rawValue)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else {
            return false
        }
        do {
            try data.write(to: url, options: [.atomic])
            // Set after writing: an atomic write replaces the file, and with it
            // any permissions the previous one had.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            cache = values
            return true
        } catch {
            return false
        }
    }

    private func load() -> [String: String] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: url),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            cache = [:]
            return [:]
        }
        cache = values
        return values
    }
}
