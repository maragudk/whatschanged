# Diary: Build WhatsChanged -- a read-only SwiftUI Mac diff viewer

A native macOS app for viewing code diffs across git branches, worktrees, and remotes. Born from the need to keep tabs on what AI agents are doing across many branches and worktrees in a project. Pure Swift, no dependencies, shells out to git.

## Step 1: Brainstorm and design

### Prompt Context

**Verbatim prompt:** Create a SwiftUI Mac app to view code changes across git branches (also in worktrees) and git remotes. It should be read-only. Let's brainstorm. Ultrathink
**Interpretation:** Design and build a native Mac diff viewer from scratch.
**Inferred intent:** Markus has AI agents creating branches and worktrees everywhere and needs a single GUI to see what they've all changed.

### What I did
Ran a brainstorm session with multiple-choice questions to nail down the design. Arrived at: two dropdown ref pickers at the top (type-to-filter), a single scrollable side-by-side diff view below with file headers. Committed refs only, no write operations, no syntax highlighting. SPM project, no Xcode project, no external dependencies, macOS 26 Tahoe target.

### Why
Getting the design right before writing code avoids rework. The key decisions were: simplicity over features (no sidebar, no file list panel, no search UI), and side-by-side diff with plain diff coloring.

### What worked
The brainstorm format worked well to converge quickly on a focused design.

### What didn't work
Nothing at this stage.

### What I learned
The primary use case is managing the output of AI agents, not general git browsing. This means branch lists could be long and change frequently.

### What was tricky
Nothing at this stage.

### What warrants review
The design decision to not have a file list sidebar -- for very large diffs, scrolling through all files in one view might be unwieldy.

### Future work
- File list sidebar or jump-to-file might be needed once used on real large diffs.

## Step 2: Build the app

### Prompt Context

**Verbatim prompt:** Build it!
**Interpretation:** Implement the full app as designed.
**Inferred intent:** Ship the working v1.

### What I did
Created 8 source files in `/Sources/WhatsChanged/`:

- `/Package.swift` -- SPM config, swift-tools-version 6.2, macOS v26
- `/Sources/WhatsChanged/Models.swift` -- `GitRef`, `FileDiff`, `DiffHunk`, `DiffLine`, `SideBySideRow` (all `Sendable`)
- `/Sources/WhatsChanged/GitService.swift` -- shells out to `git` for branch/remote/worktree listing and diffs
- `/Sources/WhatsChanged/DiffParser.swift` -- parses unified diff format, converts to side-by-side rows with paired deletion/addition alignment
- `/Sources/WhatsChanged/AppModel.swift` -- `@Observable @MainActor` state management
- `/Sources/WhatsChanged/WhatsChangedApp.swift` -- `@main` entry point with window config
- `/Sources/WhatsChanged/ContentView.swift` -- toolbar with pickers, diff area, welcome screen with `NSOpenPanel`
- `/Sources/WhatsChanged/RefPickerView.swift` -- popover-based picker with filter text field
- `/Sources/WhatsChanged/DiffView.swift` -- side-by-side rendering with line numbers, diff coloring, file headers

### Why
Straightforward implementation of the brainstormed design. All boring technology: `Process` for git, `@Observable` for state, standard SwiftUI views.

### What worked
Clean compile on first try with Swift 6.2 strict concurrency. The SPM executable target "just works" as a SwiftUI app.

### What didn't work
Nothing at compile time.

### What I learned
- `macOS(.v26)` requires `swift-tools-version: 6.2` (guarded by `@available(_PackageDescription 6.2)`). The older `.v16` exists but is renamed/unavailable.

### What was tricky
Nothing at this stage -- the initial build was clean.

### What warrants review
The diff parser handles the common unified diff cases but may have edge cases with unusual git diff output (binary files, permission changes, symlinks).

### Future work
None identified yet.

## Step 3: Fix runtime issues

### Prompt Context

**Verbatim prompt:** (Three sequential bug reports from testing)
**Interpretation:** Fix the issues found during manual testing.
**Inferred intent:** Make the app actually usable.

### What I did
Fixed three issues in sequence:

1. **App hidden behind terminal** -- Added `NSApplication.shared.setActivationPolicy(.regular)` and `NSApplication.shared.activate()` in `onAppear` in `/Sources/WhatsChanged/WhatsChangedApp.swift`. SPM-launched SwiftUI apps default to accessory activation policy and don't come to the foreground.

2. **Beachball on ref selection** -- `GitService.runGit()` was called synchronously on `@MainActor` via `loadRefs()`/`loadDiff()`. Moved git operations to `Task.detached` blocks in `/Sources/WhatsChanged/AppModel.swift`, dispatching results back to `MainActor` on completion.

3. **Diff never loads (spinner forever)** -- Classic `Process` pipe deadlock in `/Sources/WhatsChanged/GitService.swift`. Code called `process.waitUntilExit()` before `pipe.fileHandleForReading.readDataToEndOfFile()`. Large diffs fill the pipe buffer, git blocks waiting for the reader, and `waitUntilExit` blocks waiting for git. Swapped the order: read first, then wait.

### Why
All three are standard pitfalls of Mac apps launched from the terminal with subprocess I/O. They're invisible on small outputs but fatal on real-world repos.

### What worked
Each fix was targeted and minimal -- one or two lines each.

### What didn't work
The first attempt at the foreground fix (just `NSApplication.shared.activate()` without setting the activation policy) didn't work. The activation policy needed to be `.regular` first.

### What I learned
- SPM SwiftUI apps launched from the terminal need explicit `.setActivationPolicy(.regular)` to behave as proper GUI apps with dock icons and correct window layering.
- The `Process` pipe deadlock is a classic that bites every time. Always read the pipe before waiting for exit.

### What was tricky
The pipe deadlock was non-obvious from the symptoms (spinner forever). It only manifests on large diffs where the output exceeds the pipe buffer size (~64KB). Small test repos would never trigger it.

### What warrants review
- The `Task.detached` usage works but is blunt. There's no cancellation of in-flight git operations if the user changes the selection quickly. Could lead to stale results arriving after a newer request.

### Future work
- Consider cancelling in-flight diff tasks when the selection changes.
- The activation policy fix works but the app currently has no icon -- it shows the default SwiftUI app icon in the dock.
