import SwiftUI

struct EndpointEditorView: View {
    @EnvironmentObject private var endpoints: EndpointStore
    @Environment(\.dismiss) private var dismiss

    @State private var id: UUID = UUID()
    @State private var name: String = ""
    @State private var providerType: AIProviderType = .openAICompatible
    @State private var baseURLString: String = ""
    @State private var model: String = ""
    @State private var systemPrompt: String = ""
    @State private var temperature: Double = 0.7
    @State private var apiKey: String = ""
    @State private var hasExistingKey: Bool = false
    @State private var isTestingConnection = false
    @State private var testResult: String?
    @State private var fetchedModels: [String] = []
    @State private var useCustomModel: Bool = false
    @State private var isNew: Bool = true

    private let existing: EndpointConfig?

    init(endpoint: EndpointConfig?) {
        self.existing = endpoint
        _id = State(initialValue: endpoint?.id ?? UUID())
        _name = State(initialValue: endpoint?.name ?? "")
        // Collapse legacy .openAI / .anthropic to their compat equivalents
        // so the picker — which only offers the two compat cases — has a
        // matching tag for the current selection. On save, the migrated
        // type is what gets persisted.
        _providerType = State(initialValue: (endpoint?.providerType ?? .openAICompatible).migrated)
        _baseURLString = State(initialValue: endpoint?.baseURLString ?? "")
        _model = State(initialValue: endpoint?.model ?? "")
        _systemPrompt = State(initialValue: endpoint?.systemPrompt ?? "")
        _temperature = State(initialValue: endpoint?.temperature ?? 0.7)
        _isNew = State(initialValue: endpoint == nil)
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name (e.g. My Open WebUI)", text: $name)
                Picker("Provider", selection: $providerType) {
                    ForEach(AIProviderType.pickerCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: providerType) { _, _ in
                    // No more auto-filled base URL: every endpoint now
                    // requires the user to type the URL. We still clear
                    // any server-fetched model list because the model
                    // catalog is per-shape.
                    fetchedModels = []
                    useCustomModel = false
                }
                .onChange(of: baseURLString) { _, _ in
                    fetchedModels = []
                    useCustomModel = false
                }
            }
            Section("Connection") {
                TextField("Base URL", text: $baseURLString)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                if fetchedModels.isEmpty || useCustomModel {
                    TextField("Model", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !fetchedModels.isEmpty {
                        Button("Pick from \(fetchedModels.count) loaded models") {
                            useCustomModel = false
                        }
                        .font(.caption)
                    }
                } else {
                    Picker("Model", selection: $model) {
                        ForEach(fetchedModels, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        Text("Custom…").tag("__custom__")
                    }
                    .onChange(of: model) { _, new in
                        if new == "__custom__" {
                            useCustomModel = true
                            // Restore the previous non-custom value so the
                            // field isn't blank when the user comes back.
                            if let last = fetchedModels.first(where: { $0 != "__custom__" }) {
                                model = last
                            } else {
                                model = ""
                            }
                        }
                    }
                }
                SecureField(apiKeyPlaceholder, text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if hasExistingKey && apiKey.isEmpty {
                    Text("An API key is saved. Leave blank to keep it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Behavior") {
                TextField("System prompt (optional)", text: $systemPrompt, axis: .vertical)
                    .lineLimit(1...4)
                VStack(alignment: .leading) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", temperature))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $temperature, in: 0...2, step: 0.05)
                }
            }
            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTestingConnection { ProgressView() }
                        Text(isTestingConnection ? "Testing…" : "Test connection & load models")
                    }
                }
                .disabled(model.isEmpty || isTestingConnection)
                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(isNew ? "New Endpoint" : "Edit Endpoint")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            // Surface the "Set as Active" affordance here too so the
            // user can promote an existing endpoint to active without
            // going through the row's context menu. The button is a
            // no-op when this endpoint is already active.
            ToolbarItem(placement: .topBarLeading) {
                if endpoints.activeEndpointID != id {
                    Button {
                        endpoints.setActive(id)
                    } label: {
                        Label("Set active", systemImage: "checkmark.circle")
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(name.isEmpty || model.isEmpty)
            }
        }
        .onAppear {
            if !isNew, let existing {
                let stored = endpoints.apiKey(for: existing.id) ?? ""
                hasExistingKey = !stored.isEmpty
                if apiKey.isEmpty {
                    apiKey = stored
                }
            }
            // No auto-fill of the base URL: the user enters it.
            // (Previously this defaulted to api.openai.com / api.anthropic
            // for the now-removed native cases.)
        }
    }

    private var apiKeyPlaceholder: String {
        switch providerType {
        case .openAI, .openAICompatible: return "API key (sk-…, or leave blank for local servers)"
        case .anthropic, .anthropicCompatible: return "API key (sk-ant-…, or leave blank for local servers)"
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
        #if DEBUG
        // Diagnostics for the "API key doesn't survive a save" bug. Logs
        // go to Xcode console; in the sim they're visible via
        // `xcrun simctl spawn ... log stream` or the Console.app UI.
        // Read AFTER the keychain write so the log reflects the
        // post-save state, not the pre-save state.
        let persistedKey = endpoints.apiKey(for: id) ?? "<nil>"
        print("[WristAssistant] save: id=\(id) apiKeyTyped=\(apiKey.isEmpty ? "<empty>" : "<len \(apiKey.count)>") persistedKeyAfterSave=\(persistedKey.isEmpty ? "<empty>" : "<len \(persistedKey.count)>")")
        #endif
        if endpoints.activeEndpointID == nil {
            endpoints.setActive(id)
        }
        dismiss()
    }

    private func testConnection() {
        testResult = nil
        fetchedModels = []
        useCustomModel = false
        isTestingConnection = true
        let testEndpoint = EndpointConfig(
            id: id,
            name: name,
            providerType: providerType,
            baseURLString: baseURLString,
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature
        )
        let key = apiKey.isEmpty ? endpoints.apiKey(for: id) : apiKey
        #if DEBUG
        let resolvedURL = testEndpoint.baseURL?.absoluteString ?? "<nil baseURL>"
        let composedURL = (URL(string: "models", relativeTo: testEndpoint.baseURL)?.absoluteURL.absoluteString) ?? "<nil>"
        print("[WristAssistant] test: id=\(id) providerType=\(providerType) baseURLString=\(testEndpoint.baseURLString) trimmedBaseURL=\(resolvedURL) composedModelsURL=\(composedURL) keySource=\(apiKey.isEmpty ? "keychain" : "form") keyLen=\(key?.count ?? 0)")
        #endif
        let provider = ProviderRegistry.provider(for: providerType)
        Task {
            do {
                let models = try await provider.listModels(endpoint: testEndpoint, apiKey: key)
                await MainActor.run {
                    fetchedModels = models
                    if models.isEmpty {
                        testResult = "Server reachable, but no models returned. The endpoint may require a different auth scheme, or the /v1/models path may be disabled."
                    } else {
                        testResult = "✓ Loaded \(models.count) model\(models.count == 1 ? "" : "s")."
                        if !models.contains(model) {
                            // Snap to the first server-confirmed model so the
                            // picker is ready to use; user can still override.
                            model = models.first ?? model
                        }
                    }
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    testResult = "✗ \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                    isTestingConnection = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        EndpointEditorView(endpoint: nil)
            .environmentObject(EndpointStore.shared)
    }
}
