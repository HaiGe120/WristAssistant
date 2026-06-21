import Foundation

public struct EndpointConfig: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var providerType: AIProviderType
    public var baseURLString: String
    public var model: String
    public var systemPrompt: String
    public var temperature: Double
    public var maxTokens: Int?
    public var customHeaders: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        providerType: AIProviderType,
        baseURLString: String,
        model: String,
        systemPrompt: String = "",
        temperature: Double = 0.7,
        maxTokens: Int? = nil,
        customHeaders: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.providerType = providerType
        self.baseURLString = baseURLString
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.customHeaders = customHeaders
    }

    public var baseURL: URL? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    public func chatCompletionsURL() -> URL? {
        guard let base = baseURL else { return nil }
        return Self.resolveChatURL(base: base, chatPath: providerType.defaultChatPath)
    }

    public func modelsURL() -> URL? {
        guard let base = baseURL else { return nil }
        return Self.resolveModelsURL(base: base)
    }

    /// Compose `<base><chatPath>`, avoiding doubled-prefix bugs when the user
    /// pastes a full endpoint URL instead of an API root.
    ///
    /// The chat path can be expressed two ways depending on the provider:
    ///
    /// - **Sub-path form** (`/chat/completions`): the chat path is appended to
    ///   the API root, yielding `https://api.openai.com/v1/chat/completions`.
    /// - **Absolute form** (`/v1/messages`): the chat path is the full
    ///   absolute path and is kept intact for providers such as Anthropic.
    ///
    /// Foundation's `appendingPathComponent` always appends, so the
    /// absolute form collides whenever the base already has a matching
    /// prefix. We detect that collision and return the trimmed chat
    /// path as the absolute path on the origin.
    static func resolveChatURL(base: URL, chatPath: String) -> URL? {
        // Rebuild the origin (scheme + host + port) on its own. The
        // chat path will be reattached below. Using URLComponents here
        // (rather than `URL.absoluteString` splitting) avoids any
        // encoding surprises for non-ASCII hosts.
        guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        comps.path = ""
        comps.query = nil
        comps.fragment = nil
        guard let originURL = comps.url else { return base }
        let origin = originURL.absoluteString
        // Normalise the base path: drop trailing slashes but keep an
        // empty string for the origin-only case.
        let basePath = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmed = chatPath.hasPrefix("/") ? String(chatPath.dropFirst()) : chatPath
        if basePath == "v1/responses" || basePath.hasSuffix("/v1/responses") || basePath == "responses" || basePath.hasSuffix("/responses") {
            return URL(string: origin + "/" + basePath)
        }
        if !trimmed.isEmpty, (basePath == trimmed || basePath.hasSuffix("/" + trimmed)) {
            return URL(string: origin + "/" + basePath)
        }
        // Absolute form: the chat path already starts with the same
        // segment(s) the base path uses. Just put the trimmed chat
        // path directly on the origin.
        if !basePath.isEmpty, trimmed.hasPrefix(basePath + "/") {
            return URL(string: origin + "/" + trimmed)
        }
        // Sub-path form: append the trimmed chat path to the base path.
        if basePath.isEmpty {
            return URL(string: origin + "/" + trimmed)
        }
        return URL(string: origin + "/" + basePath + "/" + trimmed)
    }

    static func resolveModelsURL(base: URL) -> URL? {
        guard let comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base
        }
        var originComponents = comps
        originComponents.path = ""
        originComponents.query = nil
        originComponents.fragment = nil
        guard let originURL = originComponents.url else { return base }
        let origin = originURL.absoluteString
        var basePath = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath == "v1/chat/completions" || basePath.hasSuffix("/v1/chat/completions") {
            basePath = String(basePath.dropLast("/chat/completions".count))
        } else if basePath == "chat/completions" || basePath.hasSuffix("/chat/completions") {
            basePath = String(basePath.dropLast("/chat/completions".count))
        } else if basePath == "v1/responses" || basePath.hasSuffix("/v1/responses") {
            basePath = String(basePath.dropLast("/responses".count))
        } else if basePath == "responses" || basePath.hasSuffix("/responses") {
            basePath = String(basePath.dropLast("/responses".count))
        }
        basePath = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.hasSuffix("v1") {
            return URL(string: origin + "/" + basePath + "/models")
        }
        if basePath.isEmpty {
            return URL(string: origin + "/v1/models")
        }
        return URL(string: origin + "/" + basePath + "/v1/models")
    }

    public static let sampleAnthropicCompat = EndpointConfig(
        name: "Anthropic-compatible (custom)",
        providerType: .anthropicCompatible,
        baseURLString: "",
        model: "claude-3-5-sonnet-latest"
    )

    /// MiniMax via its OpenAI-compatible endpoint. Seeded into the store so the
    /// `WA_TEST_API_KEY` launch hook in `WristAssistantApp.init` can locate it by
    /// name and write the key into the keychain automatically during development.
    public static let sampleMiniMax = EndpointConfig(
        name: "MiniMax",
        providerType: .openAICompatible,
        baseURLString: "https://api.minimaxi.com/v1",
        model: "MiniMax-M3"
    )

    /// MiniMax via the Anthropic-compatible third-party mode. Same upstream
    /// server, but routed through the Anthropic Messages wire format so users
    /// can pick whichever their gateway expects. This is what exercises the
    /// `AnthropicProvider.listModels` server probe in non-native mode.
    public static let sampleMiniMaxAnthropic = EndpointConfig(
        name: "MiniMax (Anthropic-compatible)",
        providerType: .anthropicCompatible,
        // The Anthropic-compatible base on MiniMax is
        // https://api.minimaxi.com/anthropic (NOT /v1). The chat
        // resolver appends `/v1/messages` to whatever base is here, so
        // a /v1 base would produce /v1/messages and return 404 from
        // the gateway. The /anthropic base produces /anthropic/v1/messages
        // which is the documented endpoint.
        baseURLString: "https://api.minimaxi.com/anthropic",
        model: "MiniMax-M3"
    )
}
