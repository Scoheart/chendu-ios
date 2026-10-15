import Foundation
import SwiftData

/// A reader's own note, anchored to a text range inside one article paragraph.
@Model
final class UserNote {
    @Attribute(.unique) var id: UUID
    var issueDate: String
    var issueTitle: String
    var paragraphIndex: Int
    /// UTF-16 offset and length within the paragraph's plain text.
    var start: Int
    var length: Int
    var quote: String
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(issueDate: String, issueTitle: String, paragraphIndex: Int, start: Int, length: Int, quote: String, text: String) {
        self.id = UUID()
        self.issueDate = issueDate
        self.issueTitle = issueTitle
        self.paragraphIndex = paragraphIndex
        self.start = start
        self.length = length
        self.quote = quote
        self.text = text
        self.createdAt = .now
        self.updatedAt = .now
    }

    var key: String { "u:\(id.uuidString)" }

    /// Resolves the anchor against the current paragraph text; falls back to searching for the quote.
    func resolvedRange(in paragraphText: String) -> NSRange? {
        let ns = paragraphText as NSString
        let stored = NSRange(location: start, length: length)
        if length > 0, NSMaxRange(stored) <= ns.length, ns.substring(with: stored) == quote {
            return stored
        }
        guard !quote.isEmpty else { return nil }
        let found = ns.range(of: quote)
        return found.location == NSNotFound ? nil : found
    }
}

enum NotesExport {
    static func markdown(_ notes: [UserNote]) -> String {
        var out = "# 晨读 · 我的笔记\n"
        let groups = Dictionary(grouping: notes, by: \.issueDate)
        for date in groups.keys.sorted(by: >) {
            let items = groups[date]!.sorted { ($0.paragraphIndex, $0.start) < ($1.paragraphIndex, $1.start) }
            out += "\n## \(date) · \(items.first?.issueTitle ?? "")\n"
            for note in items {
                out += "\n> \(note.quote)\n\n\(note.text)\n"
            }
        }
        return out
    }
}
