import Foundation

/// Archive entry mapped from a Supabase `issues` row.
struct IssueSummary: Codable, Hashable, Identifiable {
    var date: String
    var topic: String
    var topicLabel: String
    var title: String
    var zhTitle: String
    var lead: String?

    var id: String { date }
}

struct FeedIndex: Codable {
    var version: Int
    var issues: [IssueSummary]
}

/// One daily issue. The reader still uses this shape; the fields come from Supabase.
struct Issue: Codable, Hashable, Identifiable {
    var date: String
    var topic: String
    var topicLabel: String
    var dateLabel: String
    var title: String
    var zhTitle: String
    var byline: String
    var lead: String
    var blocks: [ArticleBlock]
    var notes: [Annotation]
    var credit: Credit?
    var audio: [AudioTrack]
    var words: [ReviewWord]
    var patterns: [SentencePattern]
    var podcast: Podcast?
    /// Supabase `issues.id`. The reader still identifies an issue by `date`.
    var remoteId: String? = nil

    var id: String { date }

    var summary: IssueSummary {
        IssueSummary(date: date, topic: topic, topicLabel: topicLabel, title: title, zhTitle: zhTitle, lead: lead)
    }

    func note(_ n: Int) -> Annotation? { notes.first { $0.n == n } }

    /// Article paragraphs in reading order; `index` is the stable anchor used by reader notes.
    var paragraphs: [Paragraph] {
        var out: [Paragraph] = []
        var gapBefore = false
        for block in blocks {
            switch block.kind {
            case .gap:
                gapBefore = true
            case .para:
                out.append(Paragraph(index: out.count, segments: block.segments, gapBefore: gapBefore))
                gapBefore = false
            }
        }
        return out
    }

    /// Paragraph index that contains annotation `n`.
    var paragraphForNote: [Int: Int] {
        var map: [Int: Int] = [:]
        for p in paragraphs {
            for s in p.segments { if let n = s.note, map[n] == nil { map[n] = p.index } }
        }
        return map
    }
}

struct ArticleBlock: Codable, Hashable {
    enum Kind: String, Codable { case para, gap }
    var kind: Kind
    var segments: [Segment]
}

struct Segment: Codable, Hashable {
    var text: String
    var note: Int?
}

struct Paragraph: Hashable, Identifiable {
    var index: Int
    var segments: [Segment]
    var gapBefore: Bool
    var id: Int { index }
    var text: String { segments.map(\.text).joined() }
}

enum NoteKind: String, Codable {
    case vocab, grammar, idiom

    var label: String {
        switch self {
        case .vocab: "词汇"
        case .grammar: "语法"
        case .idiom: "地道表达"
        }
    }
}

struct Annotation: Codable, Hashable, Identifiable {
    var n: Int
    var kind: NoteKind
    var tag: String
    var head: String
    /// Chinese explanation; `**…**` marks emphasis (`<b>` on the site).
    var body: String
    var tilt: Double

    var id: Int { n }
}

struct Credit: Codable, Hashable {
    var text: String
    var links: [WebLink]
}

struct WebLink: Codable, Hashable {
    var title: String
    var url: String
}

struct AudioTrack: Codable, Hashable, Identifiable {
    /// "normal" or "slow"
    var id: String
    var label: String
    var detail: String
    var file: String

    var isSlow: Bool { id == "slow" }
}

struct ReviewWord: Codable, Hashable {
    var word: String
    var ipa: String
    var meaning: String
    var example: String
}

struct SentencePattern: Codable, Hashable {
    var pattern: String
    var patternZh: String
    var source: String
    var model: String
    var modelZh: String
}

struct Podcast: Codable, Hashable {
    var source: String
    var title: String
    var summary: String
    var url: String
}
