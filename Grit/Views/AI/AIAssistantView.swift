import SwiftUI

// MARK: - AI Assistant Chat View
// Full conversational AI panel — context-aware via AppNavigationState.
// Uses Apple Intelligence (FoundationModels) on-device.

struct AIAssistantChatView: View {
    @EnvironmentObject var navState: AppNavigationState
    @ObservedObject private var service = AIAssistantService.shared
    @Environment(\.dismiss) var dismiss

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false
    @FocusState private var inputFocused: Bool

    struct ChatMessage: Identifiable {
        let id = UUID()
        let isUser: Bool
        let content: String
    }

    private var contextGreeting: String {
        if let path = navState.currentFilePath {
            return "I can see you're viewing **\(path)**. Ask me anything about this file."
        }
        if let repo = navState.currentRepository {
            return "I can see you're in **\(repo.name)**. Ask me about the code, MRs, or anything else."
        }
        return "Ask me anything about your GitLab projects, code, or merge requests."
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Context banner
                if let summary = navState.contextSummary {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                            .font(.system(size: 12))
                            .foregroundStyle(.accentColor)
                        Text("Context: \(summary)")
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                }

                // Message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Greeting bubble always first
                            AssistantBubble(text: contextGreeting, isThinking: false)
                                .padding(.top, 12)

                            ForEach(messages) { msg in
                                if msg.isUser {
                                    UserBubble(text: msg.content)
                                } else {
                                    AssistantBubble(text: msg.content, isThinking: false)
                                }
                            }

                            if isThinking {
                                AssistantBubble(text: "", isThinking: true)
                                    .id("thinking")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: isThinking) { _, thinking in
                        if thinking {
                            withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                        }
                    }
                }

                Divider().opacity(0.4)

                // Input bar
                HStack(spacing: 10) {
                    TextField("Ask anything…", text: $inputText, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(10)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                        .focused($inputFocused)

                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(inputText.isEmpty ? .secondary : .accentColor)
                    }
                    .disabled(inputText.isEmpty || isThinking)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !messages.isEmpty {
                        Button {
                            withAnimation { messages.removeAll() }
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Send

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        messages.append(ChatMessage(isUser: true, content: text))
        isThinking = true
        defer { isThinking = false }

        do {
            let response = try await service.analyzeCode("", instruction: buildInstruction(for: text))
            messages.append(ChatMessage(isUser: false, content: response))
        } catch {
            messages.append(ChatMessage(isUser: false, content: "⚠️ \(error.localizedDescription)"))
        }
    }

    private func buildInstruction(for question: String) -> String {
        var parts: [String] = []
        if let path = navState.currentFilePath {
            parts.append("The user is viewing file: \(path)")
        }
        if let repo = navState.currentRepository {
            parts.append("Repository: \(repo.nameWithNamespace) (\(repo.visibility))")
            if let branch = navState.currentBranch { parts.append("Branch: \(branch)") }
        }
        parts.append("Question: \(question)")
        return parts.joined(separator: "\n")
    }
}

// MARK: - Chat Bubbles

struct UserBubble: View {
    let text: String
    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

struct AssistantBubble: View {
    let text: String
    let isThinking: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle().fill(.ultraThinMaterial).frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(.accentColor)
            }
            Group {
                if isThinking {
                    ThinkingDotsView()
                } else {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
            Spacer(minLength: 60)
        }
    }
}

struct ThinkingDotsView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 7, height: 7)
                    .scaleEffect(animating ? 1 : 0.5)
                    .opacity(animating ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(i) * 0.16),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}

// MARK: - One-shot AI response sheet (used from MR / Commit detail)

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
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView().scaleEffect(1.2)
                            Text("Apple Intelligence is thinking…")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 40)
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
