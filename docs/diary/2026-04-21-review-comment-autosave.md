# Diary: Review comment popover — stop losing work, drop manual save

Make the review comment popover resilient to app focus changes, bigger, and auto-save its contents so nothing is ever silently lost. Along the way, retire the Save button since auto-save covers it.

## Step 1: First attempt — custom NSPopover wrapper

### Prompt Context

**Verbatim prompt:** "When writing review comments, I observe two different problems, but they are related:
1. When switching focus to a different window, the little window to write the review comment in disappears, and any changes in it are lost.
2. The window to write comments in is much too small.

I'd like to change the feature so that any changes written in are saved automatically on, let's say, focus change or something like that. We don't have to press Command+Enter (whatever the shortcut is to save it), but it should still be possible to cancel with the escape key, so that changes don't get written.

Also, the window shouldn't disappear on focus change, and it should be bigger so I can see more text."

**Interpretation:** Two related issues with the comment popover at `/Sources/WhatsChanged/DiffView.swift`: (a) it auto-dismisses when the app loses focus and loses unsaved text, and (b) the editor is too cramped. The user wants auto-save (replacing the Cmd+Enter commit), escape-to-cancel preserved, the popover to persist across focus changes, and more vertical room.

**Inferred intent:** Eliminate the "lost my comment" failure mode. Treat comment entry as ephemeral text that should always end up in `review.jsonl` unless explicitly cancelled.

### What I did
Replaced SwiftUI's `.popover(...)` on the compare-side line number with a custom `SemitransientPopover` `NSViewRepresentable` wrapping `NSPopover` with `behavior = .semitransient` — which per Apple's docs stays open across app deactivation. Grew the editor to 500×220. Added a `didFinish` `@State` flag and an `onDisappear` auto-save path in `CommentPopoverView`: Escape/Save/Delete set `didFinish = true` to suppress the auto-save; any other dismissal triggers `saveIfChanged()`. Dropped the Cmd+Enter footer hint's status as the primary mechanism and added "Auto-saves on close · Esc to cancel". Moved the preferred edge from `.leading` (`.minX`) to `.maxY` on the theory that a bigger popover below the line reads better.

Swift 6 strict concurrency objected — `NSView`, `NSPopover`, and `NSHostingController` are all `@MainActor`-isolated. Marked `Coordinator` as `@MainActor`, shuttled `popoverDidClose` through a dispatched `MainActor.assumeIsolated` closure to update the binding without tripping the data-race checker.

### Why
The original SwiftUI `.popover` uses `NSPopover.transient` under the hood and auto-dismisses on app deactivation, which is what lost the text. `.semitransient` seemed like the right behavior. Building a custom wrapper also let us keep a single binding-driven API consistent with the rest of the view.

### What worked
The compile issues around concurrency were mechanical once I marked the `Coordinator` `@MainActor`. The auto-save flow with `didFinish` cleanly distinguishes between dismissal reasons.

### What didn't work
First build failed with:

```
Sending value of non-Sendable type 'AnyView' risks causing data races [sending-risks-data-race]
Main actor-isolated property 'window' can not be referenced from a nonisolated context
Main actor-isolated property 'rootView' can not be mutated from a nonisolated context
```

Fixed by hoisting `Coordinator` to `@MainActor`. The `@preconcurrency` annotation I tried on the `NSPopoverDelegate` conformance was a warning-only no-op in this SDK:

```
'@preconcurrency' on conformance to 'NSPopoverDelegate' has no effect
```

Dropped it.

### What I learned
NSPopover has three behaviors — `.transient`, `.semitransient`, `.applicationDefined` — and SwiftUI's `.popover()` gives you none of them except the `.transient` default. To change it you either wrap `NSPopover` yourself or intercept via `NSPopover.willShowNotification`.

`NSHostingController<AnyView>` + `@MainActor Coordinator` is the minimum friction path for bridging a non-Sendable SwiftUI view into AppKit in Swift 6.2.

### What was tricky
The auto-save/cancel semantics are stateful: `didFinish` is set by Escape, Save, Delete, and (in later steps) the willResignActive observer. Every new entry point has to remember to flip it or the `onDisappear` path duplicates the save.

### What warrants review
The Swift 6 concurrency dance in `Coordinator` — the delegate callback dispatches into `MainActor.assumeIsolated` to update the binding. Correct but subtle.

