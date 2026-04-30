import SwiftUI

// MARK: - Supporting Models

struct ProjectLabel: Codable, Identifiable, Hashable {
    let id:        Int
    let name:      String
    let color:     String
    let textColor: String

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case textColor = "text_color"
    }

    /// SwiftUI Color parsed from the hex string returned by GitLab (e.g. "#d9534f").
    var swiftUIColor: Color { Color(hex: color) ?? .accentColor }
}

struct ProjectMemberInfo: Codable, Identifiable, Hashable {
    let id:          Int
    let name:        String
    let username:    String
    let avatarURL:   String?
    let accessLevel: Int

    enum CodingKeys: String, CodingKey {
        case id, name, username
        case avatarURL   = "avatar_url"
        case accessLevel = "access_level"
    }
}


// MARK: - View Model

@MainActor
final class CreateIssueViewModel: ObservableObject {

    // ── Form state ────────────────────────────────────────────────────────
    @Published var issueTitle        = ""
    @Published var issueDescription  = ""
    @Published var selectedProject:    Repository?          = nil
    @Published var selectedAssigneeIDs: Set<Int>            = []
    @Published var selectedLabelNames:  Set<String>         = []
    @Published var issueType: GitLabIssueType = .issue
    /// Hex color strings for labels the user created during this session.
    /// Keyed by label name; only present for custom (not pre-existing) labels.
    @Published var customLabelColors:  [String: String]     = [:]

    // ── Remote data ───────────────────────────────────────────────────────
    @Published var memberRepos:      [Repository]           = []
    @Published var searchedRepos:    [Repository]           = []
    @Published var availableLabels:  [ProjectLabel]         = []
    @Published var availableMembers: [ProjectMemberInfo]    = []

    // ── Loading / error ───────────────────────────────────────────────────
    @Published var isCreating:       Bool    = false
    @Published var isLoadingProject: Bool    = false
    @Published var isSearchingRepos: Bool    = false
    @Published var error:            String? = nil

    private let api  = GitLabAPIService.shared
    private var auth: AuthenticationService { .shared }

    // MARK: Repo browsing

