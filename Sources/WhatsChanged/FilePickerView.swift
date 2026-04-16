import SwiftUI

struct FilePickerView: View {
    @Binding var isPresented: Bool
    let fileDiffs: [FileDiff]
    let onSelect: (UUID) -> Void

    @State private var searchText = ""
    @State private var highlightedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var filteredFiles: [FileDiff] {
        if searchText.isEmpty {
            return fileDiffs
        }
        return fileDiffs.filter {
            $0.displayPath.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Jump to file...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppFont.body)
                    .focused($isSearchFocused)
                    .onKeyPress(.upArrow) {
                        moveHighlight(-1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        moveHighlight(1)
                        return .handled
                    }
                    .onSubmit {
                        selectHighlighted()
                    }
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredFiles.enumerated()), id: \.element.id) { index, file in
                            FilePickerRow(
                                file: file,
                                isHighlighted: index == highlightedIndex
                            )
                            .id(file.id)
                            .onTapGesture {
                                onSelect(file.id)
                                isPresented = false
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: highlightedIndex) {
                    let files = filteredFiles
                    if highlightedIndex >= 0, highlightedIndex < files.count {
                        proxy.scrollTo(files[highlightedIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 500)
        .onExitCommand {
            isPresented = false
        }
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: searchText) {
            highlightedIndex = 0
        }
    }

    private func moveHighlight(_ delta: Int) {
        let files = filteredFiles
        guard !files.isEmpty else { return }
        var newIndex = highlightedIndex + delta
        if newIndex < 0 { newIndex = files.count - 1 }
        if newIndex >= files.count { newIndex = 0 }
        highlightedIndex = newIndex
    }

    private func selectHighlighted() {
        let files = filteredFiles
        guard highlightedIndex >= 0, highlightedIndex < files.count else { return }
        onSelect(files[highlightedIndex].id)
        isPresented = false
    }
}

private struct FilePickerRow: View {
    let file: FileDiff
    let isHighlighted: Bool

    var body: some View {
        HStack {
            Text(file.displayPath)
                .font(AppFont.body)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 8) {
                Text("+\(file.additions)")
                    .foregroundStyle(.green)
                Text("-\(file.deletions)")
                    .foregroundStyle(.red)
            }
            .font(AppFont.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor.opacity(0.2) : .clear)
        .contentShape(Rectangle())
    }
}
