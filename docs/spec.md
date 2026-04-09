# WhatsChanged

## Objective

WhatsChanged is a read-only native macOS app for viewing side-by-side code diffs across git branches, worktrees, and remotes in a single repository. It solves the problem of keeping track of what AI coding agents (and humans) have changed across many branches and worktrees, without switching contexts in the terminal or running `git diff` twenty times.

## Users

A single user type: a developer who uses AI coding agents that create branches and worktrees autonomously. They need a quick visual overview of what changed on any given branch compared to any other ref, without leaving their workflow to piece it together from CLI output.

## Features

### Repository access

- Open a repository via command-line argument (`whatschanged /path/to/repo`) or a folder picker in the app.
- The app resolves worktree paths back to the main repository automatically.

### Ref selection

- Two dropdown selects at the top of the window: base ref (left) and compare ref (right).
- Dropdowns list all local branches, remote-tracking branches, and worktree-associated branches (labeled as such).
- Typing while a dropdown is open filters the list by substring match.
- Base ref defaults to the repository's primary branch (main or master).

### Diff view

- A single scrollable side-by-side diff of all changed files between the two selected refs.
- Files are separated by header bars showing the file path and +/- line counts.
- Left column shows the base version, right column shows the compare version.
- Changed lines are highlighted with diff coloring: green for additions, red for deletions, yellow for modifications.
- Line numbers displayed on both sides.
- Binary files show a "binary file changed" message instead of a diff.

### Freshness

- The ref list refreshes automatically when the app window regains focus, picking up new branches created by agents in the background.

## Non-goals

- **Git mutations.** No commit, push, merge, checkout, or any write operation. This is strictly a viewer.
- **Uncommitted changes.** Only committed refs are diffable. Working tree and staged changes are not shown.
- **Syntax highlighting.** Diff coloring only, no language-aware highlighting.
- **Commit history.** No log view, no branch graph, no timeline.
- **Multi-repo.** One repository at a time.
- **iOS/iPad.** macOS only.

## Constraints

- macOS 26 (Tahoe) minimum deployment target.
- Pure Swift and SwiftUI. No external dependencies.
- Swift Package Manager project -- no Xcode project file. Must build with `swift build`.
- Shells out to the system `git` binary. No libgit2 or other git library.

## Success criteria

- A developer can point the app at a repo with 20+ agent-created branches and quickly see what any branch changed, without touching the terminal.
- Selecting two refs and seeing the diff feels immediate on typical-sized diffs (a few hundred lines across a handful of files).
- The app stays responsive while loading large diffs.

## Open questions

- **File navigation for large diffs.** When a diff spans many files, scrolling through all of them linearly may be slow. A file list sidebar or jump-to-file feature might be needed. Deferred until real-world usage reveals whether it's a problem.
- **Cancellation of in-flight diffs.** If the user changes ref selection while a large diff is loading, the old request isn't cancelled. Could lead to stale results briefly appearing. Worth addressing if it causes confusion.
