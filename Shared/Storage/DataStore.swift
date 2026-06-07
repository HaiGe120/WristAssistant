import Foundation
import SwiftData

public enum DataStore {
    public static let schema = Schema([Conversation.self, Message.self])

    @MainActor
    public static let shared: ModelContainer = {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            assertionFailure("Failed to create ModelContainer: \(error). Falling back to in-memory.")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: memory)
        }
    }()
}
