import Foundation

public enum APIError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case http(status: Int, body: String)
    case decoding(String)
    case missingAPIKey
    case cancelled
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid URL: \(s)"
        case .http(let status, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "HTTP \(status)" }
            if trimmed.count > 400 { return "HTTP \(status): \(trimmed.prefix(400))…" }
            return "HTTP \(status): \(trimmed)"
        case .decoding(let s): return "Decoding error: \(s)"
        case .missingAPIKey: return "Missing API key for this endpoint."
        case .cancelled: return "Cancelled"
        case .transport(let s): return s
        }
    }
}

public protocol AIProvider: Sendable {
    var providerType: AIProviderType { get }
    func stream(endpoint: EndpointConfig, apiKey: String?, messages: [ChatMessage]) -> AsyncThrowingStream<String, Error>
    func listModels(endpoint: EndpointConfig, apiKey: String?) async throws -> [String]
}
