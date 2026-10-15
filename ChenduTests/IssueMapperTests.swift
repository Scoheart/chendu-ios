import XCTest
@testable import Chendu

final class IssueMapperTests: XCTestCase {
    func testMapsASupabaseRowOntoTheReaderIssue() throws {
        let json = """
        [{
          "issue_date": "2026-10-11",
          "topic": "stocks",
          "topic_label": "股市",
          "title": "Morning Markets",
          "zh_title": "早盘",
          "byline": "Example",
          "lead": "开盘很安静。",
          "blocks": [{"kind": "para", "segments": [{"text": "The market opened quietly.", "note": 1}]}],
          "credit": {"text": "Example", "links": [{"title": "Morning", "url": "https://example.com/morning"}]},
          "podcast": null,
          "annotations": [{"n": 1, "kind": "vocab", "tag": "词", "head": "quietly", "body": "安静地"}],
          "vocab": [{"position": 1, "word": "quietly", "ipa": "/ˈkwaɪətli/", "meaning": "安静地", "example": "The market opened quietly."}],
          "patterns": [{"position": 1, "pattern": "opened quietly", "pattern_zh": "安静地开始", "source_sentence": "The market opened quietly.", "model_sentence": "The shop opened quietly.", "model_zh": "店安静地开了。"}],
          "audio_assets": [{"kind": "normal", "storage_path": "audio/user/issue/normal.mp3"}, {"kind": "slow", "storage_path": "audio/user/issue/slow.mp3"}]
        }]
        """.data(using: .utf8)!
        let issues = try IssueMapper.issues(from: json)
        XCTAssertEqual(issues.map(\.date), ["2026-10-11"])
        let issue = issues[0]
        XCTAssertEqual(issue.zhTitle, "早盘")
        XCTAssertEqual(issue.notes[0].kind, .vocab)
        XCTAssertEqual(issue.notes[0].tilt, 0)
        XCTAssertEqual(issue.words[0].word, "quietly")
        XCTAssertEqual(issue.patterns[0].source, "The market opened quietly.")
        XCTAssertEqual(issue.audio.map(\.id), ["normal", "slow"])
        XCTAssertEqual(issue.audio[1].file, "slow.mp3")
        let paths = try IssueMapper.storagePaths(from: json)
        XCTAssertEqual(paths["2026-10-11"]?["slow"], "audio/user/issue/slow.mp3")
    }

    func testListOrderIsPreservedFromTheQuery() throws {
        let json = """
        [
          {"issue_date":"2026-10-11","topic":"stocks","topic_label":"股市","title":"C","zh_title":"","byline":"","lead":"","blocks":[],"credit":null,"podcast":null,"annotations":[],"vocab":[],"patterns":[],"audio_assets":[]},
          {"issue_date":"2026-10-09","topic":"ai","topic_label":"AI","title":"A","zh_title":"","byline":"","lead":"","blocks":[],"credit":null,"podcast":null,"annotations":[],"vocab":[],"patterns":[],"audio_assets":[]}
        ]
        """.data(using: .utf8)!
        let issues = try IssueMapper.issues(from: json)
        XCTAssertEqual(issues.map(\.date), ["2026-10-11", "2026-10-09"])
    }
}

final class ReaderModelTests: XCTestCase {
    func testRenderingOffsets() throws {
        let segs = [Segment(text: "The ", note: nil), Segment(text: "quick fox", note: 1), Segment(text: " jumps over", note: nil)]
        let mark = UserMark(id: UUID(), range: NSRange(location: 14, length: 5))
        let rendered = ParagraphRendering.make(segments: segs, notes: [:], marks: [mark], activeKey: nil, fontSize: 18)
        let display = rendered.attributed.string as NSString
        XCTAssertEqual(display as String, "The quick fox1 jumps✎ over")
        let jumps = display.range(of: "jumps")
        XCTAssertEqual(rendered.displayToBase(jumps.location), 14)
    }

    func testUserNoteAnchorFallsBackToQuote() {
        let note = UserNote(issueDate: "d", issueTitle: "t", paragraphIndex: 0, start: 2, length: 3, quote: "fox", text: "n")
        XCTAssertEqual(note.resolvedRange(in: "a fox"), NSRange(location: 2, length: 3))
        XCTAssertEqual(note.resolvedRange(in: "the red fox"), NSRange(location: 8, length: 3))
        XCTAssertNil(note.resolvedRange(in: "nothing here"))
    }
}
