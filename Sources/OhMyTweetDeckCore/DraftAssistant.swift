import Foundation

/// An OpenAI-compatible chat endpoint: OpenRouter, a local Ollama, or anything speaking the
/// same `/chat/completions` shape.
public struct AIProvider: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case openRouter, ollama, custom
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .openRouter: return "OpenRouter"
            case .ollama: return "Ollama (local)"
            case .custom: return "Custom (OpenAI-compatible)"
            }
        }
        public var defaultBaseURL: String {
            switch self {
            case .openRouter: return "https://openrouter.ai/api/v1"
            case .ollama: return "http://localhost:11434/v1"
            case .custom: return ""
            }
        }
        public var needsKey: Bool { self == .openRouter }
    }

    public var kind: Kind
    public var baseURL: URL
    public var apiKey: String?
    public var model: String

    public init(kind: Kind, baseURL: URL, apiKey: String?, model: String) {
        self.kind = kind
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }
}

/// What to do with the draft.
public enum DraftRewrite: String, CaseIterable, Sendable, Identifiable {
    case polish, shorter, fixGrammar, english
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .polish: return "Polish"
        case .shorter: return "Make shorter"
        case .fixGrammar: return "Fix spelling & grammar"
        case .english: return "Translate to English"
        }
    }
    var instruction: String {
        switch self {
        case .polish: return "Polish this post so it reads naturally and engagingly. Keep its meaning, voice and language."
        case .shorter: return "Make this post noticeably shorter while keeping its point, voice and language."
        case .fixGrammar: return "Fix spelling, spacing and grammar only. Change nothing else. Keep the language."
        case .english: return "Translate this post into natural English for social media. Keep its tone."
        }
    }
}

public struct DraftAssistantError: Error, Equatable, CustomStringConvertible {
    public var message: String
    public var description: String { message }
}

/// Rewrites a draft with an LLM. Only the draft text is sent to the provider.
public struct DraftAssistant: Sendable {
    public let provider: AIProvider
    let transport: HTTPTransport

    public init(provider: AIProvider, transport: HTTPTransport = URLSession.shared) {
        self.provider = provider
        self.transport = transport
    }

    /// `limit` is the tightest character budget among the selected services, if any.
    public func rewrite(_ text: String, _ mode: DraftRewrite, limit: Int?) async throws -> String {
        var system = """
        You edit short social media posts for X, Threads and Instagram. \(mode.instruction)
        Keep URLs, @mentions and #hashtags exactly as written. Do not add hashtags or emoji that were not there.
        Reply with the rewritten post only: no quotes, no preamble, no explanation.
        """
        if let limit { system += "\nThe result must fit in \(limit) characters." }
        let body: [String: Any] = [
            "model": provider.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": text]],
            "temperature": mode == .fixGrammar ? 0.1 : 0.6,
            "stream": false,
        ]
        var request = URLRequest(url: provider.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = provider.apiKey, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if provider.kind == .openRouter { request.setValue("Oh My TweetDeck", forHTTPHeaderField: "X-Title") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.send(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(response.statusCode) else {
            let error = (json["error"] as? [String: Any])?["message"] as? String ?? json["error"] as? String
            throw DraftAssistantError(message: "HTTP \(response.statusCode): \(error ?? String(decoding: data.prefix(200), as: UTF8.self))")
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw DraftAssistantError(message: "Unexpected response from \(provider.kind.displayName)")
        }
        return Self.clean(content)
    }

    /// Model ids the endpoint offers (`GET /models`), for the Settings picker.
    public func models() async throws -> [String] {
        var request = URLRequest(url: provider.baseURL.appending(path: "models"))
        if let key = provider.apiKey, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DraftAssistantError(message: "Could not list models (HTTP \(response.statusCode))")
        }
        // Ollama answers `"data": null` when no model is pulled yet.
        let list = json["data"] as? [[String: Any]] ?? []
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    /// Strips reasoning blocks (`<think>…</think>`) and wrapping quotes some models add.
    static func clean(_ content: String) -> String {
        var text = content
        while let start = text.range(of: "<think>"), let end = text.range(of: "</think>", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("\"", "\""), ("“", "”"), ("「", "」")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > 1 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
