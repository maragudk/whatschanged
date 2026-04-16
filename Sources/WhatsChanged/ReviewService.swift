import Foundation

struct ReviewService: Sendable {
    let repoPath: String

    private var filePath: String {
        (repoPath as NSString).appendingPathComponent("review.jsonl")
    }

    func load() throws -> [ReviewComment] {
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? ""
        let decoder = JSONDecoder()
        return text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line in
                try? decoder.decode(ReviewComment.self, from: Data(line.utf8))
            }
    }

    func append(_ comment: ReviewComment) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(comment)
        let line = String(decoding: data, as: UTF8.self) + "\n"

        let url = URL(fileURLWithPath: filePath)
        if FileManager.default.fileExists(atPath: filePath) {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            try Data(line.utf8).write(to: url)
        }
    }

    func update(_ comment: ReviewComment) throws {
        var comments = try load()
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        comments[index] = comment
        try writeAll(comments)
    }

    func delete(_ comment: ReviewComment) throws {
        var comments = try load()
        comments.removeAll { $0.id == comment.id }
        if comments.isEmpty {
            try FileManager.default.removeItem(atPath: filePath)
        } else {
            try writeAll(comments)
        }
    }

    private func writeAll(_ comments: [ReviewComment]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let lines = try comments.map { comment in
            let data = try encoder.encode(comment)
            return String(decoding: data, as: UTF8.self)
        }
        let text = lines.joined(separator: "\n") + "\n"
        try Data(text.utf8).write(to: URL(fileURLWithPath: filePath))
    }
}
