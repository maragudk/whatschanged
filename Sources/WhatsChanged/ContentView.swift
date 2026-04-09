import SwiftUI
import AppKit

struct OpenBasePickerKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct OpenComparePickerKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var openBasePicker: Binding<Bool>? {
        get { self[OpenBasePickerKey.self] }
        set { self[OpenBasePickerKey.self] = newValue }
    }
    var openComparePicker: Binding<Bool>? {
        get { self[OpenComparePickerKey.self] }
        set { self[OpenComparePickerKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var basePickerOpen = false
    @State private var comparePickerOpen = false

    var body: some View {
        @Bindable var model = model

        if model.repoPath != nil {
            VStack(spacing: 0) {
                // Toolbar with ref pickers.
                toolbar

                Divider()

                // Diff content.
                Group {
                    if let error = model.error {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                model.loadRefs()
            }
            .focusedSceneValue(\.openBasePicker, $basePickerOpen)
            .focusedSceneValue(\.openComparePicker, $comparePickerOpen)
            .navigationTitle(URL(fileURLWithPath: model.repoPath!).lastPathComponent)
        } else {
            welcomeView
        }
    }

    private var toolbar: some View {
        HStack {
            @Bindable var model = model

            RefPickerView(
                title: model.primaryBranchName,
                refs: model.refs,
                selection: $model.baseRef,
                isPresented: $basePickerOpen
            )

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            RefPickerView(
                title: "Compare ref...",
                refs: model.refs,
                selection: $model.compareRef,
                isPresented: $comparePickerOpen
            )

            Spacer()
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
            .keyboardShortcut("o", modifiers: .command)
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
