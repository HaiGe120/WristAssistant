import Foundation

/// Native Anthropic Messages API and any third-party server that speaks the same
/// shape (custom-base-URL Anthropic-format proxies, self-hosted Claude, etc.).
///
/// Wire format: `POST {baseURL}/v1/messages`, headers `x-api-key` + `anthropic-version`,
/// streaming via SSE with `event:` lines (`content_block_delta` carries text in
/// `delta.text`).
public struct AnthropicProvider: AIProvider {
    public let providerType: AIProviderType

    public init(providerType: AIProviderType = .anthropic) {
        self.providerType = providerType
    }

    public func stream(endpoint: EndpointConfig, apiKey: String?, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let request = try Self.buildRequest(endpoint: endpoint, apiKey: apiKey, messages: messages)
                    let (bytes, _) = try await StreamingHTTP.send(request)

                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let event = parser.feed(line: line) else { continue }
                        if let text = Self.extractText(eventType: event.event, data: event.data) {
                            if !text.isEmpty { continuation.yield(text) }
                        }
                    }
                    if Task.isCancelled {
                        continuation.finish(throwing: APIError.cancelled)
                    } else {
                        continuation.finish()
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: APIError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func listModels(endpoint: EndpointConfig, apiKey: String?) async throws -> [String] {
        // Native Anthropic has no public models endpoint, so the curated
        // Claude list is the best we can do there. This is the ONLY case
        // where it's appropriate to surface Claude names — for any other
        // provider we'd be lying about what the server offers.
        guard endpoint.providerType == .anthropicCompatible || endpoint.providerType == .anthropic else {
            return Self.defaultModelSuggestions
        }
        // For Anthropic-compatible third-party servers (MiniMax, Cloudflare
        // Workers AI, self-hosted gateways, …), probe a few common
        // models-endpoint paths and return whatever the server actually
        // answers with. We deliberately do NOT fall back to the Claude
        // list here, because doing so silently replaces the server's
        // catalog with Anthropic's — the user thinks they're seeing what
        // their server offers when really they're seeing Claude names.
        let base = endpoint.baseURL
        guard let base else {
            throw APIError.invalidURL(endpoint.baseURLString)
        }
        var lastError: Error?
        // Probe paths are relative to the base URL. We try a few common
        // shapes because Anthropic-compatible gateways disagree on whether
        // the API root is the origin (e.g. https://api.minimaxi.com) or
        // the origin with a /v1 prefix (e.g. https://api.minimaxi.com/v1).
        // Using URL(string:relativeTo:) instead of appendingPathComponent
        // avoids the doubled-path bug that bit MiniMax: with the old code,
        // a base of https://api.minimaxi.com/v1 plus a candidate of
        // "/v1/models" produced a request to /v1/v1/models — 404 every
        // time — and the user was left guessing why the picker was empty.
        let candidates = ["v1/models", "models"]
        for path in candidates {
            guard let url = URL(string: path, relativeTo: base)?.absoluteURL else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let key = apiKey, !key.isEmpty {
                request.setValue(key, forHTTPHeaderField: "x-api-key")
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
            do {
                let models = try await Self.fetchModels(request: request)
                if !models.isEmpty { return models }
            } catch {
                // Remember the first real error so the caller can show
                // something useful (e.g. "HTTP 401") instead of a generic
                // "no models returned".
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    private static func fetchModels(request: URLRequest) async throws -> [String] {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Non-HTTP response from models endpoint")
        }
        if !(200..<300).contains(http.statusCode) {
            // Surface the real status so the editor UI can tell the user
            // *why* the probe failed (e.g. 401, 403, 404) instead of
            // masking it as "no models returned".
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: http.statusCode, body: body)
        }
        // OpenAI-style { "data": [{ "id": "..." }] }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let arr = obj["data"] as? [[String: Any]] {
                let ids = arr.compactMap { $0["id"] as? String }.sorted()
                if !ids.isEmpty { return ids }
            }
            // Some gateways use { "models": [{ "name": "..." }] }
            if let arr = obj["models"] as? [[String: Any]] {
                let ids = arr.compactMap {
                    ($0["name"] as? String) ?? ($0["id"] as? String)
                }.sorted()
                if !ids.isEmpty { return ids }
            }
        }
        // 2xx with a body shape we don't recognise: not a hard error,
        // just nothing to show. Returning [] lets the caller try the next
        // candidate path.
        return []
    }

    public static let defaultModelSuggestions: [String] = [
        "claude-3-5-sonnet-latest",
        "claude-3-5-haiku-latest",
        "claude-3-opus-latest",
        "claude-3-sonnet-20240229",
        "claude-3-haiku-20240307"
    ]

    // MARK: - Request building

    static func buildRequest(endpoint: EndpointConfig, apiKey: String?, messages: [ChatMessage]) throws -> URLRequest {
        guard let url = endpoint.chatCompletionsURL() else {
            throw APIError.invalidURL(endpoint.baseURLString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let key = apiKey, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        for (k, v) in endpoint.customHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        var apiMessages: [AnthropicMessage] = []
        let system = endpoint.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        for m in messages where m.role != .system {
            apiMessages.append(.init(role: m.role.rawValue, content: m.content))
        }

        let payload = AnthropicRequest(
            model: endpoint.model,
            messages: apiMessages,
            system: system.isEmpty ? nil : system,
            maxTokens: endpoint.maxTokens ?? 1024,
            temperature: endpoint.temperature,
            stream: true
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    // MARK: - Response parsing

    static func extractText(eventType: String?, data: String) -> String? {
        guard let eventType else { return nil }
        guard let jsonData = data.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        switch eventType {
        case "content_block_delta":
            if let delta = obj["delta"] as? [String: Any],
               delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String {
                return text
            }
        case "message_start", "message_delta", "message_stop",
             "content_block_start", "content_block_stop", "ping":
            return nil
        default:
            return nil
        }
        return nil
    }
}

private struct AnthropicRequest: Encodable {
    let model: String
    let messages: [AnthropicMessage]
    let system: String?
    let maxTokens: Int
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, system, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}