    func loadMemberRepos() async {
        guard let token = auth.accessToken else { return }
        isSearchingRepos = true
        defer { isSearchingRepos = false }
        do {
            memberRepos = try await api.fetchUserRepositories(baseURL: auth.baseURL, token: token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func searchRepos(_ query: String) async {
        guard !query.isEmpty else { searchedRepos = []; return }
        guard let token = auth.accessToken else { return }
        isSearchingRepos = true
        defer { isSearchingRepos = false }
        do {
            searchedRepos = try await api.searchRepositories(query: query, baseURL: auth.baseURL, token: token)
        } catch { }
    }

    // MARK: Project selection → load labels + members

    func selectProject(_ repo: Repository) async {
        selectedProject     = repo
        selectedAssigneeIDs = []
        selectedLabelNames  = []
        customLabelColors   = [:]
        availableLabels     = []
        availableMembers    = []
        isLoadingProject    = true
        defer { isLoadingProject = false }
        guard let token = auth.accessToken else { return }
        async let labels  = try? api.fetchProjectLabels(
            projectID: repo.id, baseURL: auth.baseURL, token: token)
        async let members = try? api.fetchProjectMembers(
            projectID: repo.id, baseURL: auth.baseURL, token: token)
        availableLabels  = await labels  ?? []
        availableMembers = await members ?? []
    }

    // MARK: Creation

    var canCreate: Bool {
        selectedProject != nil &&
        !issueTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Creates the issue then auto-subscribes the current user for notifications.
    func createIssue() async -> GitLabIssue? {
        guard canCreate, let project = selectedProject,
              let token = auth.accessToken else { return nil }
        isCreating = true
        defer { isCreating = false }
        do {
            // Create any custom labels in the project first so they exist
            // before the issue references them.
            let existingNames = Set(availableLabels.map(\.name))
            let newLabelNames = selectedLabelNames.filter { !existingNames.contains($0) }
            for name in newLabelNames {
                let hex = customLabelColors[name] ?? "#428BCA"
                try? await api.createProjectLabel(
                    projectID: project.id,
                    name:      name,
                    color:     hex,
                    baseURL:   auth.baseURL,
                    token:     token
                )
            }

            let cleanTitle = issueTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanDesc  = issueDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let issue = try await api.createIssue(
                projectID:   project.id,
                title:       cleanTitle,
                description: cleanDesc.isEmpty ? nil : cleanDesc,
                assigneeIDs: Array(selectedAssigneeIDs),
                labels:      Array(selectedLabelNames),
                issueType:   issueType.rawValue,
                baseURL:     auth.baseURL,
                token:       token
            )
            // Auto-subscribe so the creator receives notifications for
            // new comments, state changes and edits by other users.
            try? await api.subscribeToIssue(
                projectID: project.id,
                issueIID:  issue.iid,
                baseURL:   auth.baseURL,
                token:     token
            )
            return issue
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }
}

// MARK: - Create Issue Sheet

struct CreateIssueView: View {
    @StateObject private var viewModel = CreateIssueViewModel()
    @ObservedObject private var settingsStore = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showProjectPicker  = false
    @State private var showAssigneePicker = false
    @State private var showLabelPicker    = false

    private var userColor: Color { settingsStore.accentColor ?? .accentColor }

    /// Called with the newly-created issue on success (optional).
    var onCreated: ((GitLabIssue) -> Void)? = nil

    var body: some View {
        NavigationStack {
            Form {
                // ── Project ───────────────────────────────────────────────
                Section {
                    if let project = viewModel.selectedProject {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(userColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.system(size: 15, weight: .medium))
                                Text(project.nameWithNamespace)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Change") { showProjectPicker = true }
                                .font(.system(size: 13))
                        }
                    } else {
                        Button {
                            showProjectPicker = true
                        } label: {
                            Label("Select Project…", systemImage: "folder")
                        }
                    }
                } header: {
                    Text("Project")
                }

                // ── Issue Type ────────────────────────────────────────────
                if viewModel.selectedProject != nil {
                    Section {
                        ForEach(GitLabIssueType.allCases) { type in
                            // Hide premium types when user is on Free plan
                            if !type.requiresPremium || AuthenticationService.shared.plan.isPremiumOrHigher {
                                Button {
                                    viewModel.issueType = type
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: type.icon)
                                            .foregroundStyle(userColor)
                                            .frame(width: 20)
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(type.displayName)
                                                    .font(.system(size: 15))
                                                    .foregroundStyle(.primary)
                                                if type.requiresPremium {
                                                    Text("PREMIUM")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(Color.purple.opacity(0.15), in: Capsule())
                                                        .foregroundStyle(.purple)
                                                }
                                            }
                                        }
                                        Spacer()
                                        if viewModel.issueType == type {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(userColor)
                                                .fontWeight(.semibold)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } header: {
                        Text("Issue Type")
                    }
                }

                // ── Details ───────────────────────────────────────────────
                if viewModel.selectedProject != nil {
                    Section {
                        TextField("Title", text: $viewModel.issueTitle)
                            .font(.system(size: 15))

                        ZStack(alignment: .topLeading) {
                            if viewModel.issueDescription.isEmpty {
                                Text("Description (optional)")
                                    .foregroundStyle(Color(uiColor: .placeholderText))
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $viewModel.issueDescription)
                                .frame(minHeight: 90)
                                .padding(.vertical, 4)
                                .scrollContentBackground(.hidden)
                        }
                    } header: {
                        Text("Details")
                    }

                    // ── Assignees ─────────────────────────────────────────
                    Section {
                        ForEach(
                            viewModel.availableMembers.filter {
                                viewModel.selectedAssigneeIDs.contains($0.id)
                            }
                        ) { member in
                            HStack(spacing: 10) {
                                AvatarView(urlString: member.avatarURL,
                                           name: member.name, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(member.name)
                                        .font(.system(size: 14))
                                    Text("@\(member.username)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    viewModel.selectedAssigneeIDs.remove(member.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if viewModel.isLoadingProject {
                            loadingRow("Loading members…")
                        } else {
                            Button {
                                showAssigneePicker = true
                            } label: {
                                Label(
                                    viewModel.selectedAssigneeIDs.isEmpty
                                        ? "Add Assignee" : "Add Another",
                                    systemImage: "person.badge.plus"
                                )
                            }
                            .disabled(viewModel.availableMembers.isEmpty &&
                                      !viewModel.isLoadingProject)
                        }
                    } header: {
                        Text("Assignees")
                    }

                    // ── Labels ────────────────────────────────────────────
                    Section {
                        // Iterate selectedLabelNames directly so custom labels
                        // (not present in availableLabels) also appear.
                        ForEach(Array(viewModel.selectedLabelNames).sorted(), id: \.self) { labelName in
                            let projectLabel = viewModel.availableLabels.first { $0.name == labelName }
                            let dotColor: Color = {
                                if let pl = projectLabel { return pl.swiftUIColor }
                                if let hex = viewModel.customLabelColors[labelName] {
                                    return Color(hex: hex) ?? .secondary.opacity(0.5)
                                }
                                return .secondary.opacity(0.5)
                            }()
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(dotColor)
                                    .frame(width: 10, height: 10)
                                Text(labelName)
                                    .font(.system(size: 14))
                                Spacer()
                                Button {
                                    viewModel.selectedLabelNames.remove(labelName)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if viewModel.isLoadingProject {
                            loadingRow("Loading labels…")
                        } else {
                            Button {
                                showLabelPicker = true
                            } label: {
                                Label(
                                    viewModel.selectedLabelNames.isEmpty
                                        ? "Add Label" : "Add Another",
                                    systemImage: "tag"
                                )
                            }
                        }
                    } header: {
                        Text("Labels")
                    }
                }
            }
            .tint(userColor)
            .navigationTitle("New Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isCreating {
                        ProgressView()
                    } else {
                        Button("Create") {
                            Task {
                                if let issue = await viewModel.createIssue() {
                                    onCreated?(issue)
                                    dismiss()
                                }
                            }
                        }
                        .disabled(!viewModel.canCreate)
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get:  { viewModel.error != nil },
                set:  { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.error = nil }
            } message: {
                Text(viewModel.error ?? "")
            }
        }
        // Sub-sheets — presented on the NavigationStack so they layer correctly.
        .sheet(isPresented: $showProjectPicker) {
            ProjectPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showAssigneePicker) {
            AssigneePickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showLabelPicker) {
            LabelPickerSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.loadMemberRepos()
        }
    }

    // MARK: Helpers

    private func loadingRow(_ label: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Project Picker

private struct ProjectPickerSheet: View {
    @ObservedObject var viewModel: CreateIssueViewModel
    @ObservedObject private var settingsStore = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>? = nil

    private var userColor: Color { settingsStore.accentColor ?? .accentColor }

    private var displayed: [Repository] {
        query.isEmpty ? viewModel.memberRepos : viewModel.searchedRepos
    }

    var body: some View {
        NavigationStack {
            List(displayed) { repo in
                Button {
                    Task {
                        await viewModel.selectProject(repo)
                        dismiss()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(repo.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(repo.nameWithNamespace)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if viewModel.isSearchingRepos {
                    ProgressView()
                } else if displayed.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if displayed.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Loading projects…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search projects…")
            .onChange(of: query) { _, q in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await viewModel.searchRepos(q)
                }
            }
            .navigationTitle("Select Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(userColor)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Assignee Picker

private struct AssigneePickerSheet: View {
    @ObservedObject var viewModel: CreateIssueViewModel
    @ObservedObject private var settingsStore = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var userColor: Color { settingsStore.accentColor ?? .accentColor }

    private var filtered: [ProjectMemberInfo] {
        guard !query.isEmpty else { return viewModel.availableMembers }
        let q = query.lowercased()
        return viewModel.availableMembers.filter {
            $0.name.lowercased().contains(q) || $0.username.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { member in
                Button {
                    if viewModel.selectedAssigneeIDs.contains(member.id) {
                        viewModel.selectedAssigneeIDs.remove(member.id)
                    } else {
                        viewModel.selectedAssigneeIDs.insert(member.id)
                    }
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(urlString: member.avatarURL,
                                   name: member.name, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                            Text("@\(member.username)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if viewModel.selectedAssigneeIDs.contains(member.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .overlay {
                if filtered.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("No Members", systemImage: "person.slash")
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search members…")
            .navigationTitle("Add Assignee")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(userColor)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Label Picker

private struct LabelPickerSheet: View {
    @ObservedObject var viewModel: CreateIssueViewModel
    @ObservedObject private var settingsStore = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query       = ""
    @State private var customColor = Color.blue   // color chosen for the next custom label

    private var userColor: Color { settingsStore.accentColor ?? .accentColor }

    private var filtered: [ProjectLabel] {
        guard !query.isEmpty else { return viewModel.availableLabels }
        let q = query.lowercased()
        return viewModel.availableLabels.filter { $0.name.lowercased().contains(q) }
    }

    /// True when the typed text is non-empty and doesn't exactly match any
    /// existing label — enables the inline "Add" row for custom labels.
    private var canAddCustom: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Don't offer "Add" if already selected or if it matches an existing project label
        // (the existing label row will show a checkmark instead).
        if viewModel.selectedLabelNames.contains(trimmed) { return false }
        return !viewModel.availableLabels.contains {
            $0.name.lowercased() == trimmed.lowercased()
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // ── Custom label entry (shown when typed text is novel) ────
                if canAddCustom {
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    HStack(spacing: 12) {
                        // Color picker — tapping opens the system color panel
                        ColorPicker("Label color", selection: $customColor, supportsOpacity: false)
                            .labelsHidden()

                        Text(trimmed)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        Button {
                            viewModel.selectedLabelNames.insert(trimmed)
                            viewModel.customLabelColors[trimmed] = customColor.toHex()
                            query = ""
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(userColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }

                // ── Existing project labels ────────────────────────────────
                ForEach(filtered) { label in
                    Button {
                        if viewModel.selectedLabelNames.contains(label.name) {
                            viewModel.selectedLabelNames.remove(label.name)
                        } else {
                            viewModel.selectedLabelNames.insert(label.name)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(label.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(label.name)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if viewModel.selectedLabelNames.contains(label.name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .overlay {
                if filtered.isEmpty && !canAddCustom {
                    if query.isEmpty {
                        ContentUnavailableView(
                            "Type a label to create a custom label",
                            systemImage: "tag.slash"
                        )
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search or type a new label…")
            .navigationTitle("Add Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(userColor)
        .presentationDetents([.medium, .large])
    }
}
