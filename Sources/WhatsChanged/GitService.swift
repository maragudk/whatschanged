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

        // Get worktrees first to know which branches are checked out as worktrees.
        let worktreeOutput = try runGit(["worktree", "list", "--porcelain"])
        var currentWorktreePath: String?
        for line in worktreeOutput.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                currentWorktreePath = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("branch refs/heads/") {
                let branch = String(line.dropFirst("branch refs/heads/".count))
                if let path = currentWorktreePath {
                    // Skip the main worktree (the repo root itself).
                    let repoRoot = try findRepoRoot()
                    if path != repoRoot {
                        worktreeBranches.insert(branch)
                        refs.append(GitRef(
                            name: branch,
                            type: .worktree,
                            worktreePath: path
                        ))
                    }
                }
            }
        }

        // Local branches (skip those already listed as worktrees).
        let localOutput = try runGit(["branch", "--format=%(refname:short)"])
        for line in localOutput.components(separatedBy: "\n") {
            let name = line.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !worktreeBranches.contains(name) {
                refs.append(GitRef(name: name, type: .local, worktreePath: nil))
            }
        }

        // Remote branches.
        let remoteOutput = try runGit(["branch", "-r", "--format=%(refname:short)"])
        for line in remoteOutput.components(separatedBy: "\n") {
            let name = line.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !name.contains("/HEAD") {
                refs.append(GitRef(name: name, type: .remote, worktreePath: nil))
            }
        }

        // Pull request refs (fetched from remote, best-effort).
        let prRefs = (try? getPullRequestRefs()) ?? []
        refs.append(contentsOf: prRefs)

        return refs
    }

    /// Fetch PR refs from origin and return them as GitRefs.
    func getPullRequestRefs() throws -> [GitRef] {
        // Fetch all PR head refs from origin into local refs.
        _ = try? runGit(["fetch", "origin", "+refs/pull/*/head:refs/pull/*/head", "--quiet"])

        // List the fetched PR refs.
        let output = try runGit(["for-each-ref", "--format=%(refname)", "refs/pull/"])
        var refs: [GitRef] = []
        for line in output.components(separatedBy: "\n") {
            let refname = line.trimmingCharacters(in: .whitespaces)
            // Refs look like "refs/pull/311/head".
            guard refname.hasPrefix("refs/pull/") && refname.hasSuffix("/head") else {
                continue
            }
            refs.append(GitRef(
                name: refname,
                type: .pullRequest,
                worktreePath: nil
            ))
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
