import SwiftUI
import MessageUI
import OSLog
import UIKit

struct ReportIssueView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isCollecting  = false
    @State private var showComposer  = false
    @State private var logData:      Data?
    @State private var showNoMail    = false

    private let recipient = "contact@stoicswe.com"

    var body: some View {
        NavigationStack {
            List {

                // MARK: - What's included

                Section {
                    infoRow(icon: "info.circle",           color: .blue,   label: "App name and version")
                    infoRow(icon: "iphone",                color: .gray,   label: "Device model and iOS version")
                    infoRow(icon: "doc.text.magnifyingglass", color: .orange, label: "Log entries from the last 60 minutes")
                } header: {
                    Text("What's included")
                } footer: {
                    Text("Only logs from the Grit app process are collected — no system logs, no data from other apps.")
                }

                // MARK: - Privacy note

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Your Privacy", systemImage: "lock.shield.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Logs contain only technical app events such as network requests and navigation. They never include your GitLab tokens, passwords, or personal data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Send button

                Section {
                    Button {
                        Task { await collectAndCompose() }
                    } label: {
                        if isCollecting {
                            HStack(spacing: 10) {
                                ProgressView().scaleEffect(0.85)
                                Text("Collecting logs…")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Label("Compose Report", systemImage: "paperplane.fill")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isCollecting)
                } footer: {
                    Text("This opens your mail app with the report pre-filled and the logs attached. You can review and edit everything before sending.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Report an Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            // Present the in-app mail composer as a full-screen cover so it
            // gets its own navigation context (MFMailComposeViewController requires this).
            .fullScreenCover(isPresented: $showComposer) {
                if let data = logData {
                    MailComposerView(
                        toRecipients:      [recipient],
                        subject:           "Bug Report — Grit for GitLab",
                        body:              mailBodyTemplate,
                        attachmentData:    data,
                        attachmentMimeType: "text/plain",
                        attachmentFileName: "grit-diagnostic.txt"
                    )
                    .ignoresSafeArea()
                }
            }
            .alert("Mail Not Set Up", isPresented: $showNoMail) {
                Button("Copy Address") {
                    UIPasteboard.general.string = recipient
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("No mail account is configured on this device. The address \(recipient) has been copied to your clipboard so you can email from another app.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Info row helper

    private func infoRow(icon: String, color: Color, label: String) -> some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
        }
    }

    // MARK: - Collect logs & open composer

    private func collectAndCompose() async {
        guard MFMailComposeViewController.canSendMail() else {
            showNoMail = true
            return
        }
        isCollecting = true
        logData = await buildLogData()
        isCollecting = false
        showComposer = true
    }

    // MARK: - Build log attachment

    private func buildLogData() async -> Data {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let device  = UIDevice.current

        var text = """
        Grit for GitLab — Diagnostic Report
        ====================================
        App Version  : \(version) (build \(build))
        Device       : \(device.model)
        iOS Version  : \(device.systemVersion)
        Generated    : \(Date().formatted(.iso8601))

        ── App Log Entries (last 60 minutes) ─────────────────

        """

        do {
            let store   = try OSLogStore(scope: .currentProcessIdentifier)
            let since   = store.position(date: Date().addingTimeInterval(-3600))
            let entries = try store.getEntries(at: since)
            let lines: [String] = entries.compactMap { entry in
                guard let e = entry as? OSLogEntryLog else { return nil }
                let ts  = e.date.formatted(.iso8601)
                let lvl = e.level.shortLabel
                return "[\(ts)] [\(lvl)] \(e.composedMessage)"
            }
            text += lines.isEmpty
                ? "(no log entries recorded in the past hour)\n"
                : lines.joined(separator: "\n") + "\n"
        } catch {
            text += "(log collection failed: \(error.localizedDescription))\n"
        }

        return Data(text.utf8)
    }

    // MARK: - Email body template

    private var mailBodyTemplate: String {
        """
        Hi Nathaniel,

        I found an issue with Grit for GitLab.

        What happened:
        [Please describe the issue here]

        Steps to reproduce:
        1.
        2.
        3.

        Expected behaviour:


        Actual behaviour:


        ──────────────────────────────────────
        Diagnostic logs are attached as grit-diagnostic.txt.
        """
    }
}

// MARK: - Mail Composer (UIKit bridge)

private struct MailComposerView: UIViewControllerRepresentable {
    let toRecipients:       [String]
    let subject:            String
    let body:               String
    let attachmentData:     Data
    let attachmentMimeType: String
    let attachmentFileName: String

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(toRecipients)
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        vc.addAttachmentData(attachmentData,
                             mimeType: attachmentMimeType,
                             fileName: attachmentFileName)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController,
                                context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailComposerView
        init(_ parent: MailComposerView) { self.parent = parent }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            parent.dismiss()
        }
    }
}

// MARK: - OSLogEntryLog level label

private extension OSLogEntryLog.Level {
    var shortLabel: String {
        switch self {
        case .undefined: return "---"
        case .debug:     return "DBG"
        case .info:      return "INF"
        case .notice:    return "NTC"
        case .error:     return "ERR"
        case .fault:     return "FLT"
        @unknown default: return "???"
        }
    }
}
