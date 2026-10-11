import Foundation

/// A small, tolerant HTML tree. Enough for the site's generated markup; not a general HTML5 parser.
final class HTMLNode {
    let name: String
    let text: String
    var attributes: [String: String]
    private(set) var children: [HTMLNode] = []

    var isText: Bool { name == "#text" }

    init(element name: String, attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
        self.text = ""
    }

    init(text: String) {
        self.name = "#text"
        self.attributes = [:]
        self.text = text
    }

    func append(_ child: HTMLNode) { children.append(child) }

    subscript(attribute: String) -> String? { attributes[attribute] }

    var classes: [Substring] { (attributes["class"] ?? "").split(whereSeparator: \.isWhitespace) }

    func hasClass(_ c: String) -> Bool { classes.contains { $0 == c } }

    var elementChildren: [HTMLNode] { children.filter { !$0.isText } }

    /// Text with `<br>` as newline, skipping any element named in `excluding` or carrying a class in `excludingClasses`.
    func textContent(excluding: Set<String> = [], excludingClasses: Set<String> = []) -> String {
        if isText { return text }
        if name == "br" { return "\n" }
        var out = ""
        for c in children {
            if !c.isText, excluding.contains(c.name) || c.classes.contains(where: { excludingClasses.contains(String($0)) }) { continue }
            out += c.textContent(excluding: excluding, excludingClasses: excludingClasses)
        }
        return out
    }

    var textContent: String { textContent() }

    func first(where match: (HTMLNode) -> Bool) -> HTMLNode? {
        for c in children where !c.isText {
            if match(c) { return c }
            if let found = c.first(where: match) { return found }
        }
        return nil
    }

    func all(where match: (HTMLNode) -> Bool) -> [HTMLNode] {
        var out: [HTMLNode] = []
        for c in children where !c.isText {
            if match(c) { out.append(c) }
            out += c.all(where: match)
        }
        return out
    }

    func first(_ tag: String? = nil, class cls: String? = nil) -> HTMLNode? {
        first { (tag == nil || $0.name == tag) && (cls == nil || $0.hasClass(cls!)) }
    }

    func all(_ tag: String? = nil, class cls: String? = nil) -> [HTMLNode] {
        all { (tag == nil || $0.name == tag) && (cls == nil || $0.hasClass(cls!)) }
    }
}

