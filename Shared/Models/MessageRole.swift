import Foundation

public enum MessageRole: String, Codable, Sendable, CaseIterable {
    case system
    case user
    case assistant
}
