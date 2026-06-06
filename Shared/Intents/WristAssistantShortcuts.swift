import AppIntents

/// Surfaces `StartNewChatIntent` to Siri, Spotlight, and the Shortcuts app on
/// both the iPhone and the Apple Watch. Without an `AppShortcutsProvider` the
/// intent compiles but stays hidden from the system, so phrases like
/// "Start a new chat in Wrist Assistant" never resolve.
public struct WristAssistantShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartNewChatIntent(),
            phrases: [
                "Start a new chat in \(.applicationName)",
                "Open a new chat in \(.applicationName)",
                "Begin a new conversation in \(.applicationName)"
            ],
            shortTitle: "New Chat",
            systemImageName: "plus.bubble.fill"
        )
    }
}
