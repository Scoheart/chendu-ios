import Foundation

/// Reads the rendered pages of chendu-english.vercel.app into app models.
/// Used whenever the JSON feed is not deployed (or fails); mirrors `build_app_feed.py`.
enum SiteParser {
    enum ParseError: Error, LocalizedError {
        case missing(String)
        var errorDescription: String? {
            switch self { case .missing(let what): "页面结构无法识别（缺少 \(what)）" }
        }
    }

    // MARK: home page

    static func parseIndex(_ html: String) -> [IssueSummary] {
        let doc = HTMLParser.parse(html)
        var leads: [String: String] = [:]
        if let hero = doc.first("a", class: "hero"), let date = date(fromHref: hero["href"]),
           let lead = hero.first(class: "lead") {
            leads[date] = clean(lead.textContent)
        }
        var out: [IssueSummary] = []
        var seen = Set<String>()
        let archive = doc.first("section", class: "archive") ?? doc
        for a in archive.all("a") {
            guard let date = date(fromHref: a["href"]), !seen.contains(date),
                  let t = a.first("span", class: "t") else { continue }
            seen.insert(date)
            let topicNode = a.first("span", class: "topic")
            out.append(IssueSummary(
                date: date,
                topic: topicKey(topicNode),
                topicLabel: clean(topicNode?.textContent ?? ""),
                title: clean(t.textContent(excluding: ["small"])),
                zhTitle: clean(t.first("small")?.textContent ?? ""),
                lead: leads[date]
            ))
        }
        return out.sorted { $0.date > $1.date }
    }

    // MARK: issue page

    static func parseIssue(_ html: String, date fallbackDate: String) throws -> Issue {
        let doc = HTMLParser.parse(html)
        let body = doc.first("body")
        let date = body?["data-issue"] ?? fallbackDate
        guard let titleNode = doc.first("h1", class: "title") else { throw ParseError.missing("标题") }
        guard let article = doc.first("article", class: "article") else { throw ParseError.missing("正文") }
        let topicNode = doc.first(class: "kicker")?.first("span", class: "topic")

        var blocks: [ArticleBlock] = []
        var notes: [Annotation] = []
        for child in article.elementChildren {
            if child.hasClass("gap") {
                blocks.append(ArticleBlock(kind: .gap, segments: []))
                continue
            }
            for p in child.all("p", class: "para") {
                var segments: [Segment] = []
                collectSegments(p, note: nil, into: &segments)
                trim(&segments)
                if !segments.isEmpty { blocks.append(ArticleBlock(kind: .para, segments: segments)) }
            }
            for noteNode in child.all("div", class: "note") {
                if let a = annotation(noteNode) { notes.append(a) }
            }
        }
        if !blocks.contains(where: { $0.kind == .para }) { throw ParseError.missing("段落") }
        notes.sort { $0.n < $1.n }

        var audio: [AudioTrack] = []
        var words: [ReviewWord] = []
        var patterns: [SentencePattern] = []
        var podcast: Podcast?
        for section in doc.all("section", class: "block") where !section.hasClass("mynotes") {
            for player in section.all("div", class: "player") {
                guard let src = player.first("audio")?["src"] ?? player.first("source")?["src"] else { continue }
                let pl = player.first(class: "pl")
                audio.append(AudioTrack(
                    id: src.contains("slow") ? "slow" : "normal",
                    label: stripLeadingSymbols(clean(pl?.textContent(excluding: ["small"]) ?? "")),
                    detail: clean(pl?.first("small")?.textContent ?? ""),
                    file: src
                ))
            }
            if let table = section.first("table", class: "words") {
                for tr in table.all("tr") {
                    let w = tr.first("td", class: "w")
                    guard let word = w?.first("b")?.textContent else { continue }
                    words.append(ReviewWord(
                        word: clean(word),
                        ipa: clean(w?.first(class: "ipa")?.textContent ?? ""),
                        meaning: clean(tr.first("td", class: "zh")?.textContent ?? ""),
                        example: clean(tr.first("td", class: "ex")?.textContent(excluding: ["button"]) ?? "")
                    ))
                }
            }
            if let ol = section.first("ol", class: "patterns") {
                for li in ol.all("li") {
                    let pat = li.first(class: "pat")
                    var source = clean(li.first(class: "from")?.textContent ?? "")
                    if source.hasPrefix("原文：") { source = String(source.dropFirst(3)) }
                    patterns.append(SentencePattern(
                        pattern: clean(pat?.textContent(excluding: ["span"]) ?? ""),
                        patternZh: clean(pat?.first("span")?.textContent ?? ""),
                        source: source,
                        model: clean(li.first(class: "model")?.textContent(excluding: ["button"]) ?? ""),
                        modelZh: clean(li.first(class: "modelzh")?.textContent ?? "")
                    ))
                }
            }
            if let a = section.first("a", class: "podcast"), let href = a["href"] {
                var title = clean(a.first(class: "pt")?.textContent ?? "")
                if title.hasSuffix("↗") { title = clean(String(title.dropLast())) }
                podcast = Podcast(
                    source: clean(a.first(class: "ps")?.textContent ?? ""),
                    title: title,
                    summary: clean(a.first(class: "pz")?.textContent ?? ""),
                    url: href
                )
            }
        }

        var credit: Credit?
        if let c = doc.first("p", class: "credit") {
            var text = ""
            for child in c.children {
                if child.name == "br" { break }
                text += child.textContent
            }
            let links = c.all("a").compactMap { a in a["href"].map { WebLink(title: clean(a.textContent), url: $0) } }
            credit = Credit(text: clean(text), links: links)
        }

        return Issue(
            date: date,
            topic: topicKey(topicNode),
            topicLabel: clean(topicNode?.textContent ?? ""),
            dateLabel: clean(doc.first("header", class: "top")?.first(class: "date")?.textContent ?? ""),
            title: clean(titleNode.textContent),
            zhTitle: clean(doc.first("p", class: "zh-title")?.textContent ?? ""),
            byline: clean(doc.first("p", class: "byline")?.textContent ?? ""),
            lead: clean(doc.first("p", class: "lead")?.textContent ?? ""),
            blocks: blocks,
            notes: notes,
            credit: credit,
            audio: audio,
            words: words,
            patterns: patterns,
            podcast: podcast
        )
    }

