import Foundation

struct GitService: Sendable {
    let repoPath: String

    func findRepoRoot() throws -> String {
        let output = try runGit(["rev-parse", "--show-toplevel"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func getRefs() throws -> [GitRef] {
        var refs: [GitRef] = []
        var worktreeBranches: Set<String> = []
        let repoRoot = try findRepoRoot()

        // Get worktrees first to know which branches are checked out as worktrees.
        let worktreeOutput = try runGit(["worktree", "list", "--porcelain"])
        var currentWorktreePath: String?
        for line in worktreeOutput.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                currentWorktreePath = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch refs/heads/") {
                let branch = String(line.dropFirst("branch refs/heads/".count))
                if let path = currentWorktreePath, path != repoRoot {
                    worktreeBranches.insert(branch)
                }
            }
        }

        // Fetch all remotes and PR refs (best-effort).
        _ = try? runGit(["fetch", "--all", "--quiet"])
        // GitHub/GitLab PR refs aren't covered by the default refspec, fetch them separately per remote.
        let remotesOutput = (try? runGit(["remote"])) ?? ""
        for remote in remotesOutput.components(separatedBy: "\n") {
            let name = remote.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            _ = try? runGit(["fetch", name, "+refs/pull/*/head:refs/pull/\(name)/*", "--quiet"])
            _ = try? runGit(["fetch", name, "+refs/merge-requests/*/head:refs/merge-requests/\(name)/*", "--quiet"])
        }

        // All refs sorted by committer date (newest first).
        let format = "%(refname:short)\t%(refname)\t%(committerdate:unix)\t%(subject)"
        let output = try runGit([
            "for-each-ref",
            "--sort=-committerdate",
            "--format=\(format)",
            "refs/heads/",
            "refs/remotes/",
            "refs/pull/",
            "refs/merge-requests/",
        ])

        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 3)
            guard parts.count >= 2 else { continue }
            let shortName = String(parts[0])
            let fullRef = String(parts[1])
            let date = parts.count > 2 ? Date(timeIntervalSince1970: Double(parts[2]) ?? 0) : nil
            let subject = parts.count > 3 ? String(parts[3]) : nil

            if fullRef.hasPrefix("refs/pull/") || fullRef.hasPrefix("refs/merge-requests/") {
                refs.append(GitRef(name: fullRef, type: .pullRequest, worktreePath: nil, date: date, commitSubject: subject))
            } else if fullRef.hasPrefix("refs/remotes/") {
                if shortName.contains("/HEAD") { continue }
                refs.append(GitRef(name: shortName, type: .remote, worktreePath: nil, date: date, commitSubject: subject))
            } else if worktreeBranches.contains(shortName) {
                // Look up the worktree path for this branch.
                var wtPath: String?
                var currentPath: String?
                for wtLine in worktreeOutput.components(separatedBy: "\n") {
                    if wtLine.hasPrefix("worktree ") {
                        currentPath = String(wtLine.dropFirst("worktree ".count))
                    } else if wtLine == "branch refs/heads/\(shortName)" {
                        wtPath = currentPath
                    }
                }
                refs.append(GitRef(name: shortName, type: .worktree, worktreePath: wtPath, date: date, commitSubject: subject))
            } else {
                refs.append(GitRef(name: shortName, type: .local, worktreePath: nil, date: date, commitSubject: subject))
            }
        }

        return refs
    }

    func getDiff(base: String, compare: String) throws -> String {
        return try runGit(["diff", "--no-color", "-M", base, compare])
    }

    func primaryBranch() throws -> String {
        // Try main, then master, then fall back to HEAD.
        for candidate in ["main", "master"] {
            let result = try? runGit(["rev-parse", "--verify", candidate])
            if result != nil {
                return candidate
            }
        }
        return "HEAD"
    }

    private func runGit(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath] + args
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = stderrPipe

        try process.run()

        // Read before waiting -- otherwise large output fills the pipe buffer
        // and git blocks, deadlocking with waitUntilExit().
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else {
            throw GitError.invalidOutput
        }

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw GitError.commandFailed(status: process.terminationStatus, output: stderr.isEmpty ? output : stderr)
        }

        return output
    }
}

enum GitError: Error, LocalizedError {
    case invalidOutput
    case commandFailed(status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .invalidOutput:
            return "Failed to read git output"
        case .commandFailed(let status, let output):
            return "git exited with status \(status): \(output)"
        }
    }
}
