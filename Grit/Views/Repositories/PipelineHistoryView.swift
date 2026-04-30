import SwiftUI

// MARK: - View Model

@MainActor
private final class PipelineHistoryViewModel: ObservableObject {
    @Published var pipelines:      [Pipeline] = []
    @Published var availableRefs:  [String]   = []
    @Published var selectedRef:    String?
    @Published var isLoading       = false
    @Published var hasMore         = false
    @Published var error:          String?

    private var currentPage  = 1
    private var isPaginating = false
    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    // MARK: Initial setup

    /// Fetches one unfiltered page purely to discover which refs have pipelines,
    /// then immediately reloads filtered to the best default ref.
    func initialLoad(projectID: Int, defaultBranch: String?) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error = nil

        do {
            let discovery = try await api.fetchProjectPipelines(
                projectID: projectID,
                baseURL: auth.baseURL,
                token: token,
                ref: nil,
                page: 1
            )
            // Build ordered ref list: default branch first if present
            var seen = Set<String>()
            var refs = [String]()
            if let db = defaultBranch, discovery.contains(where: { $0.ref == db }) {
                seen.insert(db); refs.append(db)
            }
            for p in discovery {
                if let r = p.ref, !seen.contains(r) { seen.insert(r); refs.append(r) }
            }
            availableRefs = refs

            // Pick the best default: defaultBranch if it has pipelines, else first ref
            let best = refs.first
            selectedRef = best
        } catch {
            self.error = error.localizedDescription
            isLoading = false
            return
        }

        // Now load filtered — isLoading stays true through this
        await load(projectID: projectID, refresh: true, skipLoadingToggle: true)
    }

    // MARK: Paginated load

    func load(projectID: Int, refresh: Bool = false, skipLoadingToggle: Bool = false) async {
        guard let token = auth.accessToken else { return }

        if refresh {
            currentPage  = 1
            isPaginating = false
        } else {
            guard !isPaginating, hasMore else { return }
            isPaginating = true
        }

        if !skipLoadingToggle, (refresh || pipelines.isEmpty) { isLoading = true }
        error = nil
        defer {
            isLoading    = false
            isPaginating = false
        }

        let page = currentPage
        do {
            let fetched = try await api.fetchProjectPipelines(
                projectID: projectID,
                baseURL: auth.baseURL,
                token: token,
                ref: selectedRef,
                page: page
            )
            withAnimation(.easeOut(duration: 0.22)) {
                if refresh { pipelines = fetched } else { pipelines.append(contentsOf: fetched) }
            }
            hasMore     = fetched.count == 50
            currentPage = page + 1
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Branch switch

    func selectRef(_ ref: String, projectID: Int) {
        guard ref != selectedRef else { return }
        selectedRef = ref
        Task { await load(projectID: projectID, refresh: true) }
    }
}

// MARK: - Pipeline History View

struct PipelineHistoryView: View {
    let projectID:     Int
    let defaultBranch: String?

    @StateObject private var viewModel = PipelineHistoryViewModel()
    @State private var selectedPipeline: Pipeline?
    @EnvironmentObject var navState: AppNavigationState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 10) {
                if let error = viewModel.error, viewModel.pipelines.isEmpty {
                    ErrorBanner(message: error) { viewModel.error = nil }
                        .padding(.horizontal)
                } else if viewModel.isLoading {
                    loadingSkeleton
                        .padding(.horizontal)
                } else if viewModel.pipelines.isEmpty {
                    ContentUnavailableView(
                        "No Pipelines",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("No CI/CD pipelines have run for this repository.")
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(viewModel.pipelines) { pipeline in
                        Button { selectedPipeline = pipeline } label: {
                            PipelineHistoryRowView(pipeline: pipeline)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .transition(.opacity)
                    }

                    if viewModel.hasMore {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .padding(.vertical, 8)
                            .onAppear { Task { await viewModel.load(projectID: projectID) } }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle("Pipeline History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                branchPickerMenu
            }
        }
        .task {
            await viewModel.initialLoad(projectID: projectID, defaultBranch: defaultBranch)
        }
        .refreshable {
            await viewModel.load(projectID: projectID, refresh: true)
        }
        .sheet(item: $selectedPipeline) { pipeline in
            PipelineDetailView(pipeline: pipeline, projectID: projectID)
                .environmentObject(navState)
        }
    }

    // MARK: - Branch picker menu

    @ViewBuilder
    private var branchPickerMenu: some View {
        if viewModel.availableRefs.count > 1 {
            Menu {
                ForEach(viewModel.availableRefs, id: \.self) { ref in
                    Button {
                        viewModel.selectRef(ref, projectID: projectID)
                    } label: {
                        if ref == viewModel.selectedRef {
                            Label(ref, systemImage: "checkmark")
                        } else if ref == defaultBranch {
                            Label(ref, systemImage: "star")
                        } else {
                            Label(ref, systemImage: "arrow.triangle.branch")
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 12, weight: .medium))
                    Text(viewModel.selectedRef ?? "All")
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
        }
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 8) {
                    ShimmerView().frame(width: 76, height: 24).clipShape(Capsule())
                    Spacer(minLength: 8)
                    ShimmerView().frame(width: 80, height: 12)
                    ShimmerView().frame(width: 36, height: 12)
                    ShimmerView().frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .padding(12)
                .background(Color(.secondarySystemFill),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

// MARK: - Pipeline history row

private struct PipelineHistoryRowView: View {
    let pipeline: Pipeline

    var body: some View {
        HStack(spacing: 8) {
            PipelineStatusBadge(pipeline: pipeline)

            Spacer(minLength: 8)

            if let ref = pipeline.ref {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9, weight: .medium))
                    Text(ref)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }

            Text("#\(pipeline.id)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)

            if let date = pipeline.createdAt {
                Text(date.relativeFormatted)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemFill),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
