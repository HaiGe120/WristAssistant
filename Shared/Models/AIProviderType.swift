import Foundation

/// The wire format the endpoint speaks. There are two provider families:
/// OpenAI-compatible endpoints (`/v1/chat/completions` or `/v1/responses`) and
/// Anthropic-compatible endpoints (`/v1/messages`). Pointing either family at a
/// third-party server is just a matter of editing the base URL, so we collapsed
/// the picker from four
/// cases ("native" + "compatible" for each) down to two.
///
/// Historical note: the old `.openAI` / `.anthropic` cases are kept in the
/// enum only for forward-decoding compatibility with EndpointConfig blobs
/// already on disk. New endpoints are always created with one of the two
/// compat cases, and `pickerCases` is the source of truth for the UI.
public enum AIProviderType: String, CaseIterable, Codable, Identifiable, Sendable {
    case openAI
    case anthropic
    case openAICompatible
    case anthropicCompatible

    public var id: String { rawValue }

    /// The two cases shown in the endpoint editor's provider picker.
    /// `openAI` and `anthropic` are intentionally absent — the user can
    /// reach those services by typing `https://api.openai.com/v1` or
    /// `https://api.anthropic.com` into the Base URL field.
    public static let pickerCases: [AIProviderType] = [
        .openAICompatible,
        .anthropicCompatible,
    ]

    public var displayName: String {
        switch self {
        case .openAI, .openAICompatible: return "Chat API (OpenAI format)"
        case .anthropic, .anthropicCompatible: return "Chat API (Anthropic format)"
        }
    }

    public var shortName: String {
        switch self {
        case .openAI, .openAICompatible: return "Chat API"
        case .anthropic, .anthropicCompatible: return "Chat API"
        }
    }

    /// Per-family default chat path. OpenAI Responses is selected by typing a
    /// Base URL that ends in `/responses`.
    public var defaultChatPath: String {
        switch self {
        case .openAI, .openAICompatible: return "/chat/completions"
        case .anthropic, .anthropicCompatible: return "/v1/messages"
        }
    }

    /// True if this case can still appear in decoded data from before the
    /// picker collapse. Used to migrate old endpoints to the equivalent
    /// compat case the first time the editor opens them.
    public var isLegacy: Bool {
        switch self {
        case .openAI, .anthropic: return true
        case .openAICompatible, .anthropicCompatible: return false
        }
    }

    /// Map a legacy case to the equivalent compat case. Used when opening
    /// an old endpoint so the picker selection always lands on something
    /// that is actually pickable.
    public var migrated: AIProviderType {
        switch self {
        case .openAI: return .openAICompatible
        case .anthropic: return .anthropicCompatible
        case .openAICompatible, .anthropicCompatible: return self
        }
    }
}
