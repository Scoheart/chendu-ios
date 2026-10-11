import Foundation

struct NoteRecord: Equatable {
    var id: UUID
    var issueId: String
    var paragraphIndex: Int
    var start: Int
    var length: Int
    var quote: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
}

struct NoteMerge: Equatable {
    var push: [NoteRecord]
    var pull: [NoteRecord]
}

enum NoteSync {
    /// Last-write-wins on `updatedAt`. The server is not allowed to rewrite that timestamp.
    static func plan(local: [NoteRecord], remote: [NoteRecord], syncEnabled: Bool) -> NoteMerge {
        guard syncEnabled else { return NoteMerge(push: [], pull: []) }
        let remoteById = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        let localById = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var push: [NoteRecord] = []
        var pull: [NoteRecord] = []
        for note in local {
            guard !note.issueId.isEmpty else { continue }
            if let other = remoteById[note.id] {
                if note.updatedAt > other.updatedAt { push.append(note) }
            } else {
                push.append(note)
            }
        }
        for note in remote {
            if let other = localById[note.id] {
                if note.updatedAt > other.updatedAt { pull.append(note) }
            } else {
                pull.append(note)
            }
        }
        return NoteMerge(push: push, pull: pull)
    }

    static func payload(_ note: NoteRecord, userId: String) -> [String: Any] {
        var body: [String: Any] = [
            "id": note.id.uuidString,
            "user_id": userId,
            "issue_id": note.issueId,
            "paragraph_index": note.paragraphIndex,
            "start_utf16": note.start,
            "length_utf16": note.length,
            "quote": note.quote,
            "body": note.body,
            "created_at": iso(note.createdAt),
            "updated_at": iso(note.updatedAt),
        ]
        if let deletedAt = note.deletedAt { body["deleted_at"] = iso(deletedAt) }
        return body
    }

    static func record(from note: UserNote) -> NoteRecord? {
        guard let issueId = note.issueRemoteId, !issueId.isEmpty else { return nil }
        return NoteRecord(
            id: note.id,
            issueId: issueId,
            paragraphIndex: note.paragraphIndex,
            start: note.start,
            length: note.length,
            quote: note.quote,
            body: note.text,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt,
            deletedAt: note.deletedAt
        )
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
