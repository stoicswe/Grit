import SwiftUI

// MARK: - AI Floating Panel
// A draggable, hovering overlay panel that sits above the current view.
// Does NOT use .sheet — it lives in the main ZStack so the user can see
// the app content behind it.

struct AIFloatingPanel: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var navState: AppNavigationState
    @ObservedObject private var service = AIAssistantService.shared

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false
    @FocusState private var inputFocused: Bool

    /// Drag offset — negative = dragged upward (taller panel)
    @State private var dragOffset: CGFloat = 0
    @GestureState private var isDragging = false

    // Collapsed = ~42 % of screen; expanded = ~72 %
    private let collapsedFraction: CGFloat = 0.42
    private let expandedFraction: CGFloat  = 0.74

    struct ChatMessage: Identifiable {
        let id = UUID()
        let isUser: Bool
        let content: String
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let baseHeight = geo.size.height * collapsedFraction
            let panelHeight = max(
                geo.size.height * collapsedFraction,
                min(geo.size.height * expandedFraction, baseHeight - dragOffset)
            )
            // Sit just above the AI button (button bottom=80, height=52, + 8pt gap)
            let bottomInset: CGFloat = 148

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    // ── Drag Handle ──────────────────────────────────
                    dragHandle

                    // ── Context Banner ───────────────────────────────
                    if let summary = navState.contextSummary {
                        contextBanner(summary)
                    }

                    // ── Message List ─────────────────────────────────
                    messageList
                        .frame(maxHeight: .infinity)

                    Divider().opacity(0.35)

                    // ── Input Bar ────────────────────────────────────
                    inputBar
                }
                .frame(height: panelHeight)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.25), radius: 30, y: -4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.height
                        }
                        .onEnded { value in
                            // Flick down to dismiss
                            if value.translation.height > 120 {
                                withAnimation(.spring(duration: 0.35)) { isPresented = false }
                            } else {
                                withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                            }
                        }
                )
                .padding(.bottom, bottomInset)
            }
        }
        .ignoresSafeArea(.keyboard)
    }

    // MARK: - Subviews

    private var dragHandle: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("AI Assistant")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if !messages.isEmpty {
                    Button {
                        withAnimation { messages.removeAll() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func contextBanner(_ summary: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(summary)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Spacer()
            if navState.currentScreenContent != nil {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
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
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .onChange(of: isThinking) { _, thinking in
                if thinking {
                    withAnimation { proxy.scrollTo("thinking", anchor: .bottom) }
                }
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask anything…", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
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
                    .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
            }
            .disabled(inputText.isEmpty || isThinking)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Greeting

    private var contextGreeting: String {
        if let path = navState.currentFilePath {
            let fileName = path.split(separator: "/").last.map(String.init) ?? path
            return "I can see you're viewing **\(fileName)**. Ask me anything about this file."
        }
        if let repo = navState.currentRepository {
            return "I can see you're in **\(repo.name)**\(navState.currentBranch.map { " on `\($0)`" } ?? ""). What would you like to know?"
        }
        return "Ask me anything about your GitLab projects, code, or merge requests."
    }

    // MARK: - Send

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        inputFocused = false
        messages.append(ChatMessage(isUser: true, content: text))
        isThinking = true
        defer { isThinking = false }

        do {
            let instruction = buildInstruction(for: text)
            let response = try await service.analyzeCode("", instruction: instruction)
            messages.append(ChatMessage(isUser: false, content: response))
        } catch {
            messages.append(ChatMessage(isUser: false, content: "⚠️ \(error.localizedDescription)"))
        }
    }

    private func buildInstruction(for question: String) -> String {
        var parts: [String] = []

        // Navigation context
        if let repo = navState.currentRepository {
            parts.append("Repository: \(repo.nameWithNamespace) (\(repo.visibility))")
            if let branch = navState.currentBranch {
                parts.append("Branch: \(branch)")
            }
        }
        if let path = navState.currentFilePath {
            parts.append("File path: \(path)")
        }

        // Actual screen content — the most valuable context
        if let content = navState.currentScreenContent, !content.isEmpty {
            // Limit to first 3000 chars to stay within token budget
            let truncated = content.count > 3000
                ? String(content.prefix(3000)) + "\n…[truncated]"
                : content
            parts.append("Current file contents:\n```\n\(truncated)\n```")
        }

        parts.append("User question: \(question)")
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - AI Assistant Chat View (legacy full-screen version)
// Kept for use from CommitDetailView / MergeRequestDetailView one-shot responses.

struct AIAssistantChatView: View {
    @EnvironmentObject var navState: AppNavigationState
    @ObservedObject private var service = AIAssistantService.shared
    @Environment(\.dismiss) var dismiss

    @State private var messages: [AIFloatingPanel.ChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false
    @FocusState private var inputFocused: Bool

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
                if let summary = navState.contextSummary {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
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

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
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
                            .foregroundStyle(inputText.isEmpty ? Color.secondary : Color.accentColor)
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

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        messages.append(AIFloatingPanel.ChatMessage(isUser: true, content: text))
        isThinking = true
        defer { isThinking = false }

        do {
            let response = try await service.analyzeCode("", instruction: buildInstruction(for: text))
            messages.append(AIFloatingPanel.ChatMessage(isUser: false, content: response))
        } catch {
            messages.append(AIFloatingPanel.ChatMessage(isUser: false, content: "⚠️ \(error.localizedDescription)"))
        }
    }

    private func buildInstruction(for question: String) -> String {
        var parts: [String] = []
        if let path = navState.currentFilePath { parts.append("File: \(path)") }
        if let repo = navState.currentRepository {
            parts.append("Repository: \(repo.nameWithNamespace) (\(repo.visibility))")
            if let branch = navState.currentBranch { parts.append("Branch: \(branch)") }
        }
        if let content = navState.currentScreenContent, !content.isEmpty {
            let truncated = content.count > 3000
                ? String(content.prefix(3000)) + "\n…[truncated]"
                : content
            parts.append("File contents:\n```\n\(truncated)\n```")
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
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
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
                    .fill(Color.secondary)
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
