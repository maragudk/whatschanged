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

## Step 4: Add PR ref support from forks

### Prompt Context

**Verbatim prompt:** Can it show branches from forks? E.g. this PR in gomponents: https://github.com/maragudk/gomponents/pull/311
**Interpretation:** The user wants to see diffs from pull requests made by external contributors from forks.
**Inferred intent:** Fork branches don't appear as remotes in the local repo. PRs are the main way the user would encounter fork code, so the app should surface them.

### What I did
Added PR ref fetching to `/Sources/WhatsChanged/GitService.swift`. The `getPullRequestRefs()` method runs `git fetch origin '+refs/pull/*/head:refs/pull/*/head'` to download all PR head refs from the remote, then lists them with `git for-each-ref`. Added a `.pullRequest` case to `GitRef.RefType` in `/Sources/WhatsChanged/Models.swift` with display names like `PR #311`. The fetch is best-effort -- errors are silently ignored so the app still works on repos without a remote or non-GitHub remotes.

### Why
GitHub exposes every PR as a fetchable ref at `refs/pull/NUMBER/head`, even from forks. This avoids the need to add fork remotes manually.

### What worked
Clean approach: one fetch command grabs all PR refs, no per-PR logic needed. Display as `PR #311` is immediately recognizable.

### What didn't work
Everything went smoothly on the implementation side.

### What I learned
GitHub stores PR refs at `refs/pull/*/head` (and `refs/pull/*/merge` for the merge commit). These are fetchable from the origin remote without adding the fork as a separate remote.

### What was tricky
Nothing significant. The main design choice was whether to fetch all PRs upfront vs. on demand. Fetching all is simpler and the overhead is acceptable for typical repos.

### What warrants review
- Fetching all PR refs on every refresh could be slow on repos with hundreds of PRs. May need pagination or caching later.
- The fetch modifies the local repo (creates refs under `refs/pull/`). This is standard Git behavior but worth noting for a "read-only" app -- it doesn't modify the working tree or any branches.

### Future work
- Show PR title alongside the number (would require GitHub API calls).
- Consider only fetching open PRs.

## Step 5: Replace auto-refresh with manual refresh button

### Prompt Context

**Verbatim prompt:** Instead of updating on window focus, add a refresh button or something. It's slow every time I switch to it.
**Interpretation:** The automatic ref refresh on window focus is too slow because it fetches PR refs from the remote.
**Inferred intent:** User wants control over when the (slow) remote fetch happens.

### What I did
Removed the `NSApplication.didBecomeActiveNotification` observer from `/Sources/WhatsChanged/ContentView.swift`. Added a refresh button (circular arrow icon) in the toolbar, bound to Cmd+R.

### Why
The PR ref fetch hits the network on every refresh, making the auto-refresh-on-focus noticeably slow. A manual button gives the user control.

### What worked
Simple, clean fix. One notification listener removed, one button added.

### What didn't work
Everything went smoothly.

### What I learned
Network-dependent operations should not be tied to window focus events. The user switches windows frequently and doesn't want to wait each time.

### What was tricky
Nothing.

### What warrants review
Nothing -- straightforward change.

### Future work
- Could separate local ref refresh (fast, could stay automatic) from remote PR fetch (slow, manual only).

## Step 6: Fix CLI argument parsing

### Prompt Context

**Verbatim prompt:** swift run WhatsChanged ../gomponents doesn't work for some reason. Picking in the file picker does.
**Interpretation:** Relative paths passed as CLI arguments aren't resolving correctly.
**Inferred intent:** The user wants `swift run WhatsChanged ../gomponents` to just work.

### What I did
Two issues fixed in `/Sources/WhatsChanged/AppModel.swift`:

1. **Path resolution:** Replaced manual string concatenation (`cwd + "/" + path`) with `URL(fileURLWithPath:relativeTo:).standardizedFileURL` which properly resolves `..` components.

2. **Argument parsing:** `swift run WhatsChanged -- ../gomponents` was passing `--` as `args[1]`. Changed arg parsing from `args[1]` to `args.first(where: { $0 != "--" && !$0.hasPrefix("-") })` to skip flags and separators.

Also fixed stderr capture in `/Sources/WhatsChanged/GitService.swift` -- git errors were showing as blank because stderr was being piped to a `Pipe()` that was never read. Now stderr is read and included in the error message.

Added a `/Makefile` with `make run path=../gomponents`.

### Why
The string-based path concatenation didn't resolve `..` properly, producing paths like `/Users/.../whatschanged/../gomponents` which may or may not work depending on the consumer. And `swift run` injects `--` into the argument list, which the naive `args[1]` parser picked up as the path.

### What worked
`URL.standardizedFileURL` handles all path normalization correctly. The arg filtering is simple and robust.

### What didn't work
The first fix (URL-based path resolution alone) wasn't enough -- the `--` argument issue was a separate bug that only became visible from the screenshot showing `/Users/markus/Developer/whatschanged/--` as the repo path and `git exited with status 128:` as a blank error. The blank error led to also fixing stderr capture.

### What I learned
- `swift run` passes `--` through to the binary as an argument. The `--` separator tells `swift run` to stop parsing its own flags, but the separator itself ends up in the binary's `CommandLine.arguments`.
- Always capture and display stderr from subprocesses. Silent failures are debugging nightmares.

### What was tricky
Debugging remotely without being able to run the app directly. The screenshot was critical -- seeing `/whatschanged/--` in the path label immediately revealed the `--` parsing bug, and the blank error message revealed the missing stderr capture.

### What warrants review
The arg parser is simple but doesn't handle edge cases like `swift run WhatsChanged -- --some-future-flag ../gomponents`. Good enough for now.

### Future work
- Could use Swift ArgumentParser for proper CLI arg handling if more flags are needed later.