enum HTMLParser {
    private static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]
    private static let rawTextTags: Set<String> = ["script", "style", "textarea", "title"]

    static func parse(_ html: String) -> HTMLNode {
        let b = Array(html.utf8)
        let n = b.count
        let root = HTMLNode(element: "#document")
        var stack = [root]
        var i = 0
        var textStart = 0

        func flushText(_ end: Int) {
            if end > textStart {
                let raw = String(decoding: b[textStart..<end], as: UTF8.self)
                stack.last!.append(HTMLNode(text: decodeEntities(raw)))
            }
        }
        func isNameByte(_ c: UInt8) -> Bool {
            (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x5F || c == 0x3A
        }
        func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C }
        func find(_ needle: [UInt8], from start: Int, caseInsensitive: Bool = false) -> Int? {
            guard needle.count <= n else { return nil }
            var j = start
            while j + needle.count <= n {
                var ok = true
                for k in 0..<needle.count {
                    var c = b[j + k]
                    if caseInsensitive, c >= 0x41 && c <= 0x5A { c += 0x20 }
                    if c != needle[k] { ok = false; break }
                }
                if ok { return j }
                j += 1
            }
            return nil
        }

        while i < n {
            guard b[i] == 0x3C, i + 1 < n else { i += 1; continue } // '<'
            let next = b[i + 1]
            if next == 0x21 || next == 0x3F { // '!' or '?': comment, doctype, PI
                flushText(i)
                if find(Array("<!--".utf8), from: i) == i {
                    i = (find(Array("-->".utf8), from: i + 4).map { $0 + 3 }) ?? n
                } else {
                    i = (find([0x3E], from: i).map { $0 + 1 }) ?? n
                }
                textStart = i
                continue
            }
            if next == 0x2F { // closing tag
                var j = i + 2
                while j < n, isNameByte(b[j]) { j += 1 }
                let name = String(decoding: b[(i + 2)..<j], as: UTF8.self).lowercased()
                guard !name.isEmpty else { i += 1; continue }
                flushText(i)
                i = (find([0x3E], from: j).map { $0 + 1 }) ?? n
                textStart = i
                if let idx = stack.lastIndex(where: { $0.name == name }), idx > 0 {
                    stack.removeSubrange(idx...)
                }
                continue
            }
            guard (next >= 0x61 && next <= 0x7A) || (next >= 0x41 && next <= 0x5A) else { i += 1; continue }

            flushText(i)
            var j = i + 1
            while j < n, isNameByte(b[j]) { j += 1 }
            let name = String(decoding: b[(i + 1)..<j], as: UTF8.self).lowercased()
            var attrs: [String: String] = [:]
            var selfClosing = false
            while j < n {
                while j < n, isSpace(b[j]) { j += 1 }
                guard j < n else { break }
                if b[j] == 0x3E { j += 1; break }
                if b[j] == 0x2F { selfClosing = true; j += 1; continue }
                let ns = j
                while j < n, !isSpace(b[j]), b[j] != 0x3D, b[j] != 0x3E, b[j] != 0x2F { j += 1 }
                let attrName = String(decoding: b[ns..<j], as: UTF8.self).lowercased()
                while j < n, isSpace(b[j]) { j += 1 }
                var value = ""
                if j < n, b[j] == 0x3D {
                    j += 1
                    while j < n, isSpace(b[j]) { j += 1 }
                    if j < n, b[j] == 0x22 || b[j] == 0x27 {
                        let q = b[j]
                        let vs = j + 1
                        j = vs
                        while j < n, b[j] != q { j += 1 }
                        value = String(decoding: b[vs..<min(j, n)], as: UTF8.self)
                        j += 1
                    } else {
                        let vs = j
                        while j < n, !isSpace(b[j]), b[j] != 0x3E { j += 1 }
                        value = String(decoding: b[vs..<j], as: UTF8.self)
                    }
                }
                if !attrName.isEmpty { attrs[attrName] = decodeEntities(value) }
                selfClosing = false
            }
            let node = HTMLNode(element: name, attributes: attrs)
            stack.last!.append(node)
            i = j
            textStart = i
            if voidTags.contains(name) || selfClosing { continue }
            if rawTextTags.contains(name) {
                let end = find(Array("</\(name)".utf8), from: i, caseInsensitive: true) ?? n
                if end > i {
                    let raw = String(decoding: b[i..<end], as: UTF8.self)
                    node.append(HTMLNode(text: name == "title" || name == "textarea" ? decodeEntities(raw) : raw))
                }
                i = (find([0x3E], from: end).map { $0 + 1 }) ?? n
                textStart = i
                continue
            }
            stack.append(node)
        }
        flushText(n)
        return root
    }

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "mdash": "—", "ndash": "–", "hellip": "…", "rsquo": "’", "lsquo": "‘", "ldquo": "“", "rdquo": "”",
        "times": "×", "middot": "·", "copy": "©", "rarr": "→", "larr": "←", "bull": "•", "eacute": "é",
    ]

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        out.reserveCapacity(s.count)
        var idx = s.startIndex
        while idx < s.endIndex {
            let c = s[idx]
            guard c == "&", let semi = s[idx...].prefix(12).firstIndex(of: ";") else {
                out.append(c)
                idx = s.index(after: idx)
                continue
            }
            let body = s[s.index(after: idx)..<semi]
            var replacement: String?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                if let v = UInt32(body.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { replacement = String(Character(u)) }
            } else if body.hasPrefix("#") {
                if let v = UInt32(body.dropFirst()), let u = Unicode.Scalar(v) { replacement = String(Character(u)) }
            } else {
                replacement = named[String(body)]
            }
            if let r = replacement {
                out += r
                idx = s.index(after: semi)
            } else {
                out.append(c)
                idx = s.index(after: idx)
            }
        }
        return out
    }
}
