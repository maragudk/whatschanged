import AppKit
import SwiftUI

@Observable
private final class CommentAnchor {
    var file: String?
    var line: Int?

    func set(file: String, line: Int) {
        self.file = file
        self.line = line
    }

    func clear() {
        file = nil
        line = nil
    }
}

struct DiffView: View {
    @Environment(AppModel.self) private var model
    let fileDiffs: [FileDiff]
    @Binding var scrollToFileID: UUID?
    @State private var collapsedFiles: Set<String> = []
    @State private var anchor = CommentAnchor()
    @State private var highlightedFileID: UUID?

    var body: some View {
        if fileDiffs.isEmpty {
            ContentUnavailableView(
                "No changes",
                systemImage: "checkmark.circle",
                description: Text("The selected refs are identical.")
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(fileDiffs) { file in
                            FileHeaderView(file: file, collapsedFiles: $collapsedFiles, isHighlighted: highlightedFileID == file.id)
                                .id(file.id)

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
                                        SideBySideRowView(row: row, filePath: file.newPath, anchor: anchor)
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
                .onChange(of: scrollToFileID) {
                    if let id = scrollToFileID {
                        // Uncollapse the file if needed.
                        if let file = fileDiffs.first(where: { $0.id == id }) {
                            collapsedFiles.remove(file.displayPath)
                        }
                        withAnimation {
                            proxy.scrollTo(id, anchor: .top)
                        }
                        scrollToFileID = nil
                        // Flash the file header.
                        withAnimation(.easeIn(duration: 0.15)) {
                            highlightedFileID = id
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            withAnimation(.easeOut(duration: 0.4)) {
                                highlightedFileID = nil
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct FileHeaderView: View {
    let file: FileDiff
    @Binding var collapsedFiles: Set<String>
    var isHighlighted: Bool = false

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
        .background(isHighlighted ? Color(red: 0.95, green: 0.3, blue: 0.5).opacity(0.5) : Color(red: 0.95, green: 0.3, blue: 0.5).opacity(0.2))
        .contentShape(Rectangle())
        .pointerStyle(.link)
    }
}

private struct SideBySideRowView: View {
    @Environment(AppModel.self) private var model
    let row: SideBySideRow
    let filePath: String
    let anchor: CommentAnchor
    @State private var showPopover = false
    @State private var commentText = ""
    @State private var popoverStartLine = 0
    @State private var popoverEndLine = 0
    @State private var isHoveringRightLineNumber = false

    private static let lineNumberWidth: CGFloat = 50
    private static let commentIndicatorWidth: CGFloat = 8
    private static let monoFont = AppFont.body

    private var existingComment: ReviewComment? {
        guard let line = row.right?.lineNumber else { return nil }
        return model.reviewComment(forFile: filePath, line: line)
    }

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
                if !isLeft {
                    commentIndicator(for: side)
                }

                Text(String(side.lineNumber))
                    .font(Self.monoFont)
                    .foregroundStyle(!isLeft && isHoveringRightLineNumber ? .secondary : .tertiary)
                    .frame(width: Self.lineNumberWidth, alignment: .trailing)
                    .padding(.trailing, 8)
                    .background(!isLeft && isHoveringRightLineNumber ? Color.primary.opacity(0.06) : .clear)
                    .contentShape(Rectangle())
                    .pointerStyle(isLeft ? nil : .link)
                    .onHover { hovering in
                        if !isLeft { isHoveringRightLineNumber = hovering }
                    }
                    .onTapGesture {
                        if !isLeft {
                            handleTap(line: side.lineNumber)
                        }
                    }
                    .popover(isPresented: isLeft ? .constant(false) : $showPopover, arrowEdge: .leading) {
                        CommentPopoverView(
                            commentText: $commentText,
                            isPresented: $showPopover,
                            startLine: popoverStartLine,
                            endLine: popoverEndLine,
                            existingComment: existingComment,
                            onSave: { text in
                                if let existing = model.reviewComment(forFile: filePath, line: popoverStartLine) {
                                    guard existing.comment != text else { return }
                                    var updated = existing
                                    updated.comment = text
                                    model.updateReviewComment(updated)
                                } else {
                                    model.addReviewComment(file: filePath, startLine: popoverStartLine, endLine: popoverEndLine, comment: text)
                                }
                            },
                            onDelete: {
                                if let existing = existingComment {
                                    model.deleteReviewComment(existing)
                                }
                            }
                        )
                    }
            } else {
                Color.clear
                    .frame(width: (isLeft ? 0 : Self.commentIndicatorWidth) + Self.lineNumberWidth + 8)
            }

            inlineDiffText(side, isLeft: isLeft)
                .font(Self.monoFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
        }
        .padding(.horizontal, 4)
        .background(backgroundColor(for: side?.type))
    }

    private func handleTap(line: Int) {
        let shiftPressed = NSEvent.modifierFlags.contains(.shift)

        if shiftPressed, let anchorLine = anchor.line, anchor.file == filePath {
            // Shift+click: set range from anchor to this line
            popoverStartLine = min(anchorLine, line)
            popoverEndLine = max(anchorLine, line)
            anchor.clear()
        } else if let existing = existingComment {
            // Click on existing comment: edit it
            popoverStartLine = existing.startLine
            popoverEndLine = existing.endLine
            commentText = existing.comment
            anchor.clear()
            showPopover = true
            return
        } else {
            // Plain click: set anchor and open single-line popover
            anchor.set(file: filePath, line: line)
            popoverStartLine = line
            popoverEndLine = line
        }

        commentText = ""
        showPopover = true
    }

    @ViewBuilder
    private func commentIndicator(for side: SideBySideRow.Side) -> some View {
        let hasComment = model.reviewComment(forFile: filePath, line: side.lineNumber) != nil
        Rectangle()
            .fill(hasComment ? Color.blue.opacity(0.7) : .clear)
            .frame(width: 4)
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

private struct CommentPopoverView: View {
    @Binding var commentText: String
    @Binding var isPresented: Bool
    let startLine: Int
    let endLine: Int
    let existingComment: ReviewComment?
    let onSave: (String) -> Void
    let onDelete: () -> Void

    @State private var didFinish = false

    private var lineLabel: String {
        if startLine <= 0 && endLine <= 0 {
            return ""
        }
        if startLine == endLine {
            return "Line \(startLine)"
        }
        return "Lines \(startLine)-\(endLine)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(existingComment != nil ? "Edit comment" : "Add comment")
                    .font(.headline)
                Text(lineLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextEditor(text: $commentText)
                .font(AppFont.body)
                .frame(minWidth: 500, minHeight: 220)
                .scrollContentBackground(.hidden)

            HStack {
                if existingComment != nil {
                    Button("Delete") {
                        onDelete()
                        didFinish = true
                        isPresented = false
                    }
                    .foregroundStyle(.red)
                }

                Spacer()

                Text("Auto-saves · Esc to cancel")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .onExitCommand {
            didFinish = true
            isPresented = false
        }
        .onDisappear {
            if !didFinish {
                saveIfChanged()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            if !didFinish {
                saveIfChanged()
            }
        }
    }

    private func saveIfChanged() {
        let trimmed = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
    }
}

