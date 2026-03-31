import SwiftUI

// MARK: - AI Assistant Sheet (reusable)

struct AIResponseSheet: View {
    let title: String
    let subtitle: String
    let response: String?
    let isLoading: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Subtitle
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Apple Intelligence is thinking…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else if let response {
                        GlassCard {
                            Text(response)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView {
                            Label("No Response", systemImage: "sparkles.slash")
                        } description: {
                            Text("Apple Intelligence could not generate a response.")
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Full AI Chat Assistant View

struct AIAssistantChatView: View {
    @StateObject private var service = AIAssistantService.shared
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var codeContext = ""
    @State private var showContextInput = false
    @FocusState private var inputFocused: Bool

    struct ChatMessage: Identifiable {
        let id = UUID()
        let role: Role
        let content: String
        let timestamp = Date()

        enum Role { case user, assistant }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !service.isAvailable {
                    unavailableBanner
                }

                if messages.isEmpty {
                    welcomeView
                } else {
                    messageList
                }

                inputBar
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showContextInput = true
                    } label: {
                        Label("Add Code", systemImage: "doc.badge.plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showContextInput) {
            codeContextSheet
        }
    }

    // MARK: - Subviews

    private var unavailableBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Apple Intelligence not available on this device")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(spacing: 6) {
                Text("Apple Intelligence")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("On-device AI for your GitLab repos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        inputText = suggestion
                        inputFocused = true
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    private let suggestions = [
        "Review this code for potential bugs",
        "Explain what this function does",
        "Suggest improvements for this merge request",
        "How can I optimize this code?"
    ]

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if service.isProcessing {
                        typingIndicator
                            .id("typing")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation {
                    if let lastMessage = messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    } else {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
            .onChange(of: service.isProcessing) { _, _ in
                withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
            }
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(0.6)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                        value: service.isProcessing
                    )
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                if !codeContext.isEmpty {
                    Button {
                        codeContext = ""
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 11))
                            Text("Code")
                                .font(.caption)
                            Image(systemName: "xmark")
                                .font(.system(size: 9))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.15), in: .capsule)
                        .foregroundStyle(Color.accentColor)
                    }
                }

                TextField("Ask about your code…", text: $inputText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .frame(maxWidth: .infinity)

                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(inputText.isEmpty || !service.isAvailable ? Color.secondary : Color.accentColor)
                }
                .disabled(inputText.isEmpty || !service.isAvailable || service.isProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var codeContextSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $codeContext)
                    .font(.system(size: 13, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Code Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showContextInput = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showContextInput = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func send() {
        guard !inputText.isEmpty else { return }
        let userMessage = inputText
        inputText = ""
        inputFocused = false

        messages.append(ChatMessage(role: .user, content: userMessage))

        Task {
            do {
                let prompt = codeContext.isEmpty
                    ? userMessage
                    : "\(userMessage)\n\nCode context:\n```\n\(codeContext)\n```"

                let response = try await service.analyzeCode(codeContext.isEmpty ? "" : codeContext, instruction: prompt)
                messages.append(ChatMessage(role: .assistant, content: response))
            } catch {
                messages.append(ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: AIAssistantChatView.ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            Text(message.content)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    isUser
                        ? AnyShapeStyle(Color.accentColor.opacity(0.2))
                        : AnyShapeStyle(Material.ultraThinMaterial),
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isUser ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.1),
                            lineWidth: 0.5
                        )
                )
                .fixedSize(horizontal: false, vertical: true)

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