### Future work
None at this step — deferred to user feedback.

## Step 2: Revert, discover `.semitransient` is a lie in this context, simplify

### Prompt Context

**Verbatim prompt (first follow-up):** "Works great. Revert the placement change. Also save when the app loses focus."

**Verbatim prompt (second):** "Hmm, I didn't think that through. Revert the save on app focus loss. Also, the window isn't aligned properly."

**Verbatim prompt (third):** "Nope, same issue with position." (with screenshot showing the popover's arrow pointing roughly 150px to the right of the target line number)

**Verbatim prompt (fourth):** "Actually, the popover still disappears when the app loses focus, including for the ref pickers. I think that's fine."

**Interpretation:** The custom wrapper positioned the arrow incorrectly — the NSView anchor had no intrinsic size and was being placed as a zero-sized element at the center of the line number Text, so NSPopover's positioning rect was degenerate. The user accepted that the popover dismisses on focus change and is more concerned with the save actually happening.

**Inferred intent:** Get the visual back to the SwiftUI-native baseline; stop trying to suppress dismissal.

### What I did
Reverted the preferred edge to `.minX`. Tried to fix the custom wrapper's sizing by forcing `.frame(maxWidth: .infinity, maxHeight: .infinity)` on the `NSViewRepresentable` inside the `.background`. That didn't help — screenshot still showed the arrow far to the right of the line number.

Abandoned the custom wrapper entirely. Restored the original SwiftUI `.popover(isPresented:arrowEdge:)` modifier at `/Sources/WhatsChanged/DiffView.swift`. Deleted the `SemitransientPopover` struct. Installed a global `NSPopover.willShowNotification` observer in `/Sources/WhatsChanged/WhatsChangedApp.swift` that flips every popover's behavior to `.semitransient` via `.onReceive`. When the user confirmed the popover still dismisses on focus loss — meaning SwiftUI's dismissal logic overrides `NSPopover.behavior` anyway — removed the observer too.

### Why
The reliable positioning was in SwiftUI's native popover. Fighting it with a hand-rolled NSViewRepresentable cost more than the `.semitransient` behavior was worth. Since SwiftUI dismisses popovers on app deactivation regardless of `NSPopover.behavior`, the observer was dead code.

### What worked
Reverting to `.popover(...)` restored correct positioning immediately. The user's screenshot confirmed the first-stage placement issue was gone.

### What didn't work
`.frame(maxWidth: .infinity, maxHeight: .infinity)` on the anchor `NSViewRepresentable` did not fix positioning. I still don't have a definitive explanation for why the anchor ended up so far right — likely because `.background { ... }` with a ViewBuilder wraps the content in a container whose intrinsic layout interaction with `NSViewRepresentable` (no intrinsic content size) doesn't behave as I expected. Not worth chasing further since we abandoned the approach.

The global `NSPopover.willShowNotification` observer compiled and fired, but user-observed behavior was unchanged. SwiftUI's `.popover` internally dismisses on app deactivation independent of the underlying `NSPopover.behavior`.

### What I learned
Do not reach for a custom NSViewRepresentable when SwiftUI's built-in already gives you 90% of what you want. The 10% you're chasing may not be achievable anyway — in this case, `NSPopover.behavior` is not the control surface for SwiftUI-popover dismissal.

Also: observer-based `NSPopover` behavior overrides feel clever but buy nothing if SwiftUI is the one deciding when to close.

### What was tricky
Diagnosing the positioning issue without being able to introspect the live view. Screenshots got me part of the way but I could not reliably correlate pixel positions to the view's actual frame. Ended the investigation by accepting the native popover behavior.

### What warrants review
None — this step is a net-negative diff relative to step 1. Just deleted code.

### Future work
None.

## Step 3: Save-on-focus-loss with idempotent callbacks

### Prompt Context

**Verbatim prompt:** "One small detail: the auto-save actually only works when the app gains focus again, not when it loses focus. That means if I write a comment, the app loses focus, nothing is written yet, and I go back to the app. Only then is it auto-saved."

**Interpretation:** SwiftUI dismisses the popover visually on app deactivation but defers the actual view teardown — so `onDisappear` (and therefore the auto-save) doesn't fire until the app is active again. The user wants the save to happen *at* the moment of focus loss so the comment survives even if they never return (crash, long delay, closing laptop, etc.).

**Inferred intent:** Persist work at the earliest safe moment, not the latest.

### What I did
Added an `.onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification))` to `CommentPopoverView` at `/Sources/WhatsChanged/DiffView.swift`, guarded by `didFinish` so Escape/Save/Delete still suppress it.

The wrinkle: because `onDisappear` also fires when the app later regains focus, the save could run twice. In the new-comment case, the second call would duplicate the comment because the `onSave` closure captured `existingComment` at CommentPopoverView's init time (nil), so it would `model.addReviewComment(...)` both times.

Fixed by making `onSave` look up the existing comment *fresh from the model* at call time rather than relying on the captured `existingComment`:

```swift
onSave: { text in
    if let existing = model.reviewComment(forFile: filePath, line: popoverStartLine) {
        guard existing.comment != text else { return }
        var updated = existing
        updated.comment = text
        model.updateReviewComment(updated)
    } else {
        model.addReviewComment(file: filePath, startLine: popoverStartLine, endLine: popoverEndLine, comment: text)
    }
}
```

First save adds; second save finds the just-added comment and either skips (if unchanged) or updates (if the user edited more between focus loss and final dismissal).

Dropped the now-redundant `existing.comment == trimmed` check from `saveIfChanged` since idempotency now lives in the closure.

### Why
Without the willResignActive observer, a user who writes a comment and closes the laptop loses it until they reopen and the popover is torn down. With it, the save happens at the earliest moment SwiftUI tells us the app is going away.

The fresh-lookup pattern is cleaner than adding a "have I saved yet" flag: the model is the source of truth, and the closure consults it every time.

### What worked
The user confirmed the save now fires at focus loss, not on return. Idempotency held — no duplicate comments in `review.jsonl` across multiple focus-loss/focus-gain cycles.

### What didn't work
Nothing in this step.

### What I learned
SwiftUI defers `onDisappear` for dismissed-but-still-in-memory popovers until the app regains focus. If you need "at-loss" semantics, wire up `willResignActiveNotification` directly — do not rely on `onDisappear` alone.

Closure-captured state goes stale as the model changes. For idempotent operations, prefer fresh model lookups inside the callback over capturing derived state at view-init time.

### What was tricky
Reasoning about the interleaving of: (a) user types, (b) willResignActive fires, (c) SwiftUI visual dismissal, (d) app regains focus, (e) actual view teardown and onDisappear. Each path needs the right guard, and each save callback needs to be idempotent against whatever earlier paths have already done.

### What warrants review
The `didFinish` gating on `onReceive(willResignActive)` — if a future refactor adds a new "done" path (e.g., a confirm button), it needs to flip `didFinish` or it'll double-save.

### Future work
None.

## Step 4: Drop the Save button, update the spec

### Prompt Context

**Verbatim prompt (first):** "Works great now. Get rid of the save button."

**Verbatim prompt (second, after offering to update spec):** "yes"

**Interpretation:** With auto-save fully covering both dismissal and focus-loss paths, the explicit Save button is redundant UI. Also, `/docs/spec.md` still documents Cmd+Enter as the save mechanism, which no longer matches reality.

**Inferred intent:** Simplify. The popover has one way to save (close it) and one way to not save (Esc).

### What I did
Removed the `Button("Save")` and its `.keyboardShortcut(.return, modifiers: .command)`, deleted the unused `save()` helper, and updated the footer text from "Auto-saves on close · Esc to cancel" to "Auto-saves · Esc to cancel" at `/Sources/WhatsChanged/DiffView.swift`. Updated `/docs/spec.md` in two places — the Review Comments bullet about Cmd+Enter/Escape, and the "Clicking a commented line's number opens the same popover pre-filled" bullet that also referenced Cmd+Enter.

### Why
With auto-save reliable, the Save button was a false second path — same outcome as closing the popover, but discoverable as a separate action. Removing it narrows the mental model: one way in, one way out (with Esc as the opt-out).

### What worked
Straightforward removal. Build clean. Spec updated in both spots.

### What didn't work
Nothing.

### What I learned
Nothing notable — mechanical cleanup once the behavior stabilized.

### What was tricky
Nothing.

### What warrants review
The spec diff at `/docs/spec.md` captures the new contract. Worth confirming both bullets (main description and the edit-existing bullet) read consistently.

### Future work
None.
