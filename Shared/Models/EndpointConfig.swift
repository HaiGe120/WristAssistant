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
        // The base URL is always user-supplied now (the picker was
        // collapsed to compat-only). Falling back to a hard-coded
        // default would re-introduce the OpenAI/Anthropic magic the
        // user just asked us to remove.
        guard let base = baseURL else { return nil }
        return Self.resolveChatURL(base: base, chatPath: providerType.defaultChatPath)
    }

    /// Compose `<base><chatPath>`, avoiding the doubled-prefix bug that
    /// bit MiniMax and other Anthropic-compatible gateways whose base
    /// URL already ends in `/v1`.
    ///
    /// The chat path can be expressed two ways depending on the provider:
    ///
    /// - **Sub-path form** (`/chat/completions`): the chat path is meant
    ///   to be appended to the base's existing path. With base
    ///   `https://api.openai.com/v1` this yields
    ///   `https://api.openai.com/v1/chat/completions` — the desired
    ///   OpenAI URL.
    /// - **Absolute form** (`/v1/messages`): the chat path is the full
    ///   absolute path. With base `https://api.minimaxi.com/v1` we want
    ///   `https://api.minimaxi.com/v1/messages`, not
    ///   `https://api.minimaxi.com/v1/v1/messages`.
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

    public static let sampleOpenWebUI = EndpointConfig(
        name: "Open WebUI (local)",
        providerType: .openAICompatible,
        baseURLString: "http://localhost:8080/v1",
        model: "llama3.1"
    )

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
