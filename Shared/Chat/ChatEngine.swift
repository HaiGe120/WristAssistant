import Foundation

/// High-level engine that ties a conversation to a streaming provider.
/// Yields incremental text deltas as they arrive.
@MainActor
public final class ChatEngine: ObservableObject {
    @Published public private(set) var isStreaming: Bool = false
    @Published public var lastError: String?

    public init() {}

    public func send(
        endpoint: EndpointConfig,
        apiKey: String?,
        messages: [ChatMessage],
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) {
        guard !isStreaming else { return }
        isStreaming = true
        lastError = nil


        let provider = ProviderRegistry.provider(for: endpoint.providerType)
        let stream = provider.stream(endpoint: endpoint, apiKey: apiKey, messages: messages)

        Task { [weak self] in
            do {
                for try await delta in stream {
                    await MainActor.run { onDelta(delta) }
                }
                await MainActor.run {
                    self?.isStreaming = false
                    onComplete()
                }
            } catch {
                await MainActor.run {
                    self?.isStreaming = false
                    self?.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    onComplete()
                }
            }
        }
    }

    public func cancel() {
        isStreaming = false
    }
}
