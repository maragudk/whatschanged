import Foundation
import SwiftUI

@Observable
@MainActor
final class AppModel {
    var repoPath: String?
    var repoRoot: String?
    var refs: [GitRef] = []
    var baseRef: GitRef?
    var compareRef: GitRef?
    var fileDiffs: [FileDiff] = []
    var error: String?
    var primaryBranchName = "main"
    var baseSHA: String?
    var compareSHA: String?
    var reviewComments: [ReviewComment] = []
    var currentBranch: String?
    var alertMessage: String?
    var isLoading = false
    private var loadingCount = 0

    private func startLoading() { loadingCount += 1; isLoading = true }
    private func stopLoading() { loadingCount -= 1; if loadingCount <= 0 { loadingCount = 0; isLoading = false } }

    init() {
        // Check CLI arguments for a repo path. Skip flags and "--".
        let args = CommandLine.arguments.dropFirst()
        if let path = args.first(where: { $0 != "--" && !$0.hasPrefix("-") }) {
            let url = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            repoPath = url.standardizedFileURL.path(percentEncoded: false)
        }
    }

    func loadRefs() {
        guard let repoPath else { return }

        error = nil
        startLoading()

        Task.detached {
            let git = GitService(repoPath: repoPath)
            do {
                // Show local refs immediately.
                let refs = try git.getRefs()
                let primary = try git.primaryBranch()
                let root = try git.findRepoRoot()
                let branch = try? git.currentBranch()
                await MainActor.run {
                    self.refs = refs
                    self.primaryBranchName = primary
                    self.repoRoot = root
                    self.currentBranch = branch
                    if self.baseRef == nil {
                        self.baseRef = refs.first { $0.name == primary }
                    }
                    if self.compareRef == nil, let branch, branch != primary {
                        self.compareRef = refs.first { $0.name == branch }
                    }
                    self.loadReviewComments()
                    self.loadDiff()
                }

                // Fetch remotes in the background, then update refs.
                git.fetchRemotes()
                let updatedRefs = try git.getRefs()
                await MainActor.run {
                    self.stopLoading()
                    self.refs = updatedRefs
                }
            } catch {
                await MainActor.run {
                    self.stopLoading()
                    self.error = error.localizedDescription
                }
            }
        }
    }

    func loadDiff() {
        guard let repoPath, let base = baseRef, let compare = compareRef else {
            fileDiffs = []
            return
        }

        error = nil
        startLoading()

        let baseName = base.name
        let compareName = compare.name

        Task.detached {
            let git = GitService(repoPath: repoPath)
            do {
                let output = try git.getDiff(base: baseName, compare: compareName)
                let diffs = DiffParser.parse(output)
                let resolvedBase = try git.resolveRef(baseName)
                let resolvedCompare = try git.resolveRef(compareName)
                await MainActor.run {
                    self.stopLoading()
                    self.fileDiffs = diffs
                    self.baseSHA = resolvedBase
                    self.compareSHA = resolvedCompare
                }
            } catch {
                await MainActor.run {
                    self.stopLoading()
                    self.error = error.localizedDescription
                    self.fileDiffs = []
                }
            }
        }
    }

    func openRepo(at url: URL) {
        repoPath = url.path(percentEncoded: false)
        baseRef = nil
        compareRef = nil
        fileDiffs = []
        baseSHA = nil
        compareSHA = nil
        reviewComments = []
        loadRefs()
    }

    func loadReviewComments() {
        guard let repoRoot else { return }
        let service = ReviewService(repoPath: repoRoot)
        reviewComments = (try? service.load()) ?? []
    }

    func addReviewComment(file: String, startLine: Int, endLine: Int, comment: String) {
        guard let repoRoot, let baseSHA, let compareSHA else { return }
        let service = ReviewService(repoPath: repoRoot)
        let reviewComment = ReviewComment(file: file, startLine: startLine, endLine: endLine, comment: comment, base: baseSHA, compare: compareSHA)
        try? service.append(reviewComment)
        reviewComments.append(reviewComment)
    }

