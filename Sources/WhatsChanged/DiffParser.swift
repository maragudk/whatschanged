import Foundation

enum DiffParser {
    static func parse(_ diff: String) -> [FileDiff] {
        let lines = diff.components(separatedBy: "\n")
        var files: [FileDiff] = []
        var i = 0

        while i < lines.count {
            // Look for "diff --git" header.
            guard lines[i].hasPrefix("diff --git ") else {
                i += 1
                continue
            }

            let (file, nextIndex) = parseFile(lines: lines, startIndex: i)
            if let file {
                files.append(file)
            }
            i = nextIndex
        }

        return files
    }

    private static func parseFile(lines: [String], startIndex: Int) -> (FileDiff?, Int) {
        var i = startIndex + 1 // Skip "diff --git" line.
        var oldPath = ""
        var newPath = ""
        var isBinary = false

        // Parse file header lines until we hit --- or the next diff.
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("--- ") {
                oldPath = parseFilePath(line, prefix: "--- ")
                i += 1
                break
            } else if line.hasPrefix("Binary files") {
                isBinary = true
                // Extract paths from "Binary files a/foo and b/bar differ".
                let parts = line.components(separatedBy: " ")
                if parts.count >= 5 {
                    oldPath = String(parts[2].dropFirst(2)) // drop "a/"
                    newPath = String(parts[4].dropFirst(2)) // drop "b/"
                }
                i += 1
                return (FileDiff(oldPath: oldPath, newPath: newPath, hunks: [], isBinary: true), i)
            } else if line.hasPrefix("diff --git ") {
                // Next file, no content.
                return (nil, i)
            } else if line.hasPrefix("rename from ") {
                oldPath = String(line.dropFirst("rename from ".count))
                i += 1
                continue
            } else if line.hasPrefix("rename to ") {
                newPath = String(line.dropFirst("rename to ".count))
                i += 1
                continue
            } else {
                i += 1
                continue
            }
        }

        // Parse +++ line.
        if i < lines.count && lines[i].hasPrefix("+++ ") {
            newPath = parseFilePath(lines[i], prefix: "+++ ")
            i += 1
        }

        // If we got paths from rename headers but not from ---/+++, keep them.
        if oldPath.isEmpty { oldPath = newPath }
        if newPath.isEmpty { newPath = oldPath }

        // Parse hunks.
        var hunks: [DiffHunk] = []
        while i < lines.count && !lines[i].hasPrefix("diff --git ") {
            if lines[i].hasPrefix("@@ ") {
                let (hunk, nextIndex) = parseHunk(lines: lines, startIndex: i)
                if let hunk {
                    hunks.append(hunk)
                }
                i = nextIndex
            } else {
                i += 1
            }
        }

        return (FileDiff(oldPath: oldPath, newPath: newPath, hunks: hunks, isBinary: isBinary), i)
    }

    private static func parseFilePath(_ line: String, prefix: String) -> String {
        var path = String(line.dropFirst(prefix.count))
        // Strip a/ or b/ prefix.
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path = String(path.dropFirst(2))
        }
        if path == "/dev/null" {
            return "/dev/null"
        }
        return path
    }

    private static func parseHunk(lines: [String], startIndex: Int) -> (DiffHunk?, Int) {
        let header = lines[startIndex]

        // Parse @@ -old,count +new,count @@
        guard let range = header.range(of: #"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@"#, options: .regularExpression) else {
            return (nil, startIndex + 1)
        }

        let match = String(header[range])
        let numbers = match.components(separatedBy: CharacterSet(charactersIn: "@-+, "))
            .filter { !$0.isEmpty }
            .compactMap { Int($0) }

        let oldStart = numbers.count > 0 ? numbers[0] : 0
        let oldCount = numbers.count > 1 ? numbers[1] : 0
        let newStart = numbers.count > 2 ? numbers[2] : 0
        let newCount = numbers.count > 3 ? numbers[3] : 0

        var i = startIndex + 1
        var diffLines: [DiffLine] = []

        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("diff --git ") || line.hasPrefix("@@ ") {
                break
            }

            if line.hasPrefix("+") {
                diffLines.append(DiffLine(type: .addition, content: String(line.dropFirst())))
            } else if line.hasPrefix("-") {
                diffLines.append(DiffLine(type: .deletion, content: String(line.dropFirst())))
            } else if line.hasPrefix(" ") {
                diffLines.append(DiffLine(type: .context, content: String(line.dropFirst())))
            } else if line.hasPrefix("\\") {
                // "\ No newline at end of file" -- skip.
            } else if line.isEmpty {
                // Could be a context line with the space stripped, or end of diff.
                // Check if we're still within the hunk by counting lines.
                diffLines.append(DiffLine(type: .context, content: ""))
            }
            i += 1
        }

        let hunk = DiffHunk(
            oldStart: oldStart, oldCount: oldCount,
            newStart: newStart, newCount: newCount,
            header: header,
            lines: diffLines
        )
        return (hunk, i)
    }

    /// Convert a hunk's lines into side-by-side rows with line numbers.
    static func sideBySideRows(for hunk: DiffHunk) -> [SideBySideRow] {
        var rows: [SideBySideRow] = []
        let lines = hunk.lines
        var oldLine = hunk.oldStart
        var newLine = hunk.newStart
        var i = 0

        while i < lines.count {
            let line = lines[i]

            switch line.type {
            case .context:
                rows.append(SideBySideRow(
                    left: .init(lineNumber: oldLine, content: line.content, type: .context),
                    right: .init(lineNumber: newLine, content: line.content, type: .context)
                ))
                oldLine += 1
                newLine += 1
                i += 1

            case .deletion:
                // Collect consecutive deletions.
                var deletions: [DiffLine] = []
                while i < lines.count && lines[i].type == .deletion {
                    deletions.append(lines[i])
                    i += 1
                }
                // Collect consecutive additions that follow.
                var additions: [DiffLine] = []
                while i < lines.count && lines[i].type == .addition {
                    additions.append(lines[i])
                    i += 1
                }
                // Pair them up.
                let maxCount = max(deletions.count, additions.count)
                for j in 0..<maxCount {
                    let leftSide: SideBySideRow.Side? = j < deletions.count
                        ? .init(
                            lineNumber: oldLine + j,
                            content: deletions[j].content,
                            type: additions.isEmpty ? .deletion : .modified
                        ) : nil
                    let rightSide: SideBySideRow.Side? = j < additions.count
                        ? .init(
                            lineNumber: newLine + j,
                            content: additions[j].content,
                            type: deletions.isEmpty ? .addition : .modified
                        ) : nil
                    rows.append(SideBySideRow(left: leftSide, right: rightSide))
                }
                oldLine += deletions.count
                newLine += additions.count

            case .addition:
                rows.append(SideBySideRow(
                    left: nil,
                    right: .init(lineNumber: newLine, content: line.content, type: .addition)
                ))
                newLine += 1
                i += 1
            }
        }

        return rows
    }
}
