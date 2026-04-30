import SwiftUI

// MARK: - AI Slide Drawer
// A Discord-style handle anchored to the right edge that slides open an AI chat panel.
// • Drag the handle LEFT / RIGHT to open or close the panel.
// • Drag the handle UP / DOWN to reposition it vertically (position is persisted).

struct AISlideDrawer: View {
    @EnvironmentObject var navState: AppNavigationState
    @ObservedObject private var aiService = AIAssistantService.shared

    /// Persisted fraction of screen height for the handle's vertical centre (0 = top, 1 = bottom).
    @AppStorage("aiDrawerYFraction") private var yFraction: Double = 0.35

    // ── Drag state ────────────────────────────────────────────────────────────
    @State private var openProgress: CGFloat = 0        // 0 = closed, 1 = fully open
    @State private var dragStartProgress: CGFloat = 0
    @State private var tempYDelta: CGFloat = 0
    @State private var dragAxis: DragAxis? = nil
    /// Flipped true/false each time the panel opens so AIDrawerPanel can fire a .task(id:).
    @State private var isOpen = false

    private enum DragAxis { case horizontal, vertical }

    // ── Layout constants ──────────────────────────────────────────────────────
    private let panelFraction: CGFloat = 0.92   // panel width as fraction of screen width
    private let rightMargin: CGFloat = 12       // gap between panel right edge and screen edge

    /// Whether the panel is in tall (80 %) mode. Tapping the chat area expands;
    /// focusing the input field or closing the panel collapses it back to 50 %.
    @State private var isPanelExpanded = false
    private let handleW: CGFloat = 22
    private let handleH: CGFloat = 64

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let panelW = geo.size.width * panelFraction
            let panelH = geo.size.height * (isPanelExpanded ? 0.80 : 0.50)
            let slideUnit = panelW + rightMargin  // total horizontal travel distance

            // Keep the handle centre within the visible, tappable area.
            let topLimit    = geo.safeAreaInsets.top + handleH / 2 + 8
            let bottomLimit = geo.size.height - geo.safeAreaInsets.bottom - 90 - handleH / 2
            let baseY       = geo.size.height * CGFloat(yFraction)
            let handleY     = min(max(baseY + tempYDelta, topLimit), bottomLimit)

            // The floating panel is vertically centred on the handle, clamped so it stays on screen.
            let panelCenterY = min(
                max(handleY, geo.safeAreaInsets.top + panelH / 2 + 8),
                geo.size.height - geo.safeAreaInsets.bottom - 90 - panelH / 2
            )
            let panelTopPadding = max(0, panelCenterY - panelH / 2)

            // Handle's horizontal centre: starts at the right edge, slides left as panel opens.
            let handleX = geo.size.width - handleW / 2 - slideUnit * openProgress

