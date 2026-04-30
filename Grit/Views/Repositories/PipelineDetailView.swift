import SwiftUI
import UIKit

// MARK: - View Model

@MainActor
private final class PipelineDetailViewModel: ObservableObject {
    @Published var detail:    PipelineDetail?
    @Published var jobs:      [PipelineJob] = []
    @Published var isLoading  = true
    @Published var error:     String?

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    func load(projectID: Int, pipelineID: Int) async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error     = nil

        // Fetch detail metadata and jobs in parallel
        await withTaskGroup(of: Void.self) { tg in
            tg.addTask {
                do {
                    let d = try await self.api.fetchPipelineDetail(
                        projectID:  projectID,
                        pipelineID: pipelineID,
                        baseURL:    self.auth.baseURL,
                        token:      token
                    )
                    await MainActor.run { self.detail = d }
                } catch {
                    await MainActor.run { self.error = error.localizedDescription }
                }
            }
            tg.addTask {
                do {
                    let j = try await self.api.fetchPipelineJobs(
                        projectID:  projectID,
                        pipelineID: pipelineID,
                        baseURL:    self.auth.baseURL,
                        token:      token
                    )
                    await MainActor.run { self.jobs = j }
                } catch {
                    // Jobs failure is non-fatal if detail loaded
                    await MainActor.run { if self.error == nil { self.error = error.localizedDescription } }
                }
            }
        }

        isLoading = false
    }
}

// MARK: - Pipeline Detail View

struct PipelineDetailView: View {
    let pipeline:  Pipeline
    let projectID: Int

    @StateObject private var viewModel = PipelineDetailViewModel()
    @State private var selectedJob: PipelineJob?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var navState: AppNavigationState
    @ObservedObject private var aiService = AIAssistantService.shared

