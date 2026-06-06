import Foundation

/// Handles both native OpenAI and OpenAI-compatible servers (Open WebUI, Ollama,
/// LM Studio, vLLM, etc). They share the same wire format.
public struct OpenAIProvider: AIProvider {
    public let providerType: AIProviderType

    public init(providerType: AIProviderType) {
        self.providerType = providerType
    }

    public func stream(endpoint: EndpointConfig, apiKey: String?, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try Task.checkCancellation()
                    let request = try Self.buildRequest(endpoint: endpoint, apiKey: apiKey, messages: messages, stream: true)
                    #if DEBUG
                    print("[WristAssistant] stream -> POST \(request.url?.absoluteString ?? "?") keySet=\(apiKey?.isEmpty == false)")
                    #endif
                    let (bytes, response) = try await StreamingHTTP.send(request)
                    #if DEBUG
                    print("[WristAssistant] stream <- status \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    #endif

                    var parser = SSEParser()
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard let event = parser.feed(line: line) else { continue }
                        if event.data == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        if let delta = Self.extractDelta(event.data) {
                            #if DEBUG
                            if !delta.isEmpty { print("[WristAssistant] delta(\(delta.count)): \(delta.prefix(80))") }
                            #endif
                            if !delta.isEmpty { continuation.yield(delta) }
                        } else if event.data != "[DONE]" {
                            #if DEBUG
                            print("[WristAssistant] no delta in: \(event.data.prefix(120))")
                            #endif
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
        let request = try Self.buildModelsRequest(endpoint: endpoint, apiKey: apiKey)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: status, body: body)
        }
        struct ListResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        if let decoded = try? JSONDecoder().decode(ListResponse.self, from: data) {
            return decoded.data.map(\.id).sorted()
        }
        // Some compatible servers use { "models": [...] } or { "object": "list", ... }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let arr = dict["data"] as? [[String: Any]] {
                return arr.compactMap { $0["id"] as? String }.sorted()
            }
            if let arr = dict["models"] as? [[String: Any]] {
                return arr.compactMap { ($0["name"] as? String) ?? ($0["id"] as? String) }.sorted()
            }
        }
        return []
    }

    // MARK: - Request building

    static func buildRequest(endpoint: EndpointConfig, apiKey: String?, messages: [ChatMessage], stream: Bool) throws -> URLRequest {
        guard let url = endpoint.chatCompletionsURL() else {
            throw APIError.invalidURL(endpoint.baseURLString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        // The Authorization header is only set when a key is present.
        // For servers that require a key (api.openai.com, etc.) the
        // server returns 401 and the caller surfaces that as the test
        // result; we no longer fail-fast with missingAPIKey because the
        // user might be pointing at a key-less local server (Ollama,
        // LM Studio) and shouldn't be blocked by a hard requirement.
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        for (k, v) in endpoint.customHeaders {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let payload = OpenAIRequest(
            model: endpoint.model,
            messages: Self.normalizedMessages(endpoint: endpoint, messages: messages),
            stream: stream,
            temperature: endpoint.temperature,
            maxTokens: endpoint.maxTokens
        )
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    static func buildModelsRequest(endpoint: EndpointConfig, apiKey: String?) throws -> URLRequest {
        guard let base = endpoint.baseURL else {
            throw APIError.invalidURL(endpoint.baseURLString)
        }
        // Resolve the "models" path relative to the configured base so
        // endpoints that include their own /v1 prefix (MiniMax, Groq, …)
        // don't end up at /v1/v1/models. See the matching change in
        // AnthropicProvider for the same fix on the Anthropic-compatible
        // path.
        guard let url = URL(string: "models", relativeTo: base)?.absoluteURL else {
            throw APIError.invalidURL(endpoint.baseURLString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    static fileprivate func normalizedMessages(endpoint: EndpointConfig, messages: [ChatMessage]) -> [OpenAIRequest.Message] {
        var out: [OpenAIRequest.Message] = []
        let system = endpoint.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            out.append(.init(role: "system", content: system))
        }
        for m in messages where m.role != .system {
            out.append(.init(role: m.role.rawValue, content: m.content))
        }
        return out
    }

    // MARK: - Response parsing

    static func extractDelta(_ json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let choices = obj["choices"] as? [[String: Any]],
           let first = choices.first,
           let delta = first["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            return content
        }
        // Some servers (Ollama) return "message" instead of "delta"
        if let choices = obj["choices"] as? [[String: Any]],
           let first = choices.first,
           let msg = first["message"] as? [String: Any],
           let content = msg["content"] as? String {
            return content
        }
        return nil
    }
}

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [Message]
    let stream: Bool
    let temperature: Double
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case maxTokens = "max_tokens"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}
