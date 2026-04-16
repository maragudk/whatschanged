import Foundation

struct GitService: Sendable {
    let repoPath: String

    func findRepoRoot() throws -> String {
        let output = try runGit(["rev-parse", "--show-toplevel"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func fetchRemotes() {
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
                if shortName.hasSuffix("/HEAD") { continue }
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

    @discardableResult
    func commitFile(_ path: String, message: String) throws -> String {
        _ = try runGit(["add", path])
        return try runGit(["commit", "-m", message])
    }

    /// Commits the review comments file, including deletion when the file no longer exists.
    /// Returns silently if there is nothing to commit.
    @discardableResult
    func commitReviewFile(_ path: String, message: String) throws -> String {
        // -A stages additions, modifications, and deletions for this pathspec.
        _ = try runGit(["add", "-A", "--", path])
        // `git diff --cached --quiet` exits 0 when nothing is staged. Skip the commit in that case.
        let nothingStaged = (try? runGit(["diff", "--cached", "--quiet", "--", path])) != nil
        if nothingStaged {
            return ""
        }
        return try runGit(["commit", "-m", message, "--", path])
    }

    func push() throws {
        _ = try runGit(["push"])
    }

    func pushSetUpstream(_ remote: String, _ branch: String) throws {
        _ = try runGit(["push", "-u", remote, branch])
    }

    func pull() throws {
        _ = try runGit(["pull"])
    }

    func fetchAndUpdateBranch(_ branch: String) throws {
        _ = try runGit(["fetch", "--all", "--quiet"])
        let upstream = try runGit(["rev-parse", "--abbrev-ref", "\(branch)@{upstream}"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Refuse non-fast-forward updates so unpushed local commits are never silently discarded.
        // `merge-base --is-ancestor` exits 0 if the local tip is already in the upstream history.
        let isFastForward = (try? runGit(["merge-base", "--is-ancestor", "refs/heads/\(branch)", upstream])) != nil
        guard isFastForward else {
            throw GitError.notFastForward(branch: branch)
        }
        let upstreamSHA = try runGit(["rev-parse", upstream])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try runGit(["update-ref", "refs/heads/\(branch)", upstreamSHA])
    }

    func checkout(_ branch: String) throws {
        _ = try runGit(["checkout", branch])
    }

    func checkoutPR(_ number: String) throws {
        try runCommand("/usr/bin/env", args: ["gh", "pr", "checkout", number])
    }

    func checkoutMR(_ number: String) throws {
        try runCommand("/usr/bin/env", args: ["glab", "mr", "checkout", number])
    }

    func currentBranch() throws -> String {
        let output = try runGit(["rev-parse", "--abbrev-ref", "HEAD"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func resolveRef(_ ref: String) throws -> String {
        let output = try runGit(["rev-parse", ref])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
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

    @discardableResult
    private func runCommand(_ executable: String, args: [String]) throws -> String {
        return try runProcess(executable: executable, arguments: args, currentDirectory: repoPath)
    }

    private func runGit(_ args: [String]) throws -> String {
        return try runProcess(executable: "/usr/bin/git", arguments: ["-C", repoPath] + args, currentDirectory: nil)
    }

    private func runProcess(executable: String, arguments: [String], currentDirectory: String?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }
        process.environment = ProcessInfo.processInfo.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Drain both pipes concurrently. Reading one fully before the other can deadlock
        // if the unread pipe fills its kernel buffer (~16-64KB) and the child blocks writing.
        let stderrBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBox.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()
        group.wait()
        let stderrData = stderrBox.get()

        guard let output = String(data: stdoutData, encoding: .utf8) else {
            throw GitError.invalidOutput
        }

        if process.terminationStatus != 0 {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw GitError.commandFailed(status: process.terminationStatus, output: stderr.isEmpty ? output : stderr)
        }

        return output
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.lock(); defer { lock.unlock() }
        data = value
    }

    func get() -> Data {
        lock.lock(); defer { lock.unlock() }
        return data
    }
}

enum GitError: Error, LocalizedError {
    case invalidOutput
    case commandFailed(status: Int32, output: String)
    case notFastForward(branch: String)

    var errorDescription: String? {
        switch self {
        case .invalidOutput:
            return "Failed to read git output"
        case .commandFailed(let status, let output):
            return "git exited with status \(status): \(output)"
        case .notFastForward(let branch):
            return "Refusing non-fast-forward update of \(branch). Local commits would be discarded."
        }
    }
}
