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
    var error: String?
    var primaryBranchName = "main"

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

        Task.detached {
            let git = GitService(repoPath: repoPath)
            do {
                let refs = try git.getRefs()
                let primary = try git.primaryBranch()
                await MainActor.run {
                    self.refs = refs
                    self.primaryBranchName = primary
                    if self.baseRef == nil {
                        self.baseRef = refs.first { $0.name == primary }
                    }
                }
            } catch {
                await MainActor.run {
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

        let baseName = base.name
        let compareName = compare.name

        Task.detached {
            let git = GitService(repoPath: repoPath)
            do {
                let output = try git.getDiff(base: baseName, compare: compareName)
                let diffs = DiffParser.parse(output)
                await MainActor.run {
                    self.fileDiffs = diffs
                }
            } catch {
                await MainActor.run {
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
        loadRefs()
    }
}
