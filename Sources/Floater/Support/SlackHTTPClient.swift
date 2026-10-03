import FloaterCore
import Foundation

/// Talks to Slack's Web API with the user's own token, so the status it sets
/// and the messages it posts are the user's own, not a bot's.
final class SlackHTTPClient: SlackPosting, @unchecked Sendable {
    private let token: @Sendable () -> String?
    private let session: URLSession
    /// Cached from auth.test so posting can default to the user's own DM.
    private var selfID: String?

    init(token: @escaping @Sendable () -> String?, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func setStatus(text: String, emoji: String) async throws {
        let profile = ["status_text": text, "status_emoji": emoji, "status_expiration": 0] as [String: Any]
        guard let encoded = try? JSONSerialization.data(withJSONObject: ["profile": profile]) else {
            throw SlackError.api("could not encode the status")
        }
        _ = try await call("users.profile.set", json: encoded)
    }

    @discardableResult
    func post(text: String, channel: String?) async throws -> String {
        let destination: String
        if let channel, !channel.isEmpty {
            destination = channel
        } else {
            destination = try await currentUserID()
        }
        guard let encoded = try? JSONSerialization.data(
            withJSONObject: ["channel": destination, "text": text]
        ) else { throw SlackError.api("could not encode the message") }
        _ = try await call("chat.postMessage", json: encoded)
        return destination
    }

    private func currentUserID() async throws -> String {
        if let selfID { return selfID }
        let response = try await call("auth.test", json: nil)
        guard let id = response["user_id"] as? String else { throw SlackError.api("no user id") }
        selfID = id
        return id
    }

    @discardableResult
    private func call(_ method: String, json: Data?) async throws -> [String: Any] {
        guard let token = token(), !token.isEmpty else { throw SlackError.notConnected }
        var request = URLRequest(url: URL(string: "https://slack.com/api/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = json ?? Data("{}".utf8)
        request.timeoutInterval = 30

        let data: Data
        do {
            (data, _) = try await session.data(for: request)
        } catch {
            throw SlackError.transport(error.localizedDescription)
        }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SlackError.api("unreadable response")
        }
        // Slack answers 200 with ok:false rather than an HTTP error.
        guard body["ok"] as? Bool == true else {
            throw SlackError.api(body["error"] as? String ?? "unknown error")
        }
        return body
    }
}
