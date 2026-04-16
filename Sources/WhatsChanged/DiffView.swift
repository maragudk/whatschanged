import SwiftUI

struct DiffView: View {
    let fileDiffs: [FileDiff]
    @State private var collapsedFiles: Set<String> = []

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
                        FileHeaderView(file: file, collapsedFiles: $collapsedFiles)

                        if !collapsedFiles.contains(file.displayPath) {
                            if file.isBinary {
                                Text("Binary file changed")
                                    .font(AppFont.body)
                                    .foregroundStyle(.secondary)
                                    .padding(12)
                            } else {
                                ForEach(Array(file.hunks.enumerated()), id: \.element.id) { index, hunk in
                                    if index > 0 {
                                        Text("···")
                                            .font(AppFont.caption)
                                            .foregroundStyle(.tertiary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(.quaternary.opacity(0.5))
                                    }
                                    ForEach(hunk.rows) { row in
                                        SideBySideRowView(row: row)
                                    }
                                }
                            }
                        }
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

private struct FileHeaderView: View {
    let file: FileDiff
    @Binding var collapsedFiles: Set<String>

    private var isCollapsed: Bool {
        collapsedFiles.contains(file.displayPath)
    }

    var body: some View {
        Button {
            if isCollapsed {
                collapsedFiles.remove(file.displayPath)
            } else {
                collapsedFiles.insert(file.displayPath)
            }
        } label: {
            HStack {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
                Text(file.displayPath)
                    .font(AppFont.bodySemibold)
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
                    .font(AppFont.caption)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(red: 0.95, green: 0.3, blue: 0.5).opacity(0.2))
        .contentShape(Rectangle())
        .pointerStyle(.link)
    }
}

private struct SideBySideRowView: View {
    let row: SideBySideRow

    private static let lineNumberWidth: CGFloat = 50
    private static let monoFont = AppFont.body

    var body: some View {
        HStack(spacing: 0) {
            lineSide(row.left, isLeft: true)
            lineSide(row.right, isLeft: false)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func lineSide(_ side: SideBySideRow.Side?, isLeft: Bool) -> some View {
        HStack(spacing: 0) {
            if let side {
                Text(String(side.lineNumber))
                    .font(Self.monoFont)
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.lineNumberWidth, alignment: .trailing)
                    .padding(.trailing, 8)
            } else {
                Color.clear
                    .frame(width: Self.lineNumberWidth + 8)
            }

            inlineDiffText(side, isLeft: isLeft)
                .font(Self.monoFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
        }
        .padding(.horizontal, 4)
        .background(backgroundColor(for: side?.type))
    }

    private func inlineDiffText(_ side: SideBySideRow.Side?, isLeft: Bool) -> Text {
        let segments = isLeft ? row.leftSegments : row.rightSegments
        guard let (prefix, changed, suffix) = segments else {
            return Text(side?.content ?? "")
        }

        let highlight: Color = isLeft ? .red.opacity(0.35) : .green.opacity(0.35)

        var highlightedPrefix = AttributedString(prefix)
        highlightedPrefix.backgroundColor = nil
        var highlightedChanged = AttributedString(changed)
        highlightedChanged.backgroundColor = highlight
        var highlightedSuffix = AttributedString(suffix)
        highlightedSuffix.backgroundColor = nil

        return Text(highlightedPrefix + highlightedChanged + highlightedSuffix)
    }

    private func backgroundColor(for type: SideBySideRow.SideType?) -> Color {
        switch type {
        case .addition:
            return .green.opacity(0.2)
        case .deletion:
            return .red.opacity(0.2)
        case .modified:
            return .yellow.opacity(0.15)
        case .context, nil:
            return .clear
        }
    }
}
