# Project Decisions

This document records significant architectural and design decisions made throughout the project's development.

## 2026-04-16: Use a JSONL file as the review comment interface between WhatsChanged and AI agents

WhatsChanged needed a mechanism to pass line-level code review comments to an AI agent. Several options were considered:

Alternatives considered:
- **git notes**: Built-in to git, but commit-level only (not line-level), not shared by default, and orphaned by rebases. No threading or resolution support.
- **Platform-level comments** (GitHub PR reviews, etc.): Purpose-built for review, but ties the workflow to a specific platform and isn't agent-friendly for programmatic consumption.
- **A simple file in the repo**: Machine-readable, version-controlled via git, no dependencies on external systems.

Decision: Write review comments to `review.jsonl` at the repository root. Each line is a self-contained JSON object with file path, line range, comment text, and base/compare commit SHAs. The file is committed to git for history, and the agent deletes lines as it addresses them.

Tradeoffs: This approach has no built-in threading, resolution status, or notifications. But since the consumer is an AI agent with full tooling access, those features aren't needed -- the agent reads the file, looks up the code, and acts on it. The git history provides the audit trail.

## 2026-04-16: Commit SHAs instead of ref names in review comments

Review comments store the resolved commit SHAs rather than symbolic ref names (branch names). Ref names are mutable -- a branch can point to a different commit after a force push or new commit. SHAs are immutable and uniquely identify the exact code that was reviewed, regardless of how branches have moved since.

## 2026-04-16: Auto-checkout on compare ref selection instead of separate Cmd+B

Initially had a separate Cmd+B shortcut to check out the compare branch. This was an extra step in the review workflow — select a ref, see the diff, then remember to press Cmd+B before leaving comments. Since review comments are committed to the checked-out branch, you always need to be on it.

Simplified to: selecting a compare ref automatically checks out the branch and pulls latest. Startup defaults the compare ref to the current branch without checkout/pull. This removes a command and makes the common flow (select branch, review, comment, commit) seamless.

## 2026-04-16: Use gh/glab CLI for PR/MR checkout instead of manual branch creation

Initially created local branches like `pr-311` from PR refs using `git checkout -b pr-311 refs/pull/origin/311`. This worked for viewing code but pushing didn't update the PR — it created a new `pr-311` branch on the remote instead. The PR ref is a read-only reference, not connected to the PR's source branch.

Switched to `gh pr checkout` (GitHub) and `glab mr checkout` (GitLab), which check out the PR's actual source branch with proper upstream tracking. This adds external tool dependencies but correctly handles the push-updates-the-PR workflow, including forks.

## 2026-04-16: Two-phase ref loading for instant startup

On startup, the app now shows local refs and the diff immediately (no network), then fetches remotes in the background and updates the ref list when done. Previously, the entire `getRefs` call blocked on `git fetch --all` before showing anything.

This means the initial view may be missing new remote branches or PRs, but the diff for local branches appears instantly. The tradeoff favors perceived performance since the user typically wants to see their current branch's diff right away.

## 2026-04-16: Shift+click for multi-line comment ranges instead of drag selection

Needed a way to comment on ranges of lines, not just single lines. Drag gestures in SwiftUI conflict with ScrollView scrolling inside a LazyVStack, and coordinating drag state across independent row views is complex. Shift+click (click to set anchor, shift+click to set range end) is a well-understood interaction pattern that's straightforward to implement with shared state via an observable anchor object.
