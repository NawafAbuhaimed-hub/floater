import Foundation

// Wire types for POST https://api.anthropic.com/v1/messages.
// Swift has no official Anthropic SDK, so this is raw HTTP against the
// documented shapes.

public struct ToolDefinition: Encodable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let input_schema: JSONValue
    /// Guarantees tool inputs validate against the schema exactly.
    public let strict: Bool

    public init(name: String, description: String, inputSchema: JSONValue, strict: Bool = true) {
        self.name = name
        self.description = description
        self.input_schema = inputSchema
        self.strict = strict
    }
}

public enum ContentBlock: Codable, Equatable, Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String, isError: Bool)
    /// Thinking and any future block types are kept out of the way rather than
    /// crashing the decode.
    case other(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, tool_use_id, content, is_error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "tool_use":
            self = .toolUse(
                id: try container.decode(String.self, forKey: .id),
                name: try container.decode(String.self, forKey: .name),
                input: try container.decodeIfPresent(JSONValue.self, forKey: .input) ?? .object([:])
            )
        case "tool_result":
            self = .toolResult(
                toolUseID: try container.decode(String.self, forKey: .tool_use_id),
                content: (try? container.decode(String.self, forKey: .content)) ?? "",
                isError: try container.decodeIfPresent(Bool.self, forKey: .is_error) ?? false
            )
        default:
            self = .other(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseID, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseID, forKey: .tool_use_id)
            try container.encode(content, forKey: .content)
            if isError { try container.encode(true, forKey: .is_error) }
        case .other(let type):
            try container.encode(type, forKey: .type)
        }
    }

    public var textValue: String? {
        if case .text(let text) = self { return text }
        return nil
    }
}

public struct APIMessage: Codable, Equatable, Sendable {
    public let role: String
    public let content: [ContentBlock]

    public init(role: String, content: [ContentBlock]) {
        self.role = role
        self.content = content
    }

    public static func user(_ text: String) -> APIMessage {
        APIMessage(role: "user", content: [.text(text)])
    }

    public static func assistant(_ text: String) -> APIMessage {
        APIMessage(role: "assistant", content: [.text(text)])
    }
}

public struct MessagesRequest: Encodable, Sendable {
    public let model: String
    public let max_tokens: Int
    public let system: String?
    public let messages: [APIMessage]
    public let tools: [ToolDefinition]?

    public init(
        model: String,
        maxTokens: Int,
        system: String?,
        messages: [APIMessage],
        tools: [ToolDefinition]?
    ) {
        self.model = model
        self.max_tokens = maxTokens
        self.system = system
        self.messages = messages
        self.tools = tools
    }
}

public struct MessagesResponse: Decodable, Equatable, Sendable {
    public let id: String
    public let model: String
    public let stop_reason: String?
    public let content: [ContentBlock]

    public init(id: String, model: String, stop_reason: String?, content: [ContentBlock]) {
        self.id = id
        self.model = model
        self.stop_reason = stop_reason
        self.content = content
    }

    public var text: String {
        content.compactMap(\.textValue).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var toolUses: [(id: String, name: String, input: JSONValue)] {
        content.compactMap { block in
            if case .toolUse(let id, let name, let input) = block { return (id, name, input) }
            return nil
        }
    }
}

public enum ClaudeError: Error, Equatable {
    case missingAPIKey
    case unauthorized
    case rateLimited
    case server(status: Int, message: String)
    case transport(String)
    case decoding(String)
    case refused

    public var message: String {
        switch self {
        case .missingAPIKey: return "Add an Anthropic API key to use chat."
        case .unauthorized: return "That API key was rejected. Check it and try again."
        case .rateLimited: return "Rate limited by the API. Try again in a moment."
        case .server(let status, let message): return "API error \(status): \(message)"
        case .transport(let message): return "Network problem: \(message)"
        case .decoding(let message): return "Unexpected API response: \(message)"
        case .refused: return "Claude declined to answer that."
        }
    }
}

public protocol ClaudeClient: Sendable {
    func send(_ request: MessagesRequest) async throws -> MessagesResponse
}

/// Talks to the Messages API over URLSession.
public struct AnthropicClient: ClaudeClient {
    public static let defaultModel = "claude-haiku-4-5"
    public static let apiVersion = "2023-06-01"

    private let endpoint: URL
    private let apiKey: @Sendable () -> String?
    private let session: URLSession

    public init(
        apiKey: @escaping @Sendable () -> String?,
        endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.session = session
    }

    public func send(_ request: MessagesRequest) async throws -> MessagesResponse {
        guard let key = apiKey(), !key.isEmpty else { throw ClaudeError.missingAPIKey }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.timeoutInterval = 90
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw ClaudeError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw Self.error(status: status, body: data)
        }

        do {
            return try JSONDecoder().decode(MessagesResponse.self, from: data)
        } catch {
            throw ClaudeError.decoding(error.localizedDescription)
        }
    }

    /// Maps an error body onto something worth showing a person.
    static func error(status: Int, body: Data) -> ClaudeError {
        struct ErrorEnvelope: Decodable {
            struct Inner: Decodable { let type: String?; let message: String? }
            let error: Inner?
        }
        let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: body))?.error?.message
            ?? String(data: body, encoding: .utf8)
            ?? "no details"
        switch status {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        default: return .server(status: status, message: message)
        }
    }
}
