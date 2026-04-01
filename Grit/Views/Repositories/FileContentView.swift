import SwiftUI

struct FileContentView: View {
    let projectID: Int
    let filePath: String
    let fileName: String
    let ref: String

    @StateObject private var viewModel = FileContentViewModel()
    @EnvironmentObject var navState: AppNavigationState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ── File meta card ────────────────────────────────────
                if let info = viewModel.fileInfo {
                    GlassCard(padding: 12) {
                        HStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.fileName)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                Text(ByteCountFormatter.string(
                                    fromByteCount: Int64(info.size), countStyle: .file
                                ))
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

                // ── Content ───────────────────────────────────────────
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let content = viewModel.content {
                    CodeEditorView(content: content, fileName: fileName)
                        .padding(.horizontal)
                        // Give the editor enough vertical room to show without clipping
                        .frame(minHeight: 300)
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
            }
            .padding(.bottom, 40)
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(projectID: projectID, filePath: filePath, ref: ref)
            navState.enterFile(path: filePath, content: viewModel.content)
        }
        .onChange(of: viewModel.content) { _, newContent in
            if navState.currentFilePath == filePath {
                navState.setScreenContent(newContent)
            }
        }
        .onDisappear {
            navState.currentFilePath = nil
            navState.setScreenContent(nil)
        }
    }
}
