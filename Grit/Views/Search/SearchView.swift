import SwiftUI

/// Context-aware search sheet.
/// — No repo in context  → searches all of GitLab for projects
/// — Repo in context     → searches that repo's file blobs
struct SearchView: View {
    @EnvironmentObject var navState: AppNavigationState
    @StateObject private var viewModel = SearchViewModel()
    @Environment(\.dismiss) var dismiss

    @State private var query = ""
    @State private var isSearchPresented = false

    var isInsideRepo: Bool { navState.currentRepository != nil }

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    placeholderView
                } else if viewModel.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isInsideRepo {
                    repoResultsList
                } else {
                    globalResultsList
                }
            }
            .navigationTitle(isInsideRepo
                ? "Search \(navState.currentRepository!.name)"
                : "Search GitLab"
            )
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, isPresented: $isSearchPresented, prompt: searchPrompt)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, q in
                if isInsideRepo, let repo = navState.currentRepository {
                    viewModel.searchRepo(query: q, projectID: repo.id)
                } else {
                    viewModel.searchGlobal(query: q)
                }
            }
            .onAppear { isSearchPresented = true }
            .onDisappear { viewModel.reset() }
        }
        .navigationDestination(for: Repository.self) { repo in
            RepositoryDetailView(repository: repo)
        }
    }

    // MARK: - Subviews

    private var searchPrompt: String {
        if isInsideRepo, let repo = navState.currentRepository {
            return "Files, code in \(repo.name)…"
        }
        return "Projects, repositories…"
    }

    private var placeholderView: some View {
        ContentUnavailableView {
            Label(
                isInsideRepo ? "Search this repository" : "Search GitLab",
                systemImage: isInsideRepo ? "magnifyingglass.circle" : "globe"
            )
        } description: {
            Text(isInsideRepo
                ? "Find files and code in \(navState.currentRepository?.name ?? "this repo")"
                : "Find projects and repositories across GitLab"
            )
        }
    }

    private var globalResultsList: some View {
        List {
            if viewModel.globalResults.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            } else {
                Section("\(viewModel.globalResults.count) projects found") {
                    ForEach(viewModel.globalResults) { project in
                        // Convert SearchProject → lightweight Repository for navigation
                        HStack(spacing: 12) {
                            Image(systemName: project.visibility == "private" ? "lock.fill" : "folder.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(project.nameWithNamespace)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let desc = project.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").font(.system(size: 9))
                                Text("\(project.starCount)").font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var repoResultsList: some View {
        List {
            if viewModel.repoResults.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            } else {
                Section("\(viewModel.repoResults.count) matches") {
                    ForEach(viewModel.repoResults, id: \.displayID) { blob in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tint)
                                Text(blob.filename)
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .lineLimit(1)
                            }
                            Text(blob.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                            // Matched snippet
                            Text(blob.data.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .padding(8)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
