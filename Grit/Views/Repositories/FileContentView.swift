import SwiftUI

struct FileContentView: View {
    let projectID: Int
    let filePath:  String
    let fileName:  String
    let ref:       String

    @StateObject private var viewModel = FileContentViewModel()
    @EnvironmentObject var navState: AppNavigationState

    /// Whether the current file is a markdown document.
    private var isMarkdown: Bool {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        return ["md", "markdown", "mdown", "mkd", "mdx"].contains(ext)
    }

    /// Base URL for resolving relative image references in the Markdown content.
    /// Uses `webURL` which is the URL-safe project path (e.g. https://gitlab.com/group/project).
    private var imageBaseURL: String? {
        guard let repo = navState.currentRepository else { return nil }
        let webURL = repo.webURL.hasSuffix("/")
            ? String(repo.webURL.dropLast())
            : repo.webURL
        let dir = (filePath as NSString).deletingLastPathComponent
        let dirPath = dir.isEmpty ? "" : dir + "/"
        return "\(webURL)/-/raw/\(ref)/\(dirPath)"
    }

    /// Tracks whether the reader view is active for this file. Initialised
    /// from the user's default preference at the time the view is created.
    @State private var useReaderView: Bool

    init(projectID: Int, filePath: String, fileName: String, ref: String) {
        self.projectID = projectID
        self.filePath  = filePath
        self.fileName  = fileName
        self.ref       = ref

        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        let isMD = ["md", "markdown", "mdown", "mkd", "mdx"].contains(ext)
        _useReaderView = State(
            initialValue: isMD && SettingsStore.shared.markdownDefaultView == .reader
        )
    }

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
                    if isMarkdown && useReaderView {
                        MarkdownReaderView(source: content, imageBaseURL: imageBaseURL)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    } else {
                        CodeEditorView(content: content, fileName: fileName)
                            .padding(.horizontal)
                            .frame(minHeight: 300)
                            .transition(.opacity)
                    }
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
        .toolbar {
            if isMarkdown {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            useReaderView.toggle()
                        }
                    } label: {
                        Image(systemName: useReaderView ? "doc.plaintext" : "doc.richtext")
                    }
                    .disabled(viewModel.content == nil)
                }
            }
        }
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
