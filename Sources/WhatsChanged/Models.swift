import Foundation

struct GitRef: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let type: RefType
    let worktreePath: String?
    let date: Date?
    let commitSubject: String?

    enum RefType: String, Sendable {
        case local
        case remote
        case worktree
        case pullRequest
    }

    var displayName: String {
        switch type {
        case .local:
            return name
        case .remote:
            return name
        case .worktree:
            return "\(name) (worktree)"
        case .pullRequest:
            if name.hasPrefix("refs/merge-requests/") {
                // "refs/merge-requests/origin/123" -> "MR #123 (origin)"
                let stripped = name.replacingOccurrences(of: "refs/merge-requests/", with: "")
                let parts = stripped.split(separator: "/", maxSplits: 1)
                if parts.count == 2 {
                    return "MR #\(parts[1]) (\(parts[0]))"
                }
                return "MR \(stripped)"
            }
            // "refs/pull/origin/311" or "refs/pull/311/head" -> "PR #311"
            let stripped = name
                .replacingOccurrences(of: "refs/pull/", with: "")
                .replacingOccurrences(of: "/head", with: "")
            let parts = stripped.split(separator: "/")
            let number = parts.last.map(String.init) ?? stripped
            if parts.count == 2 {
                return "PR #\(parts[1]) (\(parts[0]))"
            }
            return "PR #\(number)"
        }
    }
}

struct FileDiff: Identifiable, Sendable {
    let id = UUID()
    let oldPath: String
    let newPath: String
    let hunks: [DiffHunk]
    let isBinary: Bool

    var additions: Int {
        hunks.reduce(0) { sum, hunk in
            sum + hunk.lines.filter { $0.type == .addition }.count
        }
    }

    var deletions: Int {
        hunks.reduce(0) { sum, hunk in
            sum + hunk.lines.filter { $0.type == .deletion }.count
        }
    }

    var displayPath: String {
        if oldPath == newPath || oldPath == "/dev/null" {
            return newPath
        } else if newPath == "/dev/null" {
            return oldPath
        } else {
            return "\(oldPath) -> \(newPath)"
        }
    }
}

struct DiffHunk: Identifiable, Sendable {
    let id = UUID()
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let header: String
    let lines: [DiffLine]
}

struct DiffLine: Identifiable, Sendable {
    let id = UUID()
    let type: LineType
    let content: String

    enum LineType: Sendable {
        case context
        case addition
        case deletion
    }
}

struct SideBySideRow: Identifiable, Sendable {
    let id = UUID()
    let left: Side?
    let right: Side?

    struct Side: Sendable {
        let lineNumber: Int
        let content: String
        let type: SideType
    }

    enum SideType: Sendable {
        case context
        case addition
        case deletion
        case modified
    }
}
