import Foundation

struct IssueRow: Decodable {
    var issueDate: String
    var topic: String?
    var topicLabel: String?
    var title: String
    var zhTitle: String
    var byline: String
    var lead: String
    var blocks: [ArticleBlock]
    var credit: Credit?
    var podcast: Podcast?
    var annotations: [AnnotationRow]
    var vocab: [VocabRow]
    var patterns: [PatternRow]
    var audio: [AudioRow]

    enum CodingKeys: String, CodingKey {
        case issueDate = "issue_date"
        case topic
        case topicLabel = "topic_label"
        case title
        case zhTitle = "zh_title"
        case byline
        case lead
        case blocks
        case credit
        case podcast
        case annotations
        case vocab
        case patterns
        case audio = "audio_assets"
    }
}

struct AnnotationRow: Decodable {
    var n: Int
    var kind: String
    var tag: String
    var head: String
    var body: String
}

struct VocabRow: Decodable {
    var position: Int
    var word: String
    var ipa: String
    var meaning: String
    var example: String
}

struct PatternRow: Decodable {
    var position: Int
    var pattern: String
    var patternZh: String
    var source: String
    var model: String
    var modelZh: String

    enum CodingKeys: String, CodingKey {
        case position
        case pattern
        case patternZh = "pattern_zh"
        case source = "source_sentence"
        case model = "model_sentence"
        case modelZh = "model_zh"
    }
}

struct AudioRow: Decodable {
    var kind: String
    var storagePath: String

    enum CodingKeys: String, CodingKey {
        case kind
        case storagePath = "storage_path"
    }
}

enum IssueMapper {
    static func issues(from data: Data) throws -> [Issue] {
        let rows = try JSONDecoder().decode([IssueRow].self, from: data)
        return rows.map(issue(from:))
    }

    static func issue(from row: IssueRow) -> Issue {
        Issue(
            date: row.issueDate,
            topic: row.topic ?? "general",
            topicLabel: row.topicLabel ?? "综合",
            dateLabel: dateLabel(row.issueDate),
            title: row.title,
            zhTitle: row.zhTitle,
            byline: row.byline,
            lead: row.lead,
            blocks: row.blocks,
            notes: row.annotations.sorted { $0.n < $1.n }.map { note in
                Annotation(
                    n: note.n,
                    kind: NoteKind(rawValue: note.kind) ?? .vocab,
                    tag: note.tag,
                    head: note.head,
                    body: note.body,
                    tilt: 0
                )
            },
            credit: row.credit,
            audio: row.audio.map(track(from:)),
            words: row.vocab.sorted { $0.position < $1.position }.map {
                ReviewWord(word: $0.word, ipa: $0.ipa, meaning: $0.meaning, example: $0.example)
            },
            patterns: row.patterns.sorted { $0.position < $1.position }.map {
                SentencePattern(pattern: $0.pattern, patternZh: $0.patternZh, source: $0.source, model: $0.model, modelZh: $0.modelZh)
            },
            podcast: row.podcast
        )
    }

    static func track(from row: AudioRow) -> AudioTrack {
        if row.kind == "slow" {
            return AudioTrack(id: "slow", label: "慢速", detail: "另一次合成", file: "slow.mp3")
        }
        return AudioTrack(id: row.kind, label: "正常语速", detail: "", file: "\(row.kind).mp3")
    }

    static func storagePaths(from data: Data) throws -> [String: [String: String]] {
        let rows = try JSONDecoder().decode([IssueRow].self, from: data)
        var paths: [String: [String: String]] = [:]
        for row in rows {
            var tracks: [String: String] = [:]
            for audio in row.audio {
                tracks[audio.kind] = audio.storagePath
            }
            paths[row.issueDate] = tracks
        }
        return paths
    }

    static func dateLabel(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }
        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.timeZone = TimeZone(secondsFromGMT: 0)
        output.dateFormat = "yyyy 年 M 月 d 日 · EEE"
        return output.string(from: date)
    }
}
