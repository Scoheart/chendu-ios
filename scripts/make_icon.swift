// Renders the app icon and lock-screen artwork: `swift scripts/make_icon.swift`
import AppKit
import CoreText

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fontURL = root.appendingPathComponent("Chendu/Resources/Fonts/MaShanZheng-Regular.ttf")
let descs = CTFontManagerCreateFontDescriptorsFromData(try! Data(contentsOf: fontURL) as CFData) as! [CTFontDescriptor]

func render(size: Int, to path: String) {
    let s = CGFloat(size)
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 0.984, green: 0.973, blue: 0.945, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    // dot grid
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.05))
    let step = s / 64
    var y: CGFloat = 0
    while y < s { var x: CGFloat = 0; while x < s { ctx.fill(CGRect(x: x, y: y, width: step / 4, height: step / 4)); x += step }; y += step }
    // ruled line
    ctx.setStrokeColor(CGColor(srgbRed: 0.906, green: 0.878, blue: 0.816, alpha: 1))
    ctx.setLineWidth(s * 0.006)
    ctx.setLineDash(phase: 0, lengths: [s * 0.02, s * 0.015])
    ctx.move(to: CGPoint(x: s * 0.12, y: s * 0.2)); ctx.addLine(to: CGPoint(x: s * 0.88, y: s * 0.2)); ctx.strokePath()

    let font = CTFontCreateWithFontDescriptor(descs[0], s * 0.62, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(srgbRed: 0.761, green: 0.212, blue: 0.169, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "晨", attributes: attrs))
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.saveGState()
    ctx.translateBy(x: s / 2, y: s * 0.56)
    ctx.rotate(by: -0.04)
    ctx.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
    // blue wavy underline like a vocab mark
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.setStrokeColor(CGColor(srgbRed: 0.122, green: 0.373, blue: 0.749, alpha: 1))
    ctx.setLineWidth(s * 0.018)
    ctx.setLineCap(.round)
    let wave = CGMutablePath()
    wave.move(to: CGPoint(x: s * 0.24, y: s * 0.235))
    var x = s * 0.24
    var up = true
    while x < s * 0.76 {
        wave.addQuadCurve(to: CGPoint(x: x + s * 0.065, y: s * 0.235), control: CGPoint(x: x + s * 0.0325, y: s * (up ? 0.265 : 0.205)))
        x += s * 0.065; up.toggle()
    }
    ctx.addPath(wave); ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let assets = root.appendingPathComponent("Chendu/Resources/Assets.xcassets")
render(size: 1024, to: assets.appendingPathComponent("AppIcon.appiconset/icon-1024.png").path)
render(size: 600, to: assets.appendingPathComponent("Artwork.imageset/artwork.png").path)
print("ok")
