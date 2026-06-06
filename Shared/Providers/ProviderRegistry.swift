import Foundation

public enum ProviderRegistry {
    public static func provider(for type: AIProviderType) -> AIProvider {
        switch type {
        case .openAI, .openAICompatible:
            return OpenAIProvider(providerType: type)
        case .anthropic, .anthropicCompatible:
            return AnthropicProvider(providerType: type)
        }
    }
}
