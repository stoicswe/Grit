import SwiftUI

// MARK: - License View

struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selected: LicenseFile = .source
    @State private var sourceText: String = ""
    @State private var designText: String = ""

    enum LicenseFile: String, CaseIterable {
        case source = "Source Code"
        case design = "App & UI Design"

        var resource: String {
            switch self {
            case .source: return "LICENSE"
            case .design: return "APP_LICENSE"
            }
        }

        var subtitle: String {
            switch self {
            case .source: return "MIT License"
            case .design: return "Apache License 2.0"
            }
        }
    }

    private var currentText: String {
        switch selected {
        case .source: return sourceText
        case .design: return designText
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("License", selection: $selected) {
                    ForEach(LicenseFile.allCases, id: \.self) { file in
                        Text(file.rawValue).tag(file)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Text(selected.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                Divider()

                ScrollView {
                    if currentText.isEmpty {
                        ContentUnavailableView(
                            "License unavailable",
                            systemImage: "doc.text",
                            description: Text("The license file could not be found in the app bundle.")
                        )
                        .padding(.top, 60)
                    } else {
                        Text(currentText)
                            .font(.system(size: 13, weight: .light, design: .serif))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineSpacing(5)
                            .kerning(0.1)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 20)
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle("License")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { loadLicenses() }
    }

    // MARK: - Load

    private func loadLicenses() {
        sourceText = load("LICENSE")
        designText = load("APP_LICENSE")
    }

    private func load(_ resource: String) -> String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }
}
