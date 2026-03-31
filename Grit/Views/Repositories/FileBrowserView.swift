import SwiftUI

// MARK: - File Browser (Finder-style directory listing)

struct FileBrowserView: View {
    let projectID: Int
    let ref: String
    let path: String            // current directory path, "" = root
    let displayName: String     // shown in nav title

    @StateObject private var viewModel = FileBrowserViewModel()
    @EnvironmentObject var navState: AppNavigationState

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.files.isEmpty {
                loadingView
            } else if viewModel.files.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Empty Directory",
                    systemImage: "folder",
                    description: Text("This directory contains no files.")
                )
            } else {
                fileList
            }
        }
        .task { await viewModel.loadDirectory(projectID: projectID, path: path, ref: ref) }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        // Register navigation destinations for this branch of the stack
        .navigationDestination(for: FileNavigation.self) { nav in
            if nav.file.isDirectory {
                FileBrowserView(
                    projectID: nav.projectID,
                    ref: nav.ref,
                    path: nav.file.path,
                    displayName: nav.file.name
                )
            } else {
                FileContentView(
                    projectID: nav.projectID,
                    filePath: nav.file.path,
                    fileName: nav.file.name,
                    ref: nav.ref
                )
            }
        }
    }

    // MARK: - File List

    private var fileList: some View {
        List {
            if let error = viewModel.error {
                Section {
                    ErrorBanner(message: error) { viewModel.error = nil }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Path breadcrumb header
            if !path.isEmpty {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.clear)
                .listSectionSeparator(.hidden)
            }

            Section {
                ForEach(viewModel.files) { file in
                    NavigationLink(value: FileNavigation(projectID: projectID, ref: ref, file: file)) {
                        FileRowView(file: file)
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.loadDirectory(projectID: projectID, path: path, ref: ref)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 12) {
                    ShimmerView().frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 5) {
                        ShimmerView().frame(height: 13).frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - File Row

struct FileRowView: View {
    let file: RepositoryFile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.systemImage)
                .font(.system(size: 16))
                .foregroundStyle(file.isDirectory ? .yellow : .secondary)
                .frame(width: 24)

            Text(file.name)
                .font(.system(size: 15, design: file.isDirectory ? .default : .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if file.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
