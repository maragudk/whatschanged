import SwiftUI

struct PaletteCommand: Identifiable {
    let id: String
    let name: String
    let shortcut: String?
    let isEnabled: Bool
    let action: () -> Void
}

struct CommandPaletteView: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @Binding var openBasePicker: Bool
    @Binding var openComparePicker: Bool
    @Binding var openFilePicker: Bool
    let openRepo: () -> Void

    @State private var searchText = ""
    @State private var highlightedIndex = 0
    @FocusState private var isSearchFocused: Bool

    private var commands: [PaletteCommand] {
        [
            PaletteCommand(id: "open-repo", name: "Open Repository...", shortcut: "Cmd+O", isEnabled: true) {
                openRepo()
            },
            PaletteCommand(id: "select-base", name: "Select Base Ref", shortcut: "Cmd+K", isEnabled: model.repoPath != nil) {
                openBasePicker = true
            },
            PaletteCommand(id: "select-compare", name: "Select Compare Ref", shortcut: "Cmd+L", isEnabled: model.repoPath != nil) {
                openComparePicker = true
            },
            PaletteCommand(id: "push", name: "Push Current Branch", shortcut: nil, isEnabled: model.repoPath != nil) {
                model.pushCurrentBranch()
            },
            PaletteCommand(id: "pull-current", name: "Pull Current Branch", shortcut: "Cmd+P", isEnabled: model.repoPath != nil) {
                model.pullCurrentBranch()
            },
            PaletteCommand(id: "pull-default", name: "Pull Default Branch", shortcut: nil, isEnabled: model.repoPath != nil) {
                model.pullDefaultBranch()
            },
            PaletteCommand(id: "commit-review", name: "Commit Review Comments", shortcut: "Cmd+S", isEnabled: model.repoRoot != nil) {
                model.commitReviewComments()
            },
            PaletteCommand(id: "jump-file", name: "Jump to File", shortcut: "Cmd+J", isEnabled: !model.fileDiffs.isEmpty) {
                openFilePicker = true
            },
            PaletteCommand(id: "refresh", name: "Refresh", shortcut: "Cmd+R", isEnabled: model.repoPath != nil) {
                model.loadRefs()
            },
        ]
    }

    private var filteredCommands: [PaletteCommand] {
        if searchText.isEmpty {
            return commands
        }
        return commands.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search commands...", text: $searchText)
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
                        executeHighlighted()
                    }
            }
            .padding(12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                            CommandRow(
                                command: command,
                                isHighlighted: index == highlightedIndex
                            )
                            .id(command.id)
                            .onTapGesture {
                                if command.isEnabled {
                                    command.action()
                                    isPresented = false
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .onChange(of: highlightedIndex) {
                    let cmds = filteredCommands
                    if highlightedIndex >= 0, highlightedIndex < cmds.count {
                        proxy.scrollTo(cmds[highlightedIndex].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 400)
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
        let cmds = filteredCommands
        guard !cmds.isEmpty else { return }
        var newIndex = highlightedIndex + delta
        if newIndex < 0 { newIndex = cmds.count - 1 }
        if newIndex >= cmds.count { newIndex = 0 }
        highlightedIndex = newIndex
    }

    private func executeHighlighted() {
        let cmds = filteredCommands
        guard highlightedIndex >= 0, highlightedIndex < cmds.count else { return }
        let command = cmds[highlightedIndex]
        if command.isEnabled {
            command.action()
            isPresented = false
        }
    }
}

private struct CommandRow: View {
    let command: PaletteCommand
    let isHighlighted: Bool

    var body: some View {
        HStack {
            Text(command.name)
                .font(AppFont.body)
                .foregroundStyle(command.isEnabled ? .primary : .tertiary)

            Spacer()

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(AppFont.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor.opacity(0.2) : .clear)
        .contentShape(Rectangle())
    }
}
