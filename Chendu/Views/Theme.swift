import CoreText
import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

/// Palette from the site's style.css.
enum Ink {
    static let paper = UIColor(hex: 0xFBF8F1)
    static let ink = UIColor(hex: 0x22201C)
    static let muted = UIColor(hex: 0x6F6A60)
    static let rule = UIColor(hex: 0xE7E0D0)
    static let card = UIColor.white
    static let vocab = UIColor(hex: 0x1F5FBF)
    static let grammar = UIColor(hex: 0xC2362B)
    static let idiom = UIColor(hex: 0x2F8A3E)
    static let user = UIColor(hex: 0xB35A00)
    static let vocabBG = UIColor(hex: 0x1F5FBF, alpha: 0.10)
    static let grammarBG = UIColor(hex: 0xC2362B, alpha: 0.09)
    static let idiomBG = UIColor(red: 118 / 255, green: 200 / 255, blue: 90 / 255, alpha: 0.28)
    static let idiomCardBG = UIColor(hex: 0x2F8A3E, alpha: 0.10)
    static let userBG = UIColor(red: 1, green: 170 / 255, blue: 40 / 255, alpha: 0.13)
    static let userHL = UIColor(red: 1, green: 190 / 255, blue: 70 / 255, alpha: 0.40)
    static let userHLOn = UIColor(red: 1, green: 160 / 255, blue: 30 / 255, alpha: 0.62)
    static let leadBG = UIColor(hex: 0xFFF6D9)
    static let leadInk = UIColor(hex: 0x5A4A2C)
    static let podcastBG = UIColor(hex: 0x1E1B2E)
    static let stocks = UIColor(hex: 0x1D6B52)
    static let ai = UIColor(hex: 0x5B3FA6)
    static let otherTopic = UIColor(hex: 0x8A6D3B)

    static func color(_ kind: NoteKind) -> UIColor {
        switch kind {
        case .vocab: vocab
        case .grammar: grammar
        case .idiom: idiom
        }
    }

    static func background(_ kind: NoteKind) -> UIColor {
        switch kind {
        case .vocab: vocabBG
        case .grammar: grammarBG
        case .idiom: idiomCardBG
        }
    }

    static func topic(_ key: String) -> UIColor {
        switch key {
        case "stocks": stocks
        case "ai": ai
        default: otherTopic
        }
    }
}

extension Color {
    static let paper = Color(Ink.paper)
    static let ink = Color(Ink.ink)
    static let muted = Color(Ink.muted)
    static let rule = Color(Ink.rule)
    static let grammarRed = Color(Ink.grammar)
    static let userInk = Color(Ink.user)
}

/// Ma Shan Zheng, used only for the wordmark and section headings. Article text uses the system font.
enum HandFont {
    private static let descriptors: [String: CTFontDescriptor] = {
        var out: [String: CTFontDescriptor] = [:]
        guard let url = Bundle.main.url(forResource: "MaShanZheng-Regular", withExtension: "ttf"),
              let data = try? Data(contentsOf: url),
              let descs = CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor] else { return out }
        for d in descs {
            let name = CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(d, 12, nil)) as String
            out[name] = d
        }
        return out
    }()

    private static func make(_ names: [String], _ size: CGFloat, fallback: UIFont) -> UIFont {
        for name in names {
            if let d = descriptors[name] { return CTFontCreateWithFontDescriptor(d, size, nil) as UIFont }
        }
        return fallback
    }

    static func zh(_ size: CGFloat) -> UIFont {
        make(["MaShanZheng-Regular"], size, fallback: .systemFont(ofSize: size))
    }

    static func serif(_ size: CGFloat, weight: UIFont.Weight = .regular, italic: Bool = false) -> UIFont {
        var d = UIFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        d = d.withDesign(.serif) ?? d
        if italic, let i = d.withSymbolicTraits(.traitItalic) { d = i }
        return UIFont(descriptor: d, size: size)
    }
}

extension Font {
    static func handZh(_ size: CGFloat) -> Font { Font(HandFont.zh(size) as CTFont) }
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
}

/// Faint dot grid like the site's body background.
struct PaperBackground: View {
    private static let tile: UIImage = {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        return r.image { ctx in
            Ink.paper.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            UIColor(white: 0, alpha: 0.035).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }()

    var body: some View {
        Image(uiImage: Self.tile).resizable(resizingMode: .tile).ignoresSafeArea()
    }
}

struct TopicChip: View {
    var key: String
    var label: String

    var body: some View {
        Text(label.isEmpty ? "精读" : label)
            .font(.system(size: 11, weight: .medium))
            .kerning(0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(Ink.topic(key))))
    }
}

/// Renders `**emphasis**` from annotation bodies in the note's color.
func emphasized(_ body: String, color: UIColor) -> AttributedString {
    var out = AttributedString()
    for (i, part) in body.components(separatedBy: "**").enumerated() {
        var a = AttributedString(part)
        if i % 2 == 1 { a.foregroundColor = Color(color) }
        out += a
    }
    return out
}

enum DateText {
    private static let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = shanghai
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let display: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = shanghai
        f.dateFormat = "M 月 d 日 EEE"
        return f
    }()

    static func short(_ date: String) -> String {
        guard let d = parser.date(from: date) else { return date }
        return display.string(from: d)
    }

    static func todayInShanghai() -> String { parser.string(from: .now) }
}
