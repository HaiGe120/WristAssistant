//  ChatView.swift
//  Watch chat view with a simple inline reply box at the bottom.
//  Reverts the iMessage-style floating overlay, scroll sentinel, and
//  focus-burst tricks — the basic shape the user had working before.

import SwiftUI
import SwiftData
import os.log

private let chatLog = Logger(subsystem: "com.wristassistant.app.watchkitapp", category: "ChatView")

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var endpoints: EndpointStore
    @Bindable var conversation: Conversation

    @StateObject private var engine = ChatEngine()
    @State private var draft: String = ""
    @State private var lastError: String?
    /// Live buffer of the assistant's in-progress reply. Mirrors the
    /// iOS pattern: accumulate into this `@State` so the row updates
    /// in real time, then flush the final value into the SwiftData
    /// `Message` on stream completion.
    @State private var streamingContent: String = ""
    @State private var presentingEndpointPicker = false

    private var endpoint: EndpointConfig? {
        endpoints.endpoints.first(where: { $0.id == conversation.endpointID })
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            messages
            Divider()
            ComposerView(
                text: $draft,
                isStreaming: engine.isStreaming,
                canSend: canSend,
                onSend: send
            )
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentingEndpointPicker = true
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
                .disabled(endpoints.endpoints.count < 2)
            }
        }
        .sheet(isPresented: $presentingEndpointPicker) {
            NavigationStack {
                EndpointPickerSheet(conversation: conversation)
            }
        }
        .alert("Error", isPresented: .init(
            get: { lastError != nil },
            set: { if !$0 { lastError = nil } }
        )) {
            Button("OK", role: .cancel) { lastError = nil }
        } message: {
            Text(lastError ?? "")
        }
    }

    /// Scrollable list of messages. Plain ScrollView + LazyVStack — no
    /// scroll sentinel, no auto-hide. Auto-scrolls to the newest
    /// message on appear and whenever a new message is appended.
    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(conversation.sortedMessages) { message in
                        WatchMessageRow(
                            message: message,
                            streamingOverride: streamingOverride(for: message)
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onAppear {
                if let last = conversation.sortedMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: conversation.messages.count) { _, _ in
                if let last = conversation.sortedMessages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// The live streaming buffer applies only to the most recent
    /// assistant message while the engine is producing deltas.
    private func streamingOverride(for message: Message) -> String? {
        guard engine.isStreaming, message.role == .assistant else { return nil }
        guard let lastAssistant = conversation.sortedMessages.last(where: { $0.role == .assistant }) else {
            return nil
        }
        guard lastAssistant.id == message.id else { return nil }
        return streamingContent
    }

    private func send() {
        if engine.isStreaming {
            engine.cancel()
            return
        }
        guard canSend, let endpoint else { return }
        let userText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        streamingContent = ""

        let apiKey = endpoints.apiKey(for: endpoint.id)
        let userMessage = Message(role: .user, content: userText, orderIndex: conversation.messages.count, conversation: conversation)
        let assistantMessage = Message(role: .assistant, content: "", orderIndex: conversation.messages.count + 1, conversation: conversation)
        modelContext.insert(userMessage)
        modelContext.insert(assistantMessage)
        conversation.updatedAt = .now
        if conversation.title == "New chat" {
            conversation.title = userText.prefix(40).description
        }

        let history = conversation.sortedMessages
            .filter { $0.role != .system }
            .map { ChatMessage(role: $0.role, content: $0.content) }

        engine.send(endpoint: endpoint, apiKey: apiKey, messages: history) { delta in
            streamingContent += delta
        } onComplete: {
            let final = streamingContent
            assistantMessage.content = final
            if final.isEmpty, let err = engine.lastError {
                assistantMessage.content = "⚠️ \(err)"
            }
            streamingContent = ""
            try? modelContext.save()
            SyncCoordinator.shared.publishConversation(ConversationSnapshot(conversation))
        }
    }
}

private struct WatchMessageRow: View {
    let message: Message
    let streamingOverride: String?

    private var isUser: Bool { message.role == .user }

    private var displayContent: String {
        if let streamingOverride, !streamingOverride.isEmpty {
            return streamingOverride
        }
        return message.content
    }

    @ViewBuilder
    private var renderedContent: some View {
        let raw = displayContent
        if raw.isEmpty {
            Text("…")
        } else if let attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(raw)
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 24) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
                renderedContent
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(isUser ? Color.accentColor : Color.gray.opacity(0.25))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }
            if !isUser { Spacer(minLength: 24) }
        }
    }
}

private struct EndpointPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var endpoints: EndpointStore
    @Bindable var conversation: Conversation

    var body: some View {
        List(endpoints.endpoints) { endpoint in
            Button {
                conversation.endpointID = endpoint.id
                conversation.endpointName = endpoint.name
                conversation.model = endpoint.model
                conversation.systemPrompt = endpoint.systemPrompt
                conversation.updatedAt = .now
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(endpoint.name)
                        Text(endpoint.model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if endpoint.id == conversation.endpointID {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        .navigationTitle("Switch Endpoint")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