    func updateReviewComment(_ reviewComment: ReviewComment) {
        guard let repoRoot else { return }
        let service = ReviewService(repoPath: repoRoot)
        try? service.update(reviewComment)
        if let index = reviewComments.firstIndex(where: { $0.id == reviewComment.id }) {
            reviewComments[index] = reviewComment
        }
    }

    func deleteReviewComment(_ reviewComment: ReviewComment) {
        guard let repoRoot else { return }
        let service = ReviewService(repoPath: repoRoot)
        try? service.delete(reviewComment)
        reviewComments.removeAll { $0.id == reviewComment.id }
    }

    func commitReviewComments() {
        guard let repoRoot else { return }
        let message = reviewComments.isEmpty ? "Remove review comments" : "Update review comments"
        Task.detached {
            let git = GitService(repoPath: repoRoot)
            do {
                let branch = try git.currentBranch()
                if branch == "main" || branch == "master" {
                    await MainActor.run {
                        self.alertMessage = "Cannot commit review comments on \(branch). Switch to a feature branch first."
                    }
                    return
                }
                try git.commitFile("review.jsonl", message: message)
                await MainActor.run {
                    self.loadDiff()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                }
            }
        }
    }

    func checkoutCompareRef() {
        guard let repoPath, let compare = compareRef else { return }

        startLoading()

        // For remote refs like "origin/feature-x", strip the remote prefix
        // so git checkout creates a local tracking branch.
        let type = compare.type
        let name = compare.name

        Task.detached {
            let git = GitService(repoPath: repoPath)
            do {
                switch type {
                case .remote:
                    // "origin/feature-x" -> "feature-x"
                    let parts = name.split(separator: "/", maxSplits: 1)
                    let branchName = parts.count == 2 ? String(parts[1]) : name
                    try git.checkout(branchName)
                case .local, .worktree:
                    try git.checkout(name)
                case .pullRequest:
                    if name.hasPrefix("refs/merge-requests/") {
                        let stripped = name.replacingOccurrences(of: "refs/merge-requests/", with: "")
                        let parts = stripped.split(separator: "/")
                        let number = parts.count == 2 ? String(parts[1]) : stripped
                        try git.checkoutMR(number)
                    } else {
                        let stripped = name
                            .replacingOccurrences(of: "refs/pull/", with: "")
                            .replacingOccurrences(of: "/head", with: "")
                        let parts = stripped.split(separator: "/")
                        let number = parts.last.map(String.init) ?? stripped
                        try git.checkoutPR(number)
                    }
                }
                let branch = try? git.currentBranch()
                await MainActor.run {
                    self.stopLoading()
                    self.currentBranch = branch
                }
            } catch {
                await MainActor.run {
                    self.stopLoading()
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func pushCurrentBranch() {
        guard let repoPath else { return }
        startLoading()
        Task.detached {
            let git = GitService(repoPath: repoPath)
            do {
                try git.push()
                await MainActor.run {
                    self.stopLoading()
                }
            } catch {
                await MainActor.run {
                    self.stopLoading()
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func pullCurrentBranch() {
        guard let repoPath else { return }
        startLoading()
        Task.detached {
            let git = GitService(repoPath: repoPath)
            do {
                try git.pull()
                await MainActor.run {
                    self.stopLoading()
                    self.loadDiff()
                }
            } catch {
                await MainActor.run {
                    self.stopLoading()
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func pullDefaultBranch() {
        guard let repoPath else { return }
        let branch = primaryBranchName
        startLoading()
        Task.detached {
            let git = GitService(repoPath: repoPath)
            do {
                try git.fetchAndUpdateBranch(branch)
                await MainActor.run {
                    self.stopLoading()
                    self.loadDiff()
                }
            } catch {
                await MainActor.run {
                    self.stopLoading()
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func reviewComment(forFile file: String, line: Int) -> ReviewComment? {
        guard let baseSHA, let compareSHA else { return nil }
        return reviewComments.first {
            $0.file == file && $0.containsLine(line) && $0.base == baseSHA && $0.compare == compareSHA
        }
    }
}
