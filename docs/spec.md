# WhatsChanged

## Objective

WhatsChanged is a native macOS app for viewing side-by-side code diffs and leaving review comments across git branches, worktrees, remotes, and pull requests (GitHub and GitLab, including from forks) in a single repository. It solves the problem of keeping track of what AI coding agents (and humans) have changed across many branches and worktrees, without switching contexts in the terminal or running `git diff` twenty times.

## Users

A single user type: a developer who uses AI coding agents that create branches and worktrees autonomously. They need a quick visual overview of what changed on any given branch compared to any other ref, without leaving their workflow to piece it together from CLI output.

## Features

### Repository access

- Open a repository via command-line argument (`whatschanged /path/to/repo`), Cmd+O, or a folder picker on the welcome screen.
- The app resolves worktree paths back to the main repository automatically.
- Window title reads "What's Changed in \<dir\>?"

### Ref selection

- Two dropdown selects at the top of the window: base ref (left) and compare ref (right). Keyboard shortcuts: Cmd+K for base, Cmd+L for compare.
- Dropdowns list all local branches, remote-tracking branches, worktree-associated branches, GitHub PR refs, and GitLab MR refs -- all sorted by commit date, newest first.
- Each ref shows its name and the first line of its latest commit message.
- Typing while a dropdown is open filters the list by substring match. Arrow keys navigate, Enter selects, Escape closes.
- Base ref defaults to the repository's primary branch (main or master).

### Diff view

- A single scrollable side-by-side diff of all changed files between the two selected refs.
- File sections are collapsible by clicking the file header. Collapsed state persists across refreshes. A chevron and pointer cursor indicate clickability.
- File headers have a pink background and show the file path and +/- line counts.
- Left column shows the base version, right column shows the compare version.
- Changed lines are highlighted with diff coloring: green for additions, red for deletions, yellow for modifications.
- Modified lines show inline word-level diff highlighting: the specific characters that changed are highlighted with a stronger color within the line background.
- Long lines soft-wrap naturally within each column.
- Line numbers displayed on both sides.
- A continuous vertical divider separates the two columns.
- Gaps between hunks within a file are indicated by a centered "···" separator with a subtle background.
- Binary files show a "binary file changed" message instead of a diff.
- Prefers the MonoLisa font if installed, falls back to the system monospaced font.

### Review comments

- Clicking a line number on the compare side (right column) opens a popover anchored to the line number with a text field for adding a review comment. The line number shows a pointer cursor and subtle highlight on hover.
- For multi-line comments: click a line number to set an anchor, then shift+click another line number to select a range.
- Cmd+Enter saves the comment. Escape cancels without saving.
- Comments are appended immediately to `review.jsonl` at the repository root, one JSON object per line: `{"file": "...", "startLine": 42, "endLine": 45, "comment": "...", "base": "<sha>", "compare": "<sha>"}`.
- `startLine` and `endLine` refer to compare-side line numbers (equal for single-line comments). `base` and `compare` are the resolved commit SHAs of the current comparison.
- Lines with existing comments show a blue vertical bar in the gutter. For multi-line comments, the bars merge into a continuous stripe.
- Clicking a commented line's number opens the same popover pre-filled, allowing editing (Cmd+Enter to save) or deletion.
- `review.jsonl` is loaded on app start and on refresh. Comments are matched to lines in the current diff by file path, line number, and SHA.
- Cmd+S commits `review.jsonl` to git (including deletions when all comments have been removed). Committing is refused on main/master with an alert dialog.
- The file is intended to be committed to git. An external agent reads and removes comments as it addresses them; when the file is empty, the agent deletes it.

### Branch operations

- Cmd+B checks out the compare ref as a local branch. For remote branches (e.g. `origin/feature-x`), the remote prefix is stripped and a local tracking branch is created. PR/MR refs cannot be checked out directly; an alert is shown.
- Cmd+P pulls the current branch from its configured upstream.
- Pull default branch: fetches all remotes and fast-forwards the default branch (main/master) to its upstream without checking it out. Available via command palette (no keyboard shortcut).
- The current branch name is displayed in the toolbar between the ref pickers and the loading spinner.

### Freshness

- The ref list and current diff refresh on demand via Cmd+R.
- Refresh fetches all remotes (`git fetch --all`), plus PR/MR refs from each remote.
- A spinner appears in the toolbar while refs or diffs are loading.

## Non-goals

- **Broad git mutations.** The app only performs targeted git operations: committing `review.jsonl` (Cmd+S), checking out branches (Cmd+B), and pulling (Cmd+P / command palette). No push, merge, rebase, or destructive operations.
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

- **First-collapse latency on large files.** Collapsing a file with 700+ changed lines takes ~1s the first time due to SwiftUI measuring variable-height rows. Subsequent collapses are instant. An NSTableView-based approach or Canvas rendering could eliminate this.
- **File navigation for large diffs.** When a diff spans many files, scrolling through all of them linearly may be slow. A file list sidebar or jump-to-file feature might be needed.
- **Cancellation of in-flight diffs.** If the user changes ref selection while a large diff is loading, the old request isn't cancelled. Could lead to stale results briefly appearing.
- **Standalone binary.** The app only launches correctly via `swift run`, not as a standalone binary. This appears to be a macOS window server issue with bare SwiftUI executables. Currently worked around with a shell wrapper script.
