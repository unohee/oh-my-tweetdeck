import Foundation

/// Minimal HTTP seam so publishers can be tested without the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Error returned by a Meta Graph-style API (`{"error": {"message": ..., "code": ...}}`).
public struct GraphAPIError: Error, Equatable, CustomStringConvertible {
    public var status: Int
    public var message: String
    public var code: Int?

    public var description: String {
        "HTTP \(status)\(code.map { " (code \($0))" } ?? ""): \(message)"
    }
}

/// Shared helpers for the Threads and Instagram Graph APIs, which use the same shapes.
struct GraphClient: Sendable {
    let base: URL
    let accessToken: String
    let transport: HTTPTransport

    /// Form-encoded POST. The token goes in the Authorization header, never the URL,
    /// so it does not end up in logs or proxies.
    func post(_ path: String, form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(form).data(using: .utf8)
        return try await send(request)
    }

    func get(_ path: String, query: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await transport.send(request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if !(200..<300).contains(response.statusCode) || json["error"] != nil {
            let error = json["error"] as? [String: Any]
            throw GraphAPIError(
                status: response.statusCode,
                message: error?["message"] as? String ?? String(decoding: data.prefix(300), as: UTF8.self),
                code: error?["code"] as? Int)
        }
        return json
    }

    /// application/x-www-form-urlencoded with a strict unreserved set, so '+', '&' and '='
    /// in post text survive.
    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.sorted { $0.key < $1.key }.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed)!
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed)!
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}
