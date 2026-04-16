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

## 2026-04-16: Shift+click for multi-line comment ranges instead of drag selection

Needed a way to comment on ranges of lines, not just single lines. Drag gestures in SwiftUI conflict with ScrollView scrolling inside a LazyVStack, and coordinating drag state across independent row views is complex. Shift+click (click to set anchor, shift+click to set range end) is a well-understood interaction pattern that's straightforward to implement with shared state via an observable anchor object.
