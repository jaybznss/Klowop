import SwiftUI
import SwiftData

/// Chat with your secretary. Claude can schedule events, manage todos,
/// log meals, and answer questions about your finances via tools.
struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessage.date) private var messages: [ChatMessage]
    @State private var assistant = ClaudeAssistantService.shared
    @State private var backend = BackendService.shared
    @State private var input = ""
    @State private var errorMessage: String?
    @State private var lastFailedText: String?
    @State private var confirmingClear = false
    @State private var sendTask: Task<Void, Never>?
    @FocusState private var inputFocused: Bool

    /// Markdown without LocalizedStringKey's format-specifier pitfalls
    /// (`%`, `%@` in a message would get reinterpreted).
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    var body: some View {
        NavigationStack {
            Group {
                if backend.isSignedIn {
                    chat
                } else {
                    signInGate
                }
            }
            .background(AuroraBackground(colors: [.indigo, Theme.assistant, .blue]))
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                if backend.isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { confirmingClear = true } label: { Image(systemName: "trash") }
                            .disabled(messages.isEmpty)
                            .accessibilityLabel("Clear conversation")
                    }
                }
            }
            // One tap deleting the whole conversation is data loss — confirm it.
            .confirmationDialog("Clear this conversation?", isPresented: $confirmingClear,
                                titleVisibility: .visible) {
                Button("Clear Conversation", role: .destructive) { clearChat() }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private var signInGate: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Theme.assistantGradient)
            Text("Meet your secretary")
                .font(.title2.weight(.bold))
            Text("Sign in to schedule events, manage lists, log meals, and ask about your money — just by talking.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            AppleSignInButton()
                .frame(maxWidth: 320)
                .padding(.horizontal, 36)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if messages.isEmpty { welcome }
                            ForEach(messages) { message in
                                bubble(for: message).id(message.persistentModelID)
                            }
                            if assistant.isThinking {
                                if assistant.streamingText.isEmpty {
                                    HStack {
                                        ProgressView()
                                        Text("Working on it…")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    .transition(.opacity)
                                } else {
                                    streamingBubble.id("streaming")
                                }
                            }
                            if let errorMessage {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.orange)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(errorMessage)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if lastFailedText != nil {
                                            Button("Try again") { retry() }
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Theme.assistant)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) {
                        if let last = messages.last {
                            withAnimation { proxy.scrollTo(last.persistentModelID, anchor: .bottom) }
                        }
                    }
                    .onChange(of: assistant.streamingText) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
                inputBar
            }
            .animation(.snappy, value: messages.count)
            .animation(.smooth, value: assistant.isThinking)
            .sensoryFeedback(.success, trigger: messages.count) { old, new in
                new > old && messages.last?.role == "assistant"
            }
    }

    private let suggestions = [
        "What's on my schedule this week?",
        "I just had a coffee and a croissant",
        "How are my budgets doing?",
        "Add call mom to my to-dos",
    ]

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(colors: [.indigo, Theme.assistant],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("I'm your secretary.")
                .font(.headline)
            Text("I can schedule things, keep your lists, log your meals, and answer money questions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        input = suggestion
                        send()
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(.background.secondary, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(.top, 48)
    }

    private var streamingBubble: some View {
        HStack {
            Text(markdown(assistant.streamingText))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 48)
        }
        .padding(.horizontal)
        .transition(.opacity)
    }

    private func bubble(for message: ChatMessage) -> some View {
        let isUser = message.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 48) }
            Text(markdown(message.text))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser
                        ? AnyShapeStyle(Theme.assistantGradient)
                        : AnyShapeStyle(.background.secondary),
                    in: .rect(cornerRadius: 20, style: .continuous)
                )
                .foregroundStyle(isUser ? .white : .primary)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = message.text
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                }
                .accessibilityLabel("\(isUser ? "You" : "Assistant"): \(message.text)")
            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal)
        .transition(.push(from: .bottom).combined(with: .opacity))
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message your assistant…", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)
                .focused($inputFocused)
                .onSubmit(send)
            if assistant.isThinking {
                // A way out of a long generation.
                Button {
                    sendTask?.cancel()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.secondary)
                .accessibilityLabel("Stop generating")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(Theme.assistant)
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespaces).isEmpty && !assistant.isThinking
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !assistant.isThinking else { return }
        input = ""
        errorMessage = nil
        lastFailedText = nil
        context.insert(ChatMessage(role: "user", text: text))
        try? context.save()
        dispatch(text)
    }

    /// Resend the last failed message without retyping it.
    private func retry() {
        guard let text = lastFailedText, !assistant.isThinking else { return }
        errorMessage = nil
        lastFailedText = nil
        dispatch(text)
    }

    private func dispatch(_ text: String) {
        sendTask = Task { @MainActor in
            do {
                let reply = try await assistant.send(text, context: context)
                context.insert(ChatMessage(role: "assistant", text: reply))
                try? context.save()
            } catch is CancellationError {
                // User tapped stop — nothing to surface.
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Same, surfaced through URLSession.
            } catch {
                errorMessage = error.localizedDescription
                lastFailedText = text
            }
        }
    }

    private func clearChat() {
        for message in messages { context.delete(message) }
        try? context.save()
        assistant.resetConversation()
    }
}
