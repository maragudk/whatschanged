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
                return (FileDiff(oldPath: oldPath, newPath: newPath, hunks: [], isBinary: true, additions: 0, deletions: 0), i)
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

        let additions = hunks.reduce(0) { $0 + $1.lines.filter { $0.type == .addition }.count }
        let deletions = hunks.reduce(0) { $0 + $1.lines.filter { $0.type == .deletion }.count }
        return (FileDiff(oldPath: oldPath, newPath: newPath, hunks: hunks, isBinary: isBinary, additions: additions, deletions: deletions), i)
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

        // Build a temporary hunk to compute rows, then store the final result.
        let tempHunk = DiffHunk(oldStart: oldStart, oldCount: oldCount,
                                newStart: newStart, newCount: newCount,
                                header: header, lines: diffLines, rows: [])
        let rows = sideBySideRows(for: tempHunk)
        let hunk = DiffHunk(oldStart: oldStart, oldCount: oldCount,
                            newStart: newStart, newCount: newCount,
                            header: header, lines: diffLines, rows: rows)
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
                    right: .init(lineNumber: newLine, content: line.content, type: .context),
                    leftSegments: nil, rightSegments: nil
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
                    let isModified = !additions.isEmpty && !deletions.isEmpty
                    let leftSide: SideBySideRow.Side? = j < deletions.count
                        ? .init(
                            lineNumber: oldLine + j,
                            content: deletions[j].content,
                            type: isModified ? .modified : .deletion
                        ) : nil
                    let rightSide: SideBySideRow.Side? = j < additions.count
                        ? .init(
                            lineNumber: newLine + j,
                            content: additions[j].content,
                            type: isModified ? .modified : .addition
                        ) : nil
                    // Pre-compute inline diff segments for modified pairs.
                    var leftSegs: (String, String, String)?
                    var rightSegs: (String, String, String)?
                    if isModified, let l = leftSide, let r = rightSide {
                        leftSegs = diffSegments(l.content, r.content)
                        rightSegs = diffSegments(r.content, l.content)
                    }
                    rows.append(SideBySideRow(left: leftSide, right: rightSide,
                                             leftSegments: leftSegs, rightSegments: rightSegs))
                }
                oldLine += deletions.count
                newLine += additions.count

            case .addition:
                rows.append(SideBySideRow(
                    left: nil,
                    right: .init(lineNumber: newLine, content: line.content, type: .addition),
                    leftSegments: nil, rightSegments: nil
                ))
                newLine += 1
                i += 1
            }
        }

        return rows
    }

    /// Find the common prefix and suffix between two strings, returning
    /// (prefix, changed middle, suffix) for the first string.
    static func diffSegments(_ a: String, _ b: String) -> (String, String, String) {
        let aChars = Array(a)
        let bChars = Array(b)

        var prefixLen = 0
        while prefixLen < aChars.count && prefixLen < bChars.count
                && aChars[prefixLen] == bChars[prefixLen] {
            prefixLen += 1
        }

        var suffixLen = 0
        while suffixLen < (aChars.count - prefixLen) && suffixLen < (bChars.count - prefixLen)
                && aChars[aChars.count - 1 - suffixLen] == bChars[bChars.count - 1 - suffixLen] {
            suffixLen += 1
        }

        let prefix = String(aChars[..<prefixLen])
        let suffix = String(aChars[(aChars.count - suffixLen)...])
        let changed = String(aChars[prefixLen..<(aChars.count - suffixLen)])

        return (prefix, changed, suffix)
    }
}