    // MARK: helpers

    private static func collectSegments(_ node: HTMLNode, note: Int?, into segs: inout [Segment]) {
        for c in node.children {
            if c.isText {
                append(collapse(c.text), note: note, to: &segs)
            } else if c.name == "sup" {
                continue
            } else if c.name == "br" {
                append("\n", note: note, to: &segs)
            } else if c.name == "mark", c.hasClass("hl"), let n = c["data-n"].flatMap(Int.init) {
                collectSegments(c, note: n, into: &segs)
            } else if c.hasClass("un-hl") || c.hasClass("un-sup") {
                if c.hasClass("un-hl") { collectSegments(c, note: note, into: &segs) }
            } else {
                collectSegments(c, note: note, into: &segs)
            }
        }
    }

    private static func append(_ text: String, note: Int?, to segs: inout [Segment]) {
        guard !text.isEmpty else { return }
        if var last = segs.last, last.note == note {
            last.text += text
            segs[segs.count - 1] = last
        } else {
            segs.append(Segment(text: text, note: note))
        }
    }

    private static func trim(_ segs: inout [Segment]) {
        while let f = segs.first, f.note == nil, f.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { segs.removeFirst() }
        while let l = segs.last, l.note == nil, l.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { segs.removeLast() }
        if var f = segs.first {
            f.text = String(f.text.drop(while: { $0 == " " }))
            segs[0] = f
        }
        if var l = segs.last {
            while l.text.hasSuffix(" ") { l.text.removeLast() }
            segs[segs.count - 1] = l
        }
    }

    private static func annotation(_ node: HTMLNode) -> Annotation? {
        guard let n = node["data-n"].flatMap(Int.init) else { return nil }
        let kind: NoteKind = node.hasClass("t-grammar") ? .grammar : node.hasClass("t-idiom") ? .idiom : .vocab
        var tilt = 0.0
        if let style = node["style"], let r = style.range(of: "--tilt:") {
            let rest = style[r.upperBound...].prefix { "-0123456789.".contains($0) }
            tilt = Double(rest) ?? 0
        }
        return Annotation(
            n: n,
            kind: kind,
            tag: clean(node.first(class: "tag")?.textContent ?? kind.label),
            head: clean(node.first(class: "nh")?.textContent ?? ""),
            body: node.first(class: "nz").map(markup) ?? "",
            tilt: tilt
        )
    }

    /// Plain text with `<b>`/`<strong>` kept as `**…**`.
    private static func markup(_ node: HTMLNode) -> String {
        var out = ""
        for c in node.children {
            if c.isText { out += collapse(c.text) }
            else if c.name == "br" { out += "\n" }
            else if c.name == "b" || c.name == "strong" { out += "**" + markup(c) + "**" }
            else { out += markup(c) }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func topicKey(_ node: HTMLNode?) -> String {
        guard let node else { return "other" }
        for c in node.classes where c.hasPrefix("t-") { return String(c.dropFirst(2)) }
        return "other"
    }

    static func date(fromHref href: String?) -> String? {
        guard let href, let r = href.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        return String(href[r])
    }

    private static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: #"[ \t\r\n]+"#, with: " ", options: .regularExpression)
    }

    static func clean(_ s: String) -> String {
        collapse(s).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripLeadingSymbols(_ s: String) -> String {
        String(s.drop { ch in
            ch == " " || ch.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F }
        })
    }
}
