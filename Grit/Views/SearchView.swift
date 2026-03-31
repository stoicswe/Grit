import SwiftUI

struct SearchView: View {
    @EnvironmentObject var navState: AppNavigationState
    @Environment(\.dismiss) var dismiss

    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    ContentUnavailableView(
                        "Search",
                        systemImage: "magnifyingglass",
                        description: Text(navState.currentRepository != nil
                            ? "Search in \(navState.currentRepository!.name)"
                            : "Search across your projects")
                    )
                }
            }
            .searchable(text: $query, prompt: "Search…")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
