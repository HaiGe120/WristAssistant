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
    /// Live buffer of the assistant's in-progress reply. The visible
    /// assistant row reads this through `WatchMessageRow.streamingOverride`
    /// so the bubble re-renders for every delta. The final value is
    /// flushed into the persisted `Message` only when the stream
    /// completes — mirroring the iOS `ChatView` pattern. Mutating the
    /// SwiftData `@Model` property from the streaming closure can lag
    /// per-property observation, leaving the bubble stuck on its "…"
    /// placeholder.
    @State private var streamingContent: String = ""
    @State private var presentingEndpointPicker = false
    /// Bound to the composer TextField's `.focused(_:equals:)` so
    /// the parent can raise the watchOS keyboard imperatively. We
    /// use the `ComposerField` enum tag (rather than a plain Bool)
    /// because on watchOS Bool FocusStates can get reset by view
    /// identity changes during NavigationStack push transitions,
    /// whereas an enum tag survives those resets.
    @FocusState private var focusedField: ComposerField?
    /// Tracks whether the bottom sentinel is currently inside the
    /// visible viewport. When true the user is at the bottom of the
    /// conversation and the floating reply box is fully shown; when
    /// false the user has scrolled up to read older messages and the
    /// reply box auto-hides — matching the Apple Watch iMessage UX.
    @State private var isAtBottom: Bool = true
    /// Last id we scrolled to via `proxy.scrollTo`. Used to throttle
    /// redundant `onChange` work when only the streaming deltas move
    /// the bottom around.
    @State private var lastAutoScrolledID: UUID?
    /// Latched to true after the first focus burst completes, so
    /// the staggered retries only run once per view appearance.
    @State private var didAttemptAutoFocus = false

    /// Reserved height at the bottom of the scrollable area. Sized
    /// to roughly the composer's height so the last message can be
    /// scrolled fully into view above the floating composer. We
    /// collapse this to zero while the composer is hidden so the
    /// scrollable region doesn't trail off into empty space.


    private let composerReservedHeight: CGFloat = 52
    /// How far the composer translates down off-screen when hidden.
    /// Slightly larger than the reserved height so it clears the
    /// visible viewport completely.
    private let composerHiddenOffset: CGFloat = 70

    private var endpoint: EndpointConfig? {
        endpoints.endpoints.first(where: { $0.id == conversation.endpointID })
    }

    /// True when the composer should slide out of view. The composer
    /// is always visible when the user is typing (`focusedField ==
    /// .reply`) or when the engine is streaming (so they can hit
    /// stop). Otherwise, we hide it whenever the user has scrolled
    /// away from the bottom of the conversation.
    private var composerHidden: Bool {
        if focusedField == .reply { return false }
        if engine.isStreaming { return false }
        return !isAtBottom
    }

    var body: some View {
        // The composer is a floating overlay on top of the full-screen
        // messages ScrollView (ZStack, not safeAreaInset). safeAreaInset
        // mounts its child lazily on watchOS, after the navigation
        // transition, and the inner TextField is sometimes not yet in
        // the first-responder chain when its .onAppear focus trigger
        // fires, so watchOS silently refuses to pop the keyboard.
        // Putting the composer in a ZStack keeps the TextField in the
        // responder chain from the first layout pass, which is what
        // makes the auto-focus work.
        ZStack(alignment: .bottom) {
            messages
            composerOverlay
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
        .onAppear {
            chatLog.info("onAppear — kicking off focus burst")
            runFocusBurst()
        }
    }

    /// Drives the auto-focus on "New chat" / chat appear. We use
    /// `DispatchQueue.main.asyncAfter` (NOT `.task` / `Task.sleep`)
    /// because `.task` is cancelled by SwiftUI when a NavigationStack
    /// push causes the destination view's identity to be re-issued,
    /// and that happens during the New chat transition. `asyncAfter`
    /// is fire-and-forget and survives those resets.
    ///
    /// We also set focus *immediately* in addition to the staggered
    /// delays, because on watchOS the very first frame the TextField
    /// is in the responder chain is sometimes the only one where
    /// programmatic focus actually pops the keyboard.
    private func runFocusBurst() {
        guard !didAttemptAutoFocus else { return }
        didAttemptAutoFocus = true
        chatLog.info("focus burst: immediate set")
        focusedField = .reply
        let delays: [TimeInterval] = [0.1, 0.3, 0.6, 1.0, 1.5, 2.0, 3.0]
        for d in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [focusedField] in
                chatLog.info("focus burst: +\(d, format: .fixed(precision: 1))s")
                _ = focusedField
                self.focusedField = .reply
            }
        }
    }

    /// Scrollable list of messages. The last child of the LazyVStack
    /// is a 1-point `Color.clear` sentinel — when it is in the
    /// visible viewport, the user is at the bottom and the floating
    /// composer shows. A second transparent spacer at the very end
    /// reserves space for the composer so the last message can scroll
    /// fully above it; this spacer collapses to zero when the
    /// composer is hidden.
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
                    Color.clear
                        .frame(height: 1)
                        .id("chat-bottom-sentinel")
                        .onAppear {
                            isAtBottom = true
                        }
                        .onDisappear {
                            isAtBottom = false
                        }
                    Color.clear
                        .frame(height: composerHidden ? 0 : composerReservedHeight)
                        .animation(.easeInOut(duration: 0.22), value: composerHidden)
                }
                .padding(.horizontal, 4)
            }
            .onAppear {
                chatLog.info("messages.onAppear — scrollTo bottom")
                // Scroll to the bottom on entry so the user lands on
                // the newest message with the composer visible. We
                // do this from `.onAppear` so the scroll completes
                // before the focus triggers in `.task` fire — the
                // resulting layout pass is what makes the TextField
                // a real first-responder target.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo("chat-bottom-sentinel", anchor: .bottom)
                    isAtBottom = true
                }
            }
            .onChange(of: conversation.messages.count) { _, _ in
                guard let last = conversation.sortedMessages.last else { return }
                if last.id == lastAutoScrolledID { return }
                lastAutoScrolledID = last.id
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
                isAtBottom = true
            }
        }
    }

    /// Floating reply box, drawn on top of the messages and pinned to
    /// the bottom of the screen. Slides down out of view when the
    /// user scrolls up to read, and slides back up when they return
    /// to the bottom (or focus the field).
    private var composerOverlay: some View {
        ComposerView(
            text: $draft,
            isStreaming: engine.isStreaming,
            canSend: canSend,
            onSend: send,
            focusBinding: $focusedField
        )
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .offset(y: composerHidden ? composerHiddenOffset : 0)
        .opacity(composerHidden ? 0.0 : 1.0)
        .allowsHitTesting(!composerHidden)
        .animation(.easeInOut(duration: 0.22), value: composerHidden)
    }

    /// The live streaming buffer applies only to the most recent
    /// assistant message while the engine is producing deltas. After
    /// the stream finishes the buffer is reset to `""` in `send`'s
    /// `onComplete` handler, so this method naturally returns `nil`
    /// and the row falls back to the persisted `message.content`.
    private func streamingOverride(for message: Message) -> String? {
        guard engine.isStreaming, message.role == .assistant else { return nil }
        guard let lastAssistant = conversation.sortedMessages.last(where: { $0.role == .assistant }) else {
            return nil
        }
        guard lastAssistant.id == message.id else { return nil }
        return streamingContent
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        if engine.isStreaming {
            engine.cancel()
            return
        }
        guard canSend, let endpoint else { return }
        let userText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        focusedField = nil
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

        // Mirror the iOS pattern: accumulate into the `@State` buffer
        // for the visible row, and only flush the final value into the
        // SwiftData model once the stream settles. Mutating
        // `assistantMessage.content` from the streaming closure can
        // lag per-property observation, so doing it only at completion
        // is what actually makes the bubble update in real time.
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
            // Mirror to the paired iPhone so the phone's chat list stays
            // in sync with messages composed on the watch.
            SyncCoordinator.shared.publishConversation(ConversationSnapshot(conversation))
        }
    }
}

private struct WatchMessageRow: View {
    let message: Message
    /// Live streaming buffer that overrides `message.content` while the
    /// parent view is producing deltas. See `MessageBubble` in the iOS
    /// app for the full rationale.
    let streamingOverride: String?

    private var isUser: Bool { message.role == .user }

    private var displayContent: String {
        if let streamingOverride, !streamingOverride.isEmpty {
            return streamingOverride
        }
        return message.content
    }

    /// Markdown rendering for the watch. `AttributedString(markdown:)` is
    /// available on watchOS 8+. During streaming we still call this on
    /// every delta — watch messages are short enough that the re-parse
    /// cost is negligible. Falls back to plain text if the markdown is
    /// incomplete (e.g. unclosed `**` mid-stream).
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
