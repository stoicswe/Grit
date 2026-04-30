import SwiftUI

// MARK: - File list (embedded in CommitDetailView)

struct CommitDiffView: View {
    let fileDiffs: [ParsedFileDiff]
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("\(fileDiffs.count) changed file\(fileDiffs.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if expanded.count == fileDiffs.count {
                        expanded.removeAll()
                    } else {
                        expanded = Set(fileDiffs.map(\.id))
                    }
                } label: {
                    Text(expanded.count == fileDiffs.count ? "Collapse all" : "Expand all")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 4)

            ForEach(fileDiffs) { file in
                FileDiffCard(
                    file: file,
                    isExpanded: expanded.contains(file.id),
                    onToggle: {
                        withAnimation(.spring(duration: 0.25)) {
                            if expanded.contains(file.id) {
                                expanded.remove(file.id)
                            } else {
                                expanded.insert(file.id)
                            }
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Single file card

private struct FileDiffCard: View {
    let file:       ParsedFileDiff
    let isExpanded: Bool
    let onToggle:   () -> Void
    @State private var cardWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            fileHeader
            if isExpanded {
                diffBody
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            cardWidth = newWidth
        }
    }

    // MARK: Header

    private var fileHeader: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                // File type icon
                Image(systemName: fileIcon(for: file.meta.fileName))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)

                // Paths
                VStack(alignment: .leading, spacing: 1) {
                    if file.meta.renamedFile,
                       let old = file.meta.oldPath, let new = file.meta.newPath, old != new {
                        Text(old)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .strikethrough()
                            .lineLimit(1)
                        Text(new)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    } else {
                        Text(file.meta.fileName)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                        if file.meta.displayPath != file.meta.fileName {
                            Text(file.meta.displayPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Status badge
                if let badge = file.meta.statusBadge {
                    statusBadge(badge)
                }

                // +/- stats
                if !file.isBinaryOrEmpty && !file.isTooLarge {
                    HStack(spacing: 4) {
                        if file.additions > 0 {
                            Text("+\(file.additions)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.green)
                        }
                        if file.deletions > 0 {
                            Text("-\(file.deletions)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                    }
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Diff body

    @ViewBuilder
    private var diffBody: some View {
        Divider().padding(.horizontal, 4)

        if file.isTooLarge {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Diff is too large to display.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(12)

        } else if file.isBinaryOrEmpty {
            HStack(spacing: 8) {
                Image(systemName: "doc.zipper")
                    .foregroundStyle(.secondary)
                Text("Binary file — no diff available.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(12)

        } else {
            // Scrollable diff lines
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(file.lines) { line in
                        DiffLineRow(line: line)
                    }
                }
                // Ensure the VStack is at least as wide as the card
                .frame(minWidth: cardWidth, alignment: .leading)
            }
            .background(Color(UIColor.systemBackground).opacity(0.6))
        }
    }

    // MARK: Helpers

    private func statusBadge(_ text: String) -> some View {
        let color: Color = text == "new" ? .green : text == "deleted" ? .red : .orange
        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":                    return "swift"
        case "py":                       return "p.circle"
        case "js", "ts", "jsx", "tsx":  return "j.circle"
        case "html", "htm", "xml":       return "chevron.left.forwardslash.chevron.right"
        case "css", "scss":              return "paintbrush"
        case "json":                     return "curlybraces"
        case "md", "markdown":           return "doc.richtext"
        case "sh", "bash":               return "terminal"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        case "pdf":                      return "doc.fill"
        case "zip", "gz", "tar":         return "doc.zipper"
        default:                         return "doc.text"
        }
    }
}

// MARK: - Single diff line

private struct DiffLineRow: View {
    let line: DiffLine

    private var bgColor: Color {
        switch line.kind {
        case .added:      return Color.green.opacity(0.22)
        case .removed:    return Color.red.opacity(0.22)
        case .hunkHeader: return Color.accentColor.opacity(0.15)
        default:          return Color.clear
        }
    }

    private var gutterColor: Color {
        switch line.kind {
        case .added:      return Color.green.opacity(0.35)
        case .removed:    return Color.red.opacity(0.35)
        case .hunkHeader: return Color.accentColor.opacity(0.25)
        default:          return Color.primary.opacity(0.06)
        }
    }

    private var lineIndicator: String {
        switch line.kind {
        case .added:      return "+"
        case .removed:    return "−"
        default:          return " "
        }
    }

    private var indicatorColor: Color {
        switch line.kind {
        case .added:      return .green
        case .removed:    return .red
        default:          return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 0) {

            // ── Line-number gutter ────────────────────────────────
            HStack(spacing: 0) {
                lineNumberCell(line.oldNumber)
                lineNumberCell(line.newNumber)
            }
            .background(gutterColor)

            // ── +/- indicator ─────────────────────────────────────
            Text(lineIndicator)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(indicatorColor)
                .frame(width: 16)
                .padding(.horizontal, 4)
                .background(bgColor)

            // ── Content ───────────────────────────────────────────
            if case .hunkHeader = line.kind {
                Text(line.content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            } else {
                Text(line.content.isEmpty ? " " : line.content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(contentColor)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(bgColor)
        .frame(minHeight: 20)
    }

    private var contentColor: Color {
        switch line.kind {
        case .added:   return .primary
        case .removed: return .primary
        case .meta:    return .secondary
        default:       return .primary
        }
    }

    @ViewBuilder
    private func lineNumberCell(_ number: Int?) -> some View {
        Group {
            if let n = number {
                Text("\(n)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text(" ")
                    .font(.system(size: 10, design: .monospaced))
            }
        }
        .frame(width: 36, alignment: .trailing)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }
}
