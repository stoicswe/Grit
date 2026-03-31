import SwiftUI

struct ReviewActionSheet: View {
    let projectID: Int
    let mr: MergeRequest
    @ObservedObject var viewModel: MergeRequestViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        MRStateBadge(state: mr.state)
                        Text(mr.title)
                            .font(.system(size: 16, weight: .semibold))
                        Text("by \(mr.author.name) · !\(mr.iid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Review Actions") {
                    ReviewActionButton(
                        title: "Approve",
                        subtitle: "Mark this MR as approved",
                        icon: "checkmark.seal.fill",
                        color: .green,
                        isLoading: viewModel.isApproving
                    ) {
                        Task {
                            await viewModel.approve(projectID: projectID, mrIID: mr.iid)
                            dismiss()
                        }
                    }
                    .disabled(mr.state != .opened)

                    ReviewActionButton(
                        title: "Open in GitLab",
                        subtitle: "View in browser",
                        icon: "safari.fill",
                        color: .orange,
                        isLoading: false
                    ) {
                        if let url = URL(string: mr.webURL) {
                            UIApplication.shared.open(url)
                        }
                        dismiss()
                    }
                }

                if viewModel.isApproving {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Approving…")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Review MR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct ReviewActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .foregroundStyle(color)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .disabled(isLoading)
    }
}
