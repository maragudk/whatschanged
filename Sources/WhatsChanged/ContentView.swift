import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        if model.repoPath != nil {
            VStack(spacing: 0) {
                // Toolbar with ref pickers.
                toolbar

                Divider()

                // Diff content.
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.error {
                    ContentUnavailableView(
                        "Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if model.compareRef == nil {
                    ContentUnavailableView(
                        "Select a branch to compare",
                        systemImage: "arrow.triangle.branch",
                        description: Text("Pick a ref on the right to see changes.")
                    )
                } else {
                    DiffView(fileDiffs: model.fileDiffs)
                }
            }
            .onAppear {
                model.loadRefs()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                model.loadRefs()
            }
        } else {
            welcomeView
        }
    }

    private var toolbar: some View {
        HStack {
            @Bindable var model = model

            RefPickerView(
                title: "Base ref...",
                refs: model.refs,
                selection: $model.baseRef
            )

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            RefPickerView(
                title: "Compare ref...",
                refs: model.refs,
                selection: $model.compareRef
            )

            Spacer()

            if let repoPath = model.repoPath {
                Text(repoPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onChange(of: model.baseRef) {
            model.loadDiff()
        }
        .onChange(of: model.compareRef) {
            model.loadDiff()
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("What's Changed")
                .font(.title)

            Text("Open a git repository to view changes across branches and worktrees.")
                .foregroundStyle(.secondary)

            Button("Open Repository...") {
                openRepo()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository"

        if panel.runModal() == .OK, let url = panel.url {
            model.openRepo(at: url)
        }
    }
}
