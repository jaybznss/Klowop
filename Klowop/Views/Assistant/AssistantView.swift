import SwiftUI
import SwiftData

/// Chat with your secretary. Claude can schedule events, manage todos,
/// log meals, and answer questions about your finances via tools.
struct AssistantView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessage.date) private var messages: [ChatMessage]
    @State private var assistant = ClaudeAssistantService.shared
    @State private var input = ""
    @State private var errorMessage: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
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
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 12)
                    }
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
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { clearChat() } label: { Image(systemName: "trash") }
                        .disabled(messages.isEmpty)
                }
            }
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
            Text(LocalizedStringKey(assistant.streamingText))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.background.secondary, in: .rect(cornerRadius: 18, style: .continuous))
            Spacer(minLength: 48)
        }
        .padding(.horizontal)
        .transition(.opacity)
    }

    private func bubble(for message: ChatMessage) -> some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 48) }
            Text(LocalizedStringKey(message.text))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.role == "user" ? AnyShapeStyle(Theme.assistant) : AnyShapeStyle(.background.secondary),
                    in: .rect(cornerRadius: 18, style: .continuous)
                )
                .foregroundStyle(message.role == "user" ? .white : .primary)
            if message.role != "user" { Spacer(minLength: 48) }
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
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(Theme.assistant)
            .disabled(!canSend)
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
        context.insert(ChatMessage(role: "user", text: text))
        try? context.save()

        Task { @MainActor in
            do {
                let reply = try await assistant.send(text, context: context)
                context.insert(ChatMessage(role: "assistant", text: reply))
                try? context.save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clearChat() {
        for message in messages { context.delete(message) }
        try? context.save()
        assistant.resetConversation()
    }
}
