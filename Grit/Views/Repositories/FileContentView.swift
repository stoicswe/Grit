import SwiftUI

struct FileContentView: View {
    let projectID: Int
    let filePath: String
    let fileName: String
    let ref: String

    @StateObject private var viewModel = FileContentViewModel()
    @EnvironmentObject var navState: AppNavigationState
    @State private var showAISheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // File meta card
                if let info = viewModel.fileInfo {
                    GlassCard(padding: 12) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.fileName)
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                Text(ByteCountFormatter.string(fromByteCount: Int64(info.size), countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(info.lastCommitId.prefix(8)))
                                .font(.system(size: 11, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }

                // Content
                if viewModel.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if let content = viewModel.content {
                    codeView(content)
                } else if let error = viewModel.error {
                    ErrorBanner(message: error) { viewModel.error = nil }
                        .padding(.horizontal)
                } else {
                    ContentUnavailableView(
                        "Cannot Preview",
                        systemImage: "eye.slash",
                        description: Text("This file type cannot be displayed as text.")
                    )
                }

                // AI explanation card
                if let explanation = viewModel.aiExplanation {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.accentColor)
                                Text("Apple Intelligence")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(explanation)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 30)
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if AIAssistantService.shared.isAvailable {
                    Button {
                        Task { await viewModel.explainWithAI() }
                    } label: {
                        if viewModel.isAILoading {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                        }
                    }
                    .disabled(viewModel.isAILoading)
                }
            }
        }
        .task {
            await viewModel.load(projectID: projectID, filePath: filePath, ref: ref)
            navState.enterFile(path: filePath)
        }
        .onDisappear {
            navState.currentFilePath = nil
        }
    }

    // MARK: - Code view

    private func codeView(_ content: String) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Text(content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }
}
