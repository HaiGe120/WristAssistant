import AppIntents
import Foundation

/// Siri / Shortcut / Widget intent: "Start new chat in Wrist Assistant".
///
/// Tapping a Smart Stack tile, a complication, the App Shortcut on the watch
/// home screen, or invoking this from Siri will open the watch app on a fresh
/// conversation. `openAppWhenRun = true` brings the app forward; the watch
/// app then looks for the `wristassistant://new-chat` URL it was launched with
/// and presents the new-chat sheet.
public struct StartNewChatIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start new chat"
    public static var description = IntentDescription(
        "Open Wrist Assistant and start a new conversation with the active endpoint."
    )
    public static var openAppWhenRun: Bool = true

    /// Optional initial prompt to seed the composer with.
    @Parameter(title: "Prompt", default: "")
    public var prompt: String

    public init() {
        self.prompt = ""
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let key = "pendingNewChatPrompt"
        if let data = try? JSONEncoder().encode(NewChatRequest(prompt: prompt)) {
            UserDefaults.standard.set(data, forKey: key)
        }
        return .result(dialog: IntentDialog("Starting a new chat in Wrist Assistant."))
    }
}

public struct NewChatRequest: Codable, Sendable {
    public var prompt: String
    public init(prompt: String) { self.prompt = prompt }
}
