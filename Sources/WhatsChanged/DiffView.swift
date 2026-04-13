import SwiftUI

struct DiffView: View {
    let fileDiffs: [FileDiff]

    var body: some View {
        if fileDiffs.isEmpty {
            ContentUnavailableView(
                "No changes",
                systemImage: "checkmark.circle",
                description: Text("The selected refs are identical.")
            )
        } else {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(fileDiffs) { file in
                        FileSection(file: file)
                    }
                }
                .overlay(alignment: .center) {
                    Rectangle()
                        .fill(.quaternary)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }
}

private struct FileSection: View {
    let file: FileDiff
    @State private var isCollapsed = false

    var body: some View {
        // File header.
        Button {
            isCollapsed.toggle()
        } label: {
            HStack {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(file.displayPath)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if file.isBinary {
                    Text("binary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        Text("+\(file.additions)")
                            .foregroundStyle(.green)
                        Text("-\(file.deletions)")
                            .foregroundStyle(.red)
                    }
                    .font(.system(.caption, design: .monospaced))
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }

        Divider()

        if !isCollapsed {
            if file.isBinary {
                Text("Binary file changed")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(file.hunks) { hunk in
                    HunkView(hunk: hunk)
                }
            }
        }
    }
}

private struct HunkView: View {
    let hunk: DiffHunk

    var body: some View {
        let rows = DiffParser.sideBySideRows(for: hunk)

        ForEach(rows) { row in
            SideBySideRowView(row: row)
        }
    }
}

private struct SideBySideRowView: View {
    let row: SideBySideRow

    private static let lineNumberWidth: CGFloat = 50
    private static let monoFont = Font.system(.body, design: .monospaced)

    var body: some View {
        HStack(spacing: 0) {
            // Left side.
            lineSide(row.left, isDeletion: true)

            // Right side.
            lineSide(row.right, isDeletion: false)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func lineSide(_ side: SideBySideRow.Side?, isDeletion: Bool) -> some View {
        HStack(spacing: 0) {
            // Line number.
            if let side {
                Text("\(side.lineNumber)")
                    .font(Self.monoFont)
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.lineNumberWidth, alignment: .trailing)
                    .padding(.trailing, 8)
            } else {
                Color.clear
                    .frame(width: Self.lineNumberWidth + 8)
            }

            // Content.
            Text(side?.content ?? "")
                .font(Self.monoFont)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
        }
        .padding(.horizontal, 4)
        .background(backgroundColor(for: side?.type))
    }

    private func backgroundColor(for type: SideBySideRow.SideType?) -> Color {
        switch type {
        case .addition:
            return .green.opacity(0.12)
        case .deletion:
            return .red.opacity(0.12)
        case .modified:
            return .yellow.opacity(0.10)
        case .context, nil:
            return .clear
        }
    }
}