            ZStack {
                // ── Dim overlay (tapping closes the panel) ────────────────────
                if openProgress > 0 {
                    Color.black
                        .opacity(0.25 * openProgress)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                                openProgress = 0
                            }
                        }
                }

                // ── Floating panel (slides in from the right) ─────────────────
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        Spacer().frame(height: panelTopPadding)
                        AIDrawerPanel(isExpanded: $isPanelExpanded, isOpen: isOpen)
                            .environmentObject(navState)
                            .frame(width: panelW, height: panelH)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .regularGlassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .shadow(color: .black.opacity(0.20), radius: 32, x: -4, y: 8)
                            .shadow(color: .black.opacity(0.08), radius: 6, x: -1, y: 2)
                            .padding(.trailing, rightMargin)
                        Spacer()
                    }
                }
                .offset(x: slideUnit * (1 - openProgress))

                // ── Handle tab ────────────────────────────────────────────────
                handleTab
                    .position(x: handleX, y: handleY)
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                if dragAxis == nil {
                                    dragStartProgress = openProgress
                                    let dx = abs(value.translation.width)
                                    let dy = abs(value.translation.height)
                                    dragAxis = dx > dy ? .horizontal : .vertical
                                }
                                switch dragAxis {
                                case .horizontal:
                                    // Dragging left opens the panel (negative width = left).
                                    let delta = -value.translation.width / slideUnit
                                    openProgress = max(0, min(1, dragStartProgress + delta))
                                case .vertical:
                                    tempYDelta = value.translation.height
                                case nil:
                                    break
                                }
                            }
                            .onEnded { value in
                                switch dragAxis {
                                case .horizontal:
                                    let vel = value.velocity.width
                                    let shouldOpen: Bool
                                    if vel < -400 {
                                        shouldOpen = true   // fast leftward flick
                                    } else if vel > 400 {
                                        shouldOpen = false  // fast rightward flick
                                    } else {
                                        shouldOpen = openProgress > 0.5
                                    }
                                    withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                                        openProgress = shouldOpen ? 1 : 0
                                    }
                                    if shouldOpen { isOpen.toggle() }
                                case .vertical:
                                    // Commit the new Y fraction.
                                    let newY = min(max(baseY + tempYDelta, topLimit), bottomLimit)
                                    yFraction = Double(newY / geo.size.height)
                                    withAnimation(.spring(duration: 0.25)) { tempYDelta = 0 }
                                case nil:
                                    break
                                }
                                dragAxis = nil
                            }
                    )
            }
        }
        .ignoresSafeArea()
        .onChange(of: openProgress) { _, new in
            if new == 0 {
                isPanelExpanded = false
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil, from: nil, for: nil
                )
            }
        }
        .onChange(of: aiService.isUserEnabled) { _, enabled in
            if !enabled {
                withAnimation(.spring(duration: 0.35)) { openProgress = 0 }
            }
        }
    }

    // MARK: - Handle Tab

    private var handleTab: some View {
        ZStack {
            RoundedRectangle(cornerRadius: handleW / 2, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: handleW / 2, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(
                    color: Color.accentColor.opacity(openProgress > 0 ? 0.30 : 0.15),
                    radius: 10, y: 2
                )

            VStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentColor, .purple],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Capsule()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 3, height: 16)
            }
        }
        .frame(width: handleW, height: handleH)
    }
}

// MARK: - AI Drawer Panel

struct AIDrawerPanel: View {
    @Binding var isExpanded: Bool
    /// Toggled each time the drawer finishes opening — used to auto-focus the input.
    var isOpen: Bool

    @EnvironmentObject var navState: AppNavigationState
    @ObservedObject private var service = AIAssistantService.shared
    @ObservedObject private var settingsStore = SettingsStore.shared

    @State private var messages: [AIFloatingPanel.ChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false
    @FocusState private var inputFocused: Bool

    /// Resolved user colour: custom pick if set, otherwise system accent.
    private var userColor: Color { settingsStore.accentColor ?? .accentColor }

    var body: some View {
        VStack(spacing: 0) {
            panelHeader

            if let summary = navState.contextSummary {
                contextBanner(summary)
            }

            Divider().opacity(0.3)

            messageList
                .frame(maxHeight: .infinity)

            Divider().opacity(0.3)

            inputBar
        }
        .background(.clear)
        .onChange(of: inputFocused) { _, focused in
            if focused {
                withAnimation(.spring(duration: 0.35, bounce: 0.1)) { isExpanded = false }
            }
        }
        // Each time the drawer opens (isOpen toggles), wait for the spring animation
        // to settle then pull focus into the input field.
        // .onChange fires only on actual changes — never on initial render — so the
        // keyboard is not summoned when the app first launches.
        .onChange(of: isOpen) { _, _ in
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                inputFocused = true
            }
        }
    }

    // MARK: Subviews

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Text("AI Assistant")
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            if !messages.isEmpty {
                Button {
                    withAnimation { messages.removeAll() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(.clear)
                        .clipShape(Circle())
                        .regularGlassEffect(in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
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
            if navState.currentScreenContent != nil || navState.hasRepositoryAIContext {
                Image(systemName: navState.currentScreenContent != nil ? "doc.text.fill" : "book.fill")
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
                if thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { isExpanded = true }
                    }
            )
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
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(userColor.opacity(0.55), lineWidth: 1)
                )
                .focused($inputFocused)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(inputText.isEmpty ? Color.secondary : userColor)
            }
            .disabled(inputText.isEmpty || isThinking)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Helpers

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

    private func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        inputFocused = false
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
        navState.buildAIInstruction(for: question)
    }
}
