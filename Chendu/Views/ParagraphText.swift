import SwiftUI
import UIKit

/// A reader highlight resolved against the paragraph's plain text.
struct UserMark: Hashable {
    var id: UUID
    var range: NSRange
    var key: String { "u:\(id.uuidString)" }
}

/// Paragraph text plus inserted superscripts (note numbers, ✎), with offset mapping back to the plain text.
struct ParagraphRendering {
    let attributed: NSAttributedString
    let plain: String
    /// Inserted runs, ascending: position in plain text and length in UTF-16 units.
    let insertions: [(base: Int, length: Int)]
    /// Tag → plain-text range, for accessibility frames.
    let taggedRanges: [(tag: String, label: String, range: NSRange)]

    func displayToBase(_ d: Int) -> Int {
        var offset = 0
        for ins in insertions {
            let dpos = ins.base + offset
            if d >= dpos + ins.length { offset += ins.length }
            else if d >= dpos { return ins.base }
            else { break }
        }
        return d - offset
    }

    func baseToDisplay(_ b: Int) -> Int {
        var offset = 0
        for ins in insertions where ins.base < b { offset += ins.length }
        return b + offset
    }

    static func make(segments: [Segment], notes: [Int: Annotation], marks: [UserMark], activeKey: String?, fontSize: CGFloat) -> ParagraphRendering {
        let plain = segments.map(\.text).joined()
        let text = NSMutableAttributedString(string: plain)
        let full = NSRange(location: 0, length: text.length)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = fontSize * 0.55
        style.hyphenationFactor = 0
        text.addAttributes([
            .font: HandFont.serif(fontSize),
            .foregroundColor: Ink.ink,
            .paragraphStyle: style,
        ], range: full)

        var noteRanges: [(n: Int, range: NSRange)] = []
        var loc = 0
        for seg in segments {
            let len = (seg.text as NSString).length
            if let n = seg.note {
                if let last = noteRanges.last, last.n == n, NSMaxRange(last.range) == loc {
                    noteRanges[noteRanges.count - 1].range.length += len
                } else {
                    noteRanges.append((n, NSRange(location: loc, length: len)))
                }
            }
            loc += len
        }

        for (n, range) in noteRanges {
            let kind = notes[n]?.kind ?? .vocab
            let color = Ink.color(kind)
            switch kind {
            case .vocab:
                text.addAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue,
                                    .underlineColor: color], range: range)
            case .grammar:
                text.addAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: color], range: range)
            case .idiom:
                text.addAttribute(.backgroundColor, value: Ink.idiomBG, range: range)
            }
            if activeKey == "n:\(n)" {
                text.addAttribute(.backgroundColor, value: kind == .idiom ? Ink.idiomBG.withAlphaComponent(0.5) : Ink.background(kind).withAlphaComponent(0.22), range: range)
            }
        }

        for mark in marks where NSMaxRange(mark.range) <= text.length {
            text.addAttribute(.backgroundColor, value: activeKey == mark.key ? Ink.userHLOn : Ink.userHL, range: mark.range)
            text.addAttribute(.textItemTag, value: mark.key, range: mark.range)
        }
        // Built-in annotations win the tap where a reader highlight overlaps them.
        for (n, range) in noteRanges { text.addAttribute(.textItemTag, value: "n:\(n)", range: range) }

        var tagged: [(String, String, NSRange)] = noteRanges.map { ("n:\($0.n)", (plain as NSString).substring(with: $0.range), $0.range) }
        tagged += marks.filter { NSMaxRange($0.range) <= text.length }.map { ($0.key, (plain as NSString).substring(with: $0.range), $0.range) }

        var inserts: [(base: Int, order: Int, string: NSAttributedString)] = []
        let supSize = fontSize * 0.7
        for (n, range) in noteRanges {
            let kind = notes[n]?.kind ?? .vocab
            inserts.append((NSMaxRange(range), 0, NSAttributedString(string: "\(n)", attributes: [
                .font: HandFont.en(supSize + 2, bold: true),
                .foregroundColor: Ink.color(kind),
                .baselineOffset: fontSize * 0.4,
                .paragraphStyle: style,
                .textItemTag: "n:\(n)",
            ])))
        }
        for mark in marks where NSMaxRange(mark.range) <= text.length {
            inserts.append((NSMaxRange(mark.range), 1, NSAttributedString(string: "✎", attributes: [
                .font: UIFont.systemFont(ofSize: supSize, weight: .bold),
                .foregroundColor: Ink.user,
                .baselineOffset: fontSize * 0.4,
                .paragraphStyle: style,
                .textItemTag: mark.key,
            ])))
        }
        inserts.sort { ($0.base, $0.order) < ($1.base, $1.order) }
        for ins in inserts.reversed() { text.insert(ins.string, at: ins.base) }

        return ParagraphRendering(
            attributed: text,
            plain: plain,
            insertions: inserts.map { ($0.base, $0.string.length) },
            taggedRanges: tagged
        )
    }
}