    /// Jobs grouped by stage, preserving the pipeline's natural stage order.
    private var stages: [(name: String, jobs: [PipelineJob])] {
        var order = [String]()
        var map   = [String: [PipelineJob]]()
        for job in viewModel.jobs {
            if map[job.stage] == nil {
                order.append(job.stage)
                map[job.stage] = []
            }
            map[job.stage]!.append(job)
        }
        return order.map { (name: $0, jobs: map[$0]!) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    pipelineHeader

                    if viewModel.isLoading {
                        loadingSkeleton
                    } else if let error = viewModel.error, viewModel.jobs.isEmpty {
                        ErrorBanner(message: error) { viewModel.error = nil }
                    } else if !viewModel.isLoading && viewModel.jobs.isEmpty {
                        ContentUnavailableView(
                            "No Jobs",
                            systemImage: "square.stack.3d.up.slash",
                            description: Text("This pipeline has no recorded jobs.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(stages, id: \.name) { entry in
                            stageCard(entry.name, jobs: entry.jobs)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .navigationTitle("Pipeline #\(pipeline.id)")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await viewModel.load(projectID: projectID, pipelineID: pipeline.id) }
            .sheet(item: $selectedJob) { job in
                JobLogView(job: job, projectID: projectID)
                    .environmentObject(navState)
            }
        }
        // AI drawer floats above the pipeline sheet.
        // Overlay lives outside the NavigationStack so it renders over the nav bar too.
        .overlay {
            if aiService.isUserEnabled {
                AISlideDrawer()
                    .environmentObject(navState)
            }
        }
        .onAppear {
            // Give the AI context about which pipeline the user is viewing.
            navState.enterFile(path: "Pipeline #\(pipeline.id) · \(pipeline.label)\(pipeline.ref.map { " · \($0)" } ?? "")")
        }
        .onDisappear {
            // Restore: repo detail already set repo/branch; just clear the extra fields.
            navState.currentFilePath = nil
            navState.setScreenContent(nil)
        }
    }

    // MARK: - Pipeline header

    private var pipelineHeader: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {

                // Status row
                HStack(spacing: 12) {
                    Image(systemName: pipeline.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(pipeline.color)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(pipeline.label)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(pipeline.color)
                            Text("· #\(pipeline.id)")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        if let ref = pipeline.ref {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 11))
                                Text(ref)
                                    .font(.system(size: 13, design: .monospaced))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let detail = viewModel.detail {
                    Divider().opacity(0.4)

                    VStack(alignment: .leading, spacing: 10) {

                        // Triggered by
                        if let user = detail.user {
                            metaRow(
                                icon: detail.sourceIcon,
                                label: "Triggered by"
                            ) {
                                HStack(spacing: 6) {
                                    AvatarView(urlString: user.avatarURL, name: user.name, size: 18)
                                    Text(user.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Text("· \(detail.sourceLabel)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            metaRow(icon: detail.sourceIcon, label: "Trigger") {
                                Text(detail.sourceLabel)
                                    .font(.system(size: 13))
                            }
                        }

                        // Commit SHA
                        if let sha = detail.shortSHA {
                            metaRow(icon: "chevron.left.forwardslash.chevron.right", label: "Commit") {
                                Text(sha)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(.tint)
                            }
                        }

                        // Timings
                        if let started = detail.startedAt {
                            metaRow(icon: "play.circle", label: "Started") {
                                Text(started.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 13))
                            }
                        }
                        if let finished = detail.finishedAt {
                            metaRow(icon: "stop.circle", label: "Finished") {
                                Text(finished.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 13))
                            }
                        }

                        // Duration
                        if let dur = detail.durationFormatted {
                            metaRow(icon: "timer", label: "Duration") {
                                HStack(spacing: 6) {
                                    Text(dur)
                                        .font(.system(size: 13, weight: .medium))
                                    if let q = detail.queuedDurationFormatted {
                                        Text("+ \(q)")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else if viewModel.isLoading {
                    // Metadata shimmer
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(0..<4, id: \.self) { _ in
                            HStack(spacing: 8) {
                                ShimmerView().frame(width: 14, height: 14).clipShape(Circle())
                                ShimmerView().frame(height: 12).frame(maxWidth: 220)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func metaRow<V: View>(icon: String, label: String, @ViewBuilder value: () -> V) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            value()
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Stage card

    private func stageCard(_ stage: String, jobs: [PipelineJob]) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // Stage header
            HStack(spacing: 8) {
                stageIcon(for: jobs)
                    .font(.system(size: 14, weight: .semibold))
                Text(stage.capitalized)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                let passed = jobs.filter { $0.status.lowercased() == "success" }.count
                Text("\(passed)/\(jobs.count) passed")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().opacity(0.4)

            // Job rows
            ForEach(jobs) { job in
                Button { selectedJob = job } label: {
                    jobRow(job)
                }
                .buttonStyle(.plain)

                if job.id != jobs.last?.id {
                    Divider()
                        .padding(.leading, 52)
                        .opacity(0.3)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .regularGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func stageIcon(for jobs: [PipelineJob]) -> some View {
        let statuses = Set(jobs.map { $0.status.lowercased() })
        if statuses.contains("failed") {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        } else if statuses.contains("running") {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.circle.fill").foregroundStyle(.blue)
        } else if statuses.contains("pending") || statuses.contains("created") || statuses.contains("preparing") {
            Image(systemName: "clock.fill").foregroundStyle(.orange)
        } else if statuses.contains("manual") {
            Image(systemName: "hand.tap.fill").foregroundStyle(.purple)
        } else if statuses.allSatisfy({ $0 == "success" || $0 == "skipped" || $0 == "canceled" }) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
            Image(systemName: "circle.fill").foregroundStyle(Color.secondary)
        }
    }

    // MARK: - Job row

    private func jobRow(_ job: PipelineJob) -> some View {
        HStack(spacing: 12) {
            Image(systemName: job.icon)
                .font(.system(size: 18))
                .foregroundStyle(job.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(job.label)
                        .font(.system(size: 12))
                        .foregroundStyle(job.color)

                    if let dur = job.durationFormatted {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(dur)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    if job.allowFailure && job.status.lowercased() == "failed" {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("allowed to fail")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        VStack(spacing: 14) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        ShimmerView().frame(width: 14, height: 14).clipShape(Circle())
                        ShimmerView().frame(width: 80, height: 12)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider().opacity(0.4)

                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: 12) {
                            ShimmerView().frame(width: 28, height: 18).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                ShimmerView().frame(height: 13).frame(maxWidth: 160)
                                ShimmerView().frame(height: 10).frame(maxWidth: 90)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .regularGlassEffect(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

// MARK: - No-wrap UITextView subclass

/// UITextView that keeps an infinite-width text container AND a correct
/// `contentSize` on every layout pass.
///
/// Two things go wrong with a plain UITextView when you want horizontal scroll:
///
/// 1. **Container reset**: SwiftUI calls `setBounds` after `makeUIView` returns,
///    and UITextView silently resets `textContainer.size` to match the view's
///    own bounds, so TextKit wraps at the screen edge.  Restoring the infinite
///    size *before* `super.layoutSubviews()` fixes this.
///
/// 2. **Content-size collapse**: After layout, UITextView resets `contentSize`
///    to the view's frame width (or the last visible line width with lazy
///    TextKit 2), so the scroll view thinks there is nothing to the right and
///    snaps back.  We compute the true content width from the longest line
///    (cheap with a monospaced font) and enforce it after `super`.
private final class NoWrapTextView: UITextView {

    /// Pixel width of the widest line, including insets.  Updated whenever
    /// `attributedText` is set.  O(n) string scan — fast, no layout needed.
    private var naturalContentWidth: CGFloat = 0

    override var attributedText: NSAttributedString! {
        didSet { recomputeNaturalWidth() }
    }

    private func recomputeNaturalWidth() {
        guard let attributed = attributedText, attributed.length > 0 else {
            naturalContentWidth = 0
            return
        }
        // Monospaced: every glyph has the same advance width, so measuring
        // the widest line by character count is accurate and very fast.
        let font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let charWidth = ("W" as NSString).size(withAttributes: [.font: font]).width
        let maxChars  = attributed.string
            .components(separatedBy: "\n")
            .map(\.count)
            .max() ?? 0
        naturalContentWidth = CGFloat(maxChars) * charWidth
            + textContainerInset.left + textContainerInset.right
            + textContainer.lineFragmentPadding * 2
    }

    override func layoutSubviews() {
        // 1. Restore infinite container BEFORE super so TextKit never wraps.
        textContainer.widthTracksTextView  = false
        textContainer.heightTracksTextView = false
        textContainer.size = CGSize(
            width:  CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        super.layoutSubviews()
        // 2. Enforce correct contentSize.width AFTER super so the scroll view
        //    allows horizontal panning all the way to the end of the longest line.
        if naturalContentWidth > contentSize.width {
            contentSize = CGSize(width: naturalContentWidth, height: contentSize.height)
        }
    }
}

// MARK: - Log Text View (UITextView wrapper)

/// UIViewRepresentable wrapping `NoWrapTextView`. Accepts a plain, ANSI-stripped
/// string and builds the highlighted `NSAttributedString` synchronously inside
/// `makeUIView` so TextKit 2 lazy rendering kicks in immediately.
private struct LogTextView: UIViewRepresentable {
    /// Plain text, already stripped of ANSI escape sequences.
    let text: String

    func makeUIView(context: Context) -> NoWrapTextView {
        let tv = NoWrapTextView()
        tv.isEditable             = false
        tv.isSelectable           = true
        tv.backgroundColor        = .clear
        tv.textContainerInset     = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)

        // Initial container setup — layoutSubviews will re-apply on every pass.
        tv.textContainer.widthTracksTextView  = false
        tv.textContainer.heightTracksTextView = false
        tv.textContainer.size = CGSize(
            width:  CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        tv.showsHorizontalScrollIndicator = true
        tv.alwaysBounceHorizontal         = true

        tv.attributedText = Self.buildAttributedString(text)
        return tv
    }

    func updateUIView(_ tv: NoWrapTextView, context: Context) {
        // Only rebuild when the underlying text actually changes.
        guard tv.attributedText.string != text else { return }
        tv.attributedText = Self.buildAttributedString(text)
    }

    // MARK: - Attributed string builder

    /// Builds a syntax-highlighted attributed string.
    /// No `NSParagraphStyle` is applied — wrapping is suppressed by the
    /// infinite-width text container in `makeUIView`, so lines render to their
    /// full natural width and horizontal scroll reveals the whole line.
    static func buildAttributedString(_ text: String) -> NSAttributedString {
        let baseFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let boldFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

        let result = NSMutableAttributedString()
        let lines  = text.components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            let attrs = lineAttributes(line, base: baseFont, bold: boldFont)
            result.append(NSAttributedString(string: line, attributes: attrs))
            if i < lines.count - 1 {
                result.append(NSAttributedString(
                    string: "\n",
                    attributes: [.font: baseFont, .foregroundColor: UIColor.label]
                ))
            }
        }
        return result
    }

    private static func lineAttributes(
        _ line: String,
        base: UIFont,
        bold: UIFont
    ) -> [NSAttributedString.Key: Any] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let lower   = trimmed.lowercased()

        // Section markers — dim, not useful to highlight
        if trimmed.hasPrefix("section_start:") || trimmed.hasPrefix("section_end:") {
            return [.font: base, .foregroundColor: UIColor.tertiaryLabel]
        }

        // Errors — bold red
        if lower.hasPrefix("error") || lower.hasPrefix("fatal")
            || lower.contains(": error ")  || lower.contains(": error:")
            || lower.contains("error:") || lower.contains("failed:")
            || lower.contains("fatal:") || lower.contains(" failed")
            || lower == "failed" {
            return [.font: bold, .foregroundColor: UIColor.systemRed]
        }

        // Warnings — orange
        if lower.hasPrefix("warning") || lower.contains("warning:") || lower.contains(" warning ") {
            return [.font: base, .foregroundColor: UIColor.systemOrange]
        }

        // Shell commands ($ cmd, + cmd, ++ cmd, % cmd)
        if trimmed.hasPrefix("$ ") || trimmed.hasPrefix("+ ")
            || trimmed.hasPrefix("++ ") || trimmed.hasPrefix("% ") {
            return [.font: bold, .foregroundColor: UIColor.systemCyan]
        }

        // Timestamp-prefixed metadata lines like [12:34:56]
        if trimmed.hasPrefix("[") && trimmed.count > 10 {
            if trimmed.dropFirst().first?.isNumber == true {
                return [.font: base, .foregroundColor: UIColor.secondaryLabel]
            }
        }

        // Success indicators
        if lower == "passed" || lower == "ok"
            || lower.hasPrefix("job succeeded") || lower.contains("passed!")
            || lower.hasPrefix("pipeline succeeded") {
            return [.font: bold, .foregroundColor: UIColor.systemGreen]
        }

        // Stage / section headings GitLab emits (e.g. "Running stage:")
        if lower.hasPrefix("running stage:") || lower.hasPrefix("executing stage:") {
            return [.font: bold, .foregroundColor: UIColor.systemIndigo]
        }

        // Default
        return [.font: base, .foregroundColor: UIColor.label]
    }
}

// MARK: - Job Log View

struct JobLogView: View {
    let job:       PipelineJob
    let projectID: Int

    /// Plain ANSI-stripped text. Passed directly to LogTextView which builds
    /// the NSAttributedString synchronously — avoids reference-type @State diffing.
    @State private var cleanedLog: String?
    @State private var isLoading  = true
    @State private var error:      String?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var navState: AppNavigationState
    @ObservedObject private var aiService = AIAssistantService.shared

    private let api  = GitLabAPIService.shared
    private let auth = AuthenticationService.shared

    /// Compiled once at app launch; reused for every log fetch.
    private nonisolated static let ansiRegex: NSRegularExpression? = {
        let pattern = #"\x1B(?:[@-Z\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Loading log…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView {
                        Label("Log Unavailable", systemImage: "lock.slash")
                    } description: {
                        Text(error)
                    }
                } else if let clean = cleanedLog {
                    if clean.isEmpty {
                        ContentUnavailableView(
                            "Empty Log",
                            systemImage: "doc.text",
                            description: Text("This job produced no output.")
                        )
                    } else {
                        LogTextView(text: clean)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            .navigationTitle(job.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if let log = cleanedLog, !log.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(
                            item: log,
                            subject: Text("Job log: \(job.name)"),
                            message: Text("CI log for job \"\(job.name)\"")
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        // AI drawer floats above the log sheet.
        .overlay {
            if aiService.isUserEnabled {
                AISlideDrawer()
                    .environmentObject(navState)
            }
        }
        .task { await loadLog() }
        .onDisappear {
            // Restore the pipeline context that PipelineDetailView set.
            navState.setScreenContent(nil)
            navState.currentFilePath = "Pipeline #\(job.id)"
        }
    }

    // MARK: - Load

    private func loadLog() async {
        guard let token = auth.accessToken else { return }
        isLoading = true
        error     = nil
        do {
            let raw = try await api.fetchJobLog(
                projectID: projectID,
                jobID:     job.id,
                baseURL:   auth.baseURL,
                token:     token
            )
            // Strip ANSI on a background thread — returns a plain String (value type,
            // safe to cross actor boundaries). The attributed string is built later,
            // synchronously inside LogTextView.makeUIView.
            let cleaned = await Task.detached(priority: .userInitiated) {
                Self.stripANSI(raw)
            }.value
            cleanedLog = cleaned
            // Push log content into navState so the AI can analyze it.
            // Tail-truncate to stay within the AI's token budget.
            let aiContent = cleaned.count > 6000
                ? "…[earlier output omitted]\n" + String(cleaned.suffix(6000))
                : cleaned
            navState.enterFile(path: "jobs/\(job.name)", content: aiContent)
        } catch GitLabAPIService.APIError.httpError(403) {
            error = "You don't have permission to view this job's log."
        } catch GitLabAPIService.APIError.httpError(404) {
            error = "Log not found. The job may not have produced output yet."
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - ANSI stripping (called on background thread)

    private nonisolated static func stripANSI(_ text: String) -> String {
        guard let regex = ansiRegex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex
            .stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: "\r", with: "")
    }
}
