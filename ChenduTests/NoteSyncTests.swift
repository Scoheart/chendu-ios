import XCTest
@testable import Chendu

final class NoteSyncTests: XCTestCase {
    private func note(_ id: String, updated: TimeInterval, body: String, deleted: TimeInterval? = nil) -> NoteRecord {
        NoteRecord(
            id: UUID(uuidString: id)!,
            issueId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
            paragraphIndex: 0,
            start: 0,
            length: 3,
            quote: "fox",
            body: body,
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: updated),
            deletedAt: deleted.map { Date(timeIntervalSince1970: $0) }
        )
    }

    func testNewerLocalNoteIsPushedAndNewerRemoteNoteIsPulled() {
        let id = "11111111-1111-4111-8111-111111111111"
        let local = note(id, updated: 20, body: "local")
        let remote = note(id, updated: 10, body: "remote")
        let plan = NoteSync.plan(local: [local], remote: [remote], syncEnabled: true)
        XCTAssertEqual(plan.push.map(\.body), ["local"])
        XCTAssertTrue(plan.pull.isEmpty)

        let reverse = NoteSync.plan(local: [remote], remote: [local], syncEnabled: true)
        XCTAssertEqual(reverse.pull.map(\.body), ["local"])
        XCTAssertTrue(reverse.push.isEmpty)
    }

    func testATombstoneWithALaterTimestampWins() {
        let id = "22222222-2222-4222-8222-222222222222"
        let alive = note(id, updated: 10, body: "keep")
        let dead = note(id, updated: 30, body: "keep", deleted: 30)
        let plan = NoteSync.plan(local: [alive], remote: [dead], syncEnabled: true)
        XCTAssertEqual(plan.pull.first?.deletedAt, dead.deletedAt)
        XCTAssertTrue(plan.push.isEmpty)
    }

    func testSyncOffKeepsTheNoteLocal() {
        let id = "33333333-3333-4333-8333-333333333333"
        let plan = NoteSync.plan(local: [note(id, updated: 1, body: "x")], remote: [], syncEnabled: false)
        XCTAssertTrue(plan.push.isEmpty)
        XCTAssertTrue(plan.pull.isEmpty)
    }

    func testPayloadKeepsTheClientUpdatedAtAndUsesBody() {
        let id = "44444444-4444-4444-8444-444444444444"
        let record = note(id, updated: 50, body: "hello")
        let payload = NoteSync.payload(record, userId: "user")
        XCTAssertEqual(payload["body"] as? String, "hello")
        XCTAssertEqual(payload["updated_at"] as? String, NoteSync.payload(record, userId: "user")["updated_at"] as? String)
        XCTAssertFalse((payload["updated_at"] as? String ?? "").isEmpty)
        XCTAssertNil(payload["text"])
    }

    func testMarkdownSkipsTombstones() {
        let alive = UserNote(issueDate: "2026-10-11", issueTitle: "Morning", paragraphIndex: 0, start: 0, length: 3, quote: "fox", text: "alive")
        let dead = UserNote(issueDate: "2026-10-11", issueTitle: "Morning", paragraphIndex: 0, start: 0, length: 3, quote: "fox", text: "gone")
        dead.markDeleted()
        let markdown = NotesExport.markdown([alive, dead])
        XCTAssertTrue(markdown.contains("alive"))
        XCTAssertFalse(markdown.contains("gone"))
    }
}
