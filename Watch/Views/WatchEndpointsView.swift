import SwiftUI
import SwiftData

struct WatchEndpointsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var endpoints: EndpointStore
    @EnvironmentObject private var sync: SyncCoordinator
    @State private var presentingNew = false
    @State private var editing: EndpointConfig?

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: sync.isCompanionReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                        .foregroundStyle(sync.isCompanionReachable ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sync.isCompanionReachable ? "iPhone reachable" : "iPhone not reachable")
                            .font(.caption)
                        if endpoints.endpoints.isEmpty {
                            Text("Pull endpoints from iPhone to start.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(endpoints.endpoints.count) endpoint\(endpoints.endpoints.count == 1 ? "" : "s") synced")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        SyncCoordinator.shared.requestEndpoints()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Section("Configured") {
                if endpoints.endpoints.isEmpty {
                    Text("No endpoints yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(endpoints.endpoints) { e in
                        Button {
                            editing = e
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.name)
                                    Text(e.model)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if e.id == endpoints.activeEndpointID {
                                    Image(systemName: "checkmark")
                                }
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
            Section {
                Button {
                    presentingNew = true
                } label: {
                    Label("Add endpoint", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Endpoints")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $presentingNew) {
            NavigationStack {
                WatchEndpointEditor(endpoint: nil)
            }
        }
        .sheet(item: $editing) { endpoint in
            NavigationStack {
                WatchEndpointEditor(endpoint: endpoint)
            }
        }
    }
}

struct WatchEndpointEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var endpoints: EndpointStore

    @State private var id: UUID = UUID()
    @State private var name: String = ""
    @State private var providerType: AIProviderType = .openAICompatible
    @State private var baseURLString: String = ""
    @State private var model: String = ""
    @State private var systemPrompt: String = ""
    @State private var temperature: Double = 0.7
    @State private var apiKey: String = ""
    @State private var hasExistingKey: Bool = false
    @State private var isNew: Bool = true

    init(endpoint: EndpointConfig?) {
        _id = State(initialValue: endpoint?.id ?? UUID())
        _name = State(initialValue: endpoint?.name ?? "")
        _providerType = State(initialValue: endpoint?.providerType ?? .openAICompatible)
        _baseURLString = State(initialValue: endpoint?.baseURLString ?? "")
        _model = State(initialValue: endpoint?.model ?? "")
        _systemPrompt = State(initialValue: endpoint?.systemPrompt ?? "")
        _temperature = State(initialValue: endpoint?.temperature ?? 0.7)
        _isNew = State(initialValue: endpoint == nil)
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $name)
                Picker("Provider", selection: $providerType) {
                    ForEach(AIProviderType.allCases) { type in
                        Text(shortName(type)).tag(type)
                    }
                }
            }
            Section("Connection") {
                TextField("Base URL", text: $baseURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Model", text: $model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(apiKeyPlaceholder, text: $apiKey)
                if hasExistingKey && apiKey.isEmpty {
                    Text("Saved key on file. Leave blank to keep.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Behavior") {
                TextField("System prompt", text: $systemPrompt, axis: .vertical)
                    .lineLimit(1...3)
                HStack {
                    Text("Temp")
                    Spacer()
                    Text(String(format: "%.2f", temperature))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $temperature, in: 0...2, step: 0.1)
            }
        }
        .navigationTitle(isNew ? "New Endpoint" : "Edit Endpoint")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.isEmpty || model.isEmpty)
            }
        }
        .onAppear {
            if !isNew, let existing = endpoints.endpoints.first(where: { $0.id == id }) {
                let stored = endpoints.apiKey(for: existing.id) ?? ""
                hasExistingKey = !stored.isEmpty
                if apiKey.isEmpty {
                    apiKey = stored
                }
            }
            // No auto-fill of the base URL: the user enters it.
        }
    }

    private func shortName(_ type: AIProviderType) -> String {
        switch type {
        case .openAI, .openAICompatible: return "Chat API"
        case .anthropic, .anthropicCompatible: return "Chat API"
        }
    }

    private var apiKeyPlaceholder: String {
        switch providerType {
        case .openAI, .openAICompatible: return "API key (sk-…)"
        case .anthropic, .anthropicCompatible: return "API key (sk-ant-…)"
        }
    }

    private func save() {
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = EndpointConfig(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            providerType: providerType,
            baseURLString: trimmedURL,
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPrompt: systemPrompt,
            temperature: temperature
        )
        endpoints.save(config)
        if !apiKey.isEmpty {
            endpoints.setAPIKey(apiKey, for: id)
        } else if isNew {
            endpoints.setAPIKey("", for: id)
        }
        if endpoints.activeEndpointID == nil {
            endpoints.setActive(id)
        }
        dismiss()
    }
}
