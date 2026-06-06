import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject private var endpoints: EndpointStore
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var presentingNew = false

    var body: some View {
        NavigationStack {
            List {
                Section("Apple Watch sync") {
                    HStack {
                        Image(systemName: syncIcon)
                            .foregroundStyle(syncTint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(syncTitle)
                            if let when = sync.lastSyncedAt {
                                Text("Last synced \(when, style: .relative) ago")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Endpoints, API keys, and chats are mirrored to the paired watch.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if let err = sync.lastError {
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                        Spacer()
                    }
                    Button {
                        // Use the activation-aware bootstrap so this
                        // also works if the user taps it before the
                        // session finishes activating (e.g. right
                        // after launch). requestBootstrap() defers
                        // the publish until the session is ready.
                        SyncCoordinator.shared.requestBootstrap()
                        sync.objectWillChange.send()
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Section("Endpoints") {
                    if endpoints.endpoints.isEmpty {
                        Text("No endpoints yet. Tap + to add one.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(endpoints.endpoints) { endpoint in
                            NavigationLink {
                                EndpointEditorView(endpoint: endpoint)
                            } label: {
                                EndpointRow(endpoint: endpoint, isActive: endpoint.id == endpoints.activeEndpointID)
                            }
                            .contextMenu {
                                // Long-press affordance for "Set as
                                // Active" — the Settings list only has
                                // tap-to-edit and swipe-to-delete, so
                                // without this the user had no way to
                                // promote a non-active row.
                                if endpoint.id != endpoints.activeEndpointID {
                                    Button {
                                        endpoints.setActive(endpoint.id)
                                    } label: {
                                        Label("Set as Active", systemImage: "checkmark.circle")
                                    }
                                }
                                Button(role: .destructive) {
                                    endpoints.delete(endpoint.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                endpoints.delete(endpoints.endpoints[index].id)
                            }
                        }
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Link("Open WebUI", destination: URL(string: "https://openwebui.com")!)
                    Link("OpenAI API docs", destination: URL(string: "https://platform.openai.com/docs/api-reference/chat")!)
                    Link("Anthropic API docs", destination: URL(string: "https://docs.anthropic.com/en/api/messages")!)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentingNew = true
                    } label: {
                        Label("Add endpoint", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $presentingNew) {
                NavigationStack {
                    EndpointEditorView(endpoint: nil)
                }
            }
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return short + " (" + build + ")"
    }

    private var syncTitle: String {
        switch sync.activationState {
        case .activated:
            return sync.isCompanionReachable ? "Watch is paired & reachable" : "Watch is paired (not reachable)"
        case .inactive: return "Watch sync not active"
        case .unsupported: return "Watch sync unsupported on this device"
        case .unknown: return "Starting watch sync…"
        }
    }

    private var syncIcon: String {
        guard sync.activationState == .activated else { return "antenna.radiowaves.left.and.right.slash" }
        return sync.isCompanionReachable ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right"
    }

    private var syncTint: Color {
        guard sync.activationState == .activated, sync.isCompanionReachable else { return .secondary }
        return .green
    }
}

private struct EndpointRow: View {
    let endpoint: EndpointConfig
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(endpoint.name).font(.headline)
                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                Text(endpoint.providerType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(endpoint.model)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(EndpointStore.shared)
        .modelContainer(DataStore.shared)
}
