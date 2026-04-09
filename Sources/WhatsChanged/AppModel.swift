import Foundation
import SwiftUI

@Observable
@MainActor
final class AppModel {
    var repoPath: String?
    var refs: [GitRef] = []
    var baseRef: GitRef?
    var compareRef: GitRef?
    var fileDiffs: [FileDiff] = []
    var isLoading = false
    var error: String?

    init() {
        // Check CLI arguments for a repo path.
        let args = CommandLine.arguments
        if args.count > 1 {
            let path = args[1]
            let resolved = path.hasPrefix("/")
                ? path
                : FileManager.default.currentDirectoryPath + "/" + path
            repoPath = resolved
        }
    }

    func loadRefs() {
        guard let repoPath else { return }

        isLoading = true
        error = nil

        Task.detached {
            let git = GitService(repoPath: repoPath)
            do {
                let refs = try git.getRefs()
                let primary = try git.primaryBranch()
                await MainActor.run {
                    self.refs = refs
                    if self.baseRef == nil {
                        self.baseRef = refs.first { $0.name == primary }
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func loadDiff() {
        guard let repoPath, let base = baseRef, let compare = compareRef else {
            fileDiffs = []
            return
        }

        isLoading = true
        error = nil

        let baseName = base.name
        let compareName = compare.name

        Task.detached {
            let git = GitService(repoPath: repoPath)
            do {
                let output = try git.getDiff(base: baseName, compare: compareName)
                let diffs = DiffParser.parse(output)
                await MainActor.run {
                    self.fileDiffs = diffs
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.fileDiffs = []
                    self.isLoading = false
                }
            }
        }
    }

    func openRepo(at url: URL) {
        repoPath = url.path(percentEncoded: false)
        baseRef = nil
        compareRef = nil
        fileDiffs = []
        loadRefs()
    }
}
