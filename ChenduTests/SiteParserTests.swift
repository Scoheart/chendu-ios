import XCTest
@testable import Chendu

final class SiteParserTests: XCTestCase {
    private func fixture(_ name: String, _ ext: String = "html") throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testIndex() throws {
        let issues = SiteParser.parseIndex(try fixture("home"))
        XCTAssertEqual(issues.map(\.date), ["2026-10-11", "2026-10-10", "2026-10-09"])
        XCTAssertEqual(issues[0].topic, "stocks")
        XCTAssertEqual(issues[0].topicLabel, "美股")
        XCTAssertEqual(issues[0].title, "Wall Street finishes its record-setting week with gains")
        XCTAssertTrue(issues[0].zhTitle.hasPrefix("美股收官周收涨"))
        XCTAssertNotNil(issues[0].lead)
        XCTAssertEqual(issues[1].topic, "ai")
        XCTAssertNil(issues[1].lead)
    }

    func testIssue() throws {
        let issue = try SiteParser.parseIssue(try fixture("issue-2026-10-11"), date: "x")
        XCTAssertEqual(issue.date, "2026-10-11")
        XCTAssertEqual(issue.topic, "stocks")
        XCTAssertEqual(issue.dateLabel, "2026 年 10 月 11 日 · 周日")
        XCTAssertEqual(issue.notes.count, 18)
        XCTAssertEqual(issue.notes.map(\.n), Array(1...18))
        XCTAssertEqual(issue.words.count, 12)
        XCTAssertEqual(issue.patterns.count, 4)
        XCTAssertEqual(issue.audio.map(\.file), ["audio.mp3", "audio-slow.mp3"])
        XCTAssertEqual(issue.audio[0].label, "正常语速")
        XCTAssertEqual(issue.audio[1].id, "slow")
        XCTAssertEqual(issue.podcast?.title, "The stock market isn’t the economy — except when maybe it is?")
        XCTAssertEqual(issue.credit?.links.count, 3)
        XCTAssertTrue(issue.blocks.contains { $0.kind == .gap })

        let paras = issue.paragraphs
        XCTAssertEqual(paras.count, 10)
        XCTAssertTrue(paras[5].gapBefore)
        XCTAssertEqual(paras[0].text, "NEW YORK (AP) -- The U.S. stock market finished its record-setting week with gains on Friday, even as other financial markets remained indecisive.")
        XCTAssertEqual(paras[0].segments.first { $0.note == 1 }?.text, "record-setting week")
        XCTAssertTrue(paras[1].text.contains("S&P 500"))

        let n4 = try XCTUnwrap(issue.note(4))
        XCTAssertEqual(n4.kind, .idiom)
        XCTAssertEqual(n4.head, "yo-yo (v.)")
        XCTAssertEqual(n4.tilt, -0.9, accuracy: 0.001)
        XCTAssertEqual(issue.paragraphForNote[6], 2)

        XCTAssertEqual(issue.words[0].word, "indecisive")
        XCTAssertEqual(issue.words[0].ipa, "/ˌɪndɪˈsaɪsɪv/")
        XCTAssertEqual(issue.words[0].example, "Other financial markets remained indecisive on Friday.")
        XCTAssertEqual(issue.patterns[0].patternZh, "A 收涨收官，尽管 B 仍…")
        XCTAssertFalse(issue.patterns[0].source.hasPrefix("原文"))
    }

    func testFeedJSONMatchesPageParser() throws {
        // issue-<date>.json fixtures are produced by the site's tools/build_app_feed.py from the same pages.
        for date in ["2026-10-09", "2026-10-10", "2026-10-11"] {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "issue-\(date)", withExtension: "json"))
            let fromFeed = try JSONDecoder().decode(Issue.self, from: Data(contentsOf: url))
            let fromPage = try SiteParser.parseIssue(try fixture("issue-\(date)"), date: date)
            XCTAssertEqual(fromFeed, fromPage, date)
            XCTAssertFalse(fromPage.notes.isEmpty, date)
            XCTAssertEqual(fromPage.audio.count, 2, date)
        }
    }

    func testEntities() {
        XCTAssertEqual(HTMLParser.decodeEntities("S&amp;P &#8212; &#x2019; &nbsp;&bogus; a & b"), "S&P — ’ \u{00A0}&bogus; a & b")
    }

    func testRenderingOffsets() throws {
        let segs = [Segment(text: "The ", note: nil), Segment(text: "quick fox", note: 1), Segment(text: " jumps over", note: nil)]
        let mark = UserMark(id: UUID(), range: NSRange(location: 14, length: 5)) // "jumps"
        let r = ParagraphRendering.make(segments: segs, notes: [:], marks: [mark], activeKey: nil, fontSize: 18)
        let display = r.attributed.string as NSString
        XCTAssertEqual(display as String, "The quick fox1 jumps✎ over")
        // round-trip plain → display → plain
        for b in 0...(r.plain as NSString).length {
            XCTAssertEqual(r.displayToBase(r.baseToDisplay(b)), b)
        }
        let jumps = display.range(of: "jumps")
        XCTAssertEqual(r.displayToBase(jumps.location), 14)
        XCTAssertEqual(r.displayToBase(NSMaxRange(jumps)), 19)
    }

    func testUserNoteAnchorFallsBackToQuote() {
        let note = UserNote(issueDate: "d", issueTitle: "t", paragraphIndex: 0, start: 2, length: 3, quote: "fox", text: "n")
        XCTAssertEqual(note.resolvedRange(in: "a fox"), NSRange(location: 2, length: 3))
        XCTAssertEqual(note.resolvedRange(in: "the red fox"), NSRange(location: 8, length: 3))
        XCTAssertNil(note.resolvedRange(in: "nothing here"))
    }
}
