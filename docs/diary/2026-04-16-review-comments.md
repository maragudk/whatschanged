# Diary: Add review comments feature

Add the ability to annotate lines in the diff with review comments that get written to a JSONL file for consumption by AI agents.

## Step 1: Brainstorm and design

### Prompt Context

**Verbatim prompt:** "Is there any built-in mechanism in Git to create line-level comments on the code that is committed?"
**Interpretation:** The user wants to add code review annotations to WhatsChanged.
**Inferred intent:** Build a feedback loop from WhatsChanged back to AI coding agents -- review the agent's diff, leave comments, and have the agent act on them.

### What I did
Brainstormed the feature through a series of questions covering data format, UI interaction, comment lifecycle, and the agent contract. Landed on:
- `review.jsonl` at repo root, one JSON object per line
- Click compare-side line number to open a popover
- Cmd+Enter to save, Escape to cancel
- File committed to git for history; agent removes lines as addressed

### Why
Needed to nail down the design before writing code -- several non-obvious decisions (SHAs vs ref names, JSONL vs JSON, click vs drag for ranges).

### What worked
Multiple-choice questions moved the brainstorm quickly. The user had clear opinions on most choices.

### What didn't work
Nothing at this stage.

### What I learned
The user wants this as a machine interface, not a human one. That simplifies the data format significantly -- no need for threading, resolution status, or rich formatting.

### What was tricky
Nothing significant.

### What warrants review
The spec update at `/docs/spec.md` captures the feature design. The non-goals section was updated to reflect that the app now writes one file.

### Future work
An agent skill to consume `review.jsonl` -- filed as maragudk/fabrik#10.

## Step 2: Implement core data model and services

### Prompt Context

**Verbatim prompt:** "Yes" (to "Does that look like the complete picture? Want me to update the spec and start building?")
**Interpretation:** Build the feature as designed.
**Inferred intent:** Ship the full feature in one session.

### What I did
- Added `ReviewComment` struct to `/Sources/WhatsChanged/Models.swift` with `file`, `startLine`, `endLine`, `comment`, `base`, `compare` fields. Conforms to `Codable`, `Identifiable`, `Sendable`.
- Added `resolveRef()` to `/Sources/WhatsChanged/GitService.swift` for SHA resolution via `git rev-parse`.
- Added `commitFile()` to `GitService` for staging and committing `review.jsonl`.
- Created `/Sources/WhatsChanged/ReviewService.swift` with `load()`, `append()`, `update()`, `delete()`, and `writeAll()` methods.
- Wired everything into `/Sources/WhatsChanged/AppModel.swift`: `reviewComments` array, `baseSHA`/`compareSHA` tracking, `repoRoot` resolution, CRUD methods, and `commitReviewComments()`.

### Why
The data layer and services needed to be in place before the UI work.

### What worked
Clean separation: `ReviewService` handles file I/O, `AppModel` handles state, `GitService` handles git operations. Each is independently testable.

### What didn't work
Nothing -- straightforward implementation.

### What I learned
`JSONEncoder` escapes forward slashes by default, producing `handlers\/case.go` in the JSONL output. Fixed with `.withoutEscapingSlashes` output formatting option.

### What was tricky
Nothing significant.

### What warrants review
The `ReviewService` silently swallows errors via `try?` in `AppModel`. This is intentional for now (review comments are non-critical) but could mask issues.

### Future work
None.

## Step 3: Build the comment popover UI

### Prompt Context

**Verbatim prompt:** (continuation of build)
**Interpretation:** Implement the UI for adding, editing, and deleting review comments.
**Inferred intent:** Complete the user-facing part of the feature.

### What I did
- Modified `/Sources/WhatsChanged/DiffView.swift` extensively:
  - Added `CommentAnchor` observable class for shift+click range selection state
  - Updated `SideBySideRowView` with popover, tap gesture, hover highlight, and pointer cursor on compare-side line numbers
  - Added `CommentPopoverView` with text editor, save (Cmd+Enter), delete, and cancel (Escape) actions
  - Added blue rectangle gutter indicator for commented lines (fills row height, merges into continuous bar for ranges)
- Added `CommentAnchor` at `DiffView` level, passed to each row
- Added Cmd+S menu item in `/Sources/WhatsChanged/WhatsChangedApp.swift` to commit `review.jsonl`
- Added loading spinner to toolbar in `/Sources/WhatsChanged/ContentView.swift`
- Added `isLoading` flag with reference counting in `AppModel`

### Why
The UI needed to feel lightweight -- popover anchored to the line number, no modals or sidebars.

### What worked
- The popover-on-line-number approach is clean and doesn't disrupt the diff layout
- Rectangle indicators that merge into a bar for ranges look good
- Reference-counted loading state handles overlapping `loadRefs`/`loadDiff` correctly

### What didn't work
- **Popover not appearing on click**: The popover was attached to the line number `Text` but the `onTapGesture` was on the parent `HStack`. SwiftUI didn't immediately invalidate the child view when the parent's state changed. The popover only appeared when moving the mouse (which triggered `onHover` and forced a re-render). Fixed by moving the tap gesture to the same view as the popover.
- **"Line 0" in popover**: `@State` variables `popoverStartLine`/`popoverEndLine` initialized to `0`. Added a guard in the display label, though the exact race condition that causes this wasn't fully identified.
- **Excessive dots for multi-line comments**: Initially showed a blue dot on every line in a range. Changed to a rectangle that fills the row height, so multi-line ranges render as a continuous vertical bar.
- **Slash escaping**: `handlers\/case.go` in JSONL output. Fixed with `.withoutEscapingSlashes`.

### What I learned
In SwiftUI, when a popover is attached to a child view but the state trigger (`isPresented`) is modified by a gesture on a parent view, the popover may not appear until the child view is independently invalidated. Keep the gesture and popover on the same view.

### What was tricky
The shift+click range selection required shared mutable state (`CommentAnchor`) across independent row views in a `LazyVStack`. An `@Observable` class owned by `DiffView` and passed as a parameter worked well. Using `@State` wouldn't work because each row has its own state.

### What warrants review
- The popover anchoring and tap gesture placement in `DiffView.swift` -- the fix for the delayed popover is worth verifying works reliably
- The "Line 0" edge case -- the guard hides it but the root cause isn't identified
- The `commitReviewComments()` method commits silently with no success feedback to the user

### Future work
- Agent skill to consume `review.jsonl` (maragudk/fabrik#10)
- Success/failure feedback after Cmd+S commit
- Consider whether the commit message should include which files were commented on