struct ParagraphText: UIViewRepresentable {
    var index: Int
    var rendering: ParagraphRendering
    var onTapTag: (String) -> Void
    var onAddNote: (NSRange, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ParagraphContainer {
        let container = ParagraphContainer()
        container.textView.delegate = context.coordinator
        return container
    }

    func updateUIView(_ container: ParagraphContainer, context: Context) {
        context.coordinator.parent = self
        container.paragraphIndex = index
        container.rendering = rendering
        container.onTapTag = onTapTag
        let tv = container.textView
        if !tv.attributedText.isEqual(to: rendering.attributed) {
            tv.attributedText = rendering.attributed
            container.setNeedsLayout()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ParagraphContainer, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let size = uiView.textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ParagraphText?

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            guard case .tag(let tag) = textItem.content else { return defaultAction }
            return UIAction { [weak self] _ in self?.parent?.onTapTag(tag) }
        }

        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            if case .tag = textItem.content { return nil }
            return UITextItem.MenuConfiguration(menu: defaultMenu)
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0, let parent else { return UIMenu(children: suggestedActions) }
            let r = parent.rendering
            let start = r.displayToBase(range.location)
            let end = r.displayToBase(NSMaxRange(range))
            var base = NSRange(location: start, length: max(0, end - start))
            let ns = r.plain as NSString
            // Trim surrounding whitespace so the anchor quote is clean.
            while base.length > 0, ns.substring(with: NSRange(location: base.location, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                base.location += 1; base.length -= 1
            }
            while base.length > 0, ns.substring(with: NSRange(location: NSMaxRange(base) - 1, length: 1)).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                base.length -= 1
            }
            guard base.length > 0 else { return UIMenu(children: suggestedActions) }
            let quote = ns.substring(with: base)
            let add = UIAction(title: "加笔记", image: UIImage(systemName: "square.and.pencil")) { [weak textView] _ in
                textView?.selectedRange = NSRange(location: 0, length: 0)
                parent.onAddNote(base, quote)
            }
            add.accessibilityIdentifier = "addNoteAction"
            return UIMenu(children: [add] + suggestedActions)
        }
    }
}

/// Hosts the paragraph's text view plus transparent marker views over each annotated phrase, so the phrases
/// are reachable by VoiceOver and UI tests (UITextView itself is an accessibility leaf). Markers don't take touches.
final class ParagraphContainer: UIView {
    let textView = UITextView()
    var paragraphIndex = 0 {
        didSet { textView.accessibilityIdentifier = "para-\(paragraphIndex)" }
    }
    var rendering: ParagraphRendering? {
        didSet { rebuildMarkers() }
    }
    var onTapTag: ((String) -> Void)?
    private var markers: [Marker] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        let tv = textView
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.linkTextAttributes = [:]
        tv.dataDetectorTypes = []
        addSubview(tv)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
        textView.layoutIfNeeded()
        for m in markers { m.frame = rect(for: m.displayRange) }
    }

    private func rebuildMarkers() {
        guard let rendering else { return }
        let signature = rendering.taggedRanges.map { "\($0.tag)@\($0.range.location)" }
        guard signature != markers.map({ "\($0.noteTag)@\($0.baseLocation)" }) else { return }
        markers.forEach { $0.removeFromSuperview() }
        markers = rendering.taggedRanges.map { item in
            let m = Marker()
            m.noteTag = item.tag
            m.baseLocation = item.range.location
            m.displayRange = NSRange(location: rendering.baseToDisplay(item.range.location), length: item.range.length)
            m.isAccessibilityElement = true
            m.accessibilityLabel = item.label
            m.accessibilityHint = item.tag.hasPrefix("n:") ? "查看批注" : "查看我的笔记"
            m.accessibilityIdentifier = item.tag.hasPrefix("n:") ? "note-\(item.tag.dropFirst(2))" : "usernote-\(item.tag.dropFirst(2))"
            m.accessibilityTraits = .button
            m.activate = { [weak self] in self?.onTapTag?(item.tag) }
            addSubview(m)
            return m
        }
        setNeedsLayout()
    }

    private func rect(for displayRange: NSRange) -> CGRect {
        let tv = textView
        guard let p0 = tv.position(from: tv.beginningOfDocument, offset: displayRange.location),
              let p1 = tv.position(from: p0, offset: displayRange.length),
              let range = tv.textRange(from: p0, to: p1) else { return .zero }
        let r = tv.firstRect(for: range)
        return r.isNull || r.isInfinite ? .zero : tv.convert(r, to: self)
    }

    private final class Marker: UIView {
        var noteTag = ""
        var baseLocation = 0
        var displayRange = NSRange(location: 0, length: 0)
        var activate: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError() }

        override func accessibilityActivate() -> Bool {
            activate?()
            return true
        }
    }
}
