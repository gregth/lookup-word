// Draws docs/demo.gif: a sentence in each language, the pointer moving to a word, a double-tap of ⌥, and the card
// Lookup Word shows for it. The cards are the app's own, from `LookupWord --render WORD LANG docs/card-….png`; the
// window, pointer and key badge around them are drawn here.
//
//   swift scripts/make-demo.swift      (from the repository root, after rendering the cards)
import AppKit
import ImageIO
import UniformTypeIdentifiers

let docs = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs")
let W: CGFloat = 880, H: CGFloat = 600

struct Scene { var language: String; var sentence: String; var word: String; var card: String }
let scenes = [
    Scene(language: "English", sentence: "The outcome of the review was better than expected.", word: "outcome", card: "card-outcome.png"),
    Scene(language: "Nederlands", sentence: "Gisteren liep ik langs de gracht naar huis.", word: "liep", card: "card-dutch.png"),
    Scene(language: "Ελληνικά", sentence: "Τον είδε στο σταθμό χθες το βράδυ.", word: "είδε", card: "card-greek.png"),
]

let window = NSRect(x: 20, y: 20, width: W - 40, height: H - 40)  // top-left origin: the context below is flipped
let textFont = NSFont.systemFont(ofSize: 24)
let textOrigin = NSPoint(x: 60, y: 430)
let background = NSColor(white: 0.07, alpha: 1), windowColor = NSColor(white: 0.14, alpha: 1)

func pointer(at p: NSPoint) {
    let path = NSBezierPath()  // the standard arrow, 22 pt tall
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 20), (5, 15.5), (8.5, 22.5), (11.5, 21), (8, 14.2), (14.5, 14.2)]
    path.move(to: NSPoint(x: p.x + pts[0].0, y: p.y + pts[0].1))
    for (x, y) in pts.dropFirst() { path.line(to: NSPoint(x: p.x + x, y: p.y + y)) }
    path.close()
    NSColor.black.setFill(); path.fill()
    NSColor.white.setStroke(); path.lineWidth = 1.5; path.stroke()
}

// a note in the window's bottom-right corner: the shortcut, then the save
func badge(_ text: String, _ alpha: CGFloat, color: NSColor = .white) {
    let font = NSFont.systemFont(ofSize: 18, weight: .semibold)
    let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color.withAlphaComponent(alpha)])
    let w = s.size().width + 36
    let r = NSRect(x: W - 40 - w, y: H - 92, width: w, height: 44)
    NSColor(white: 1, alpha: 0.14 * alpha).setFill()
    NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
    s.draw(at: NSPoint(x: r.minX + 18, y: r.minY + 11))
}

// One frame: the window with its sentence, and optionally the pointer, the badge, the highlight and the card.
func frame(_ sc: Scene, pointerAt: NSPoint?, badgeAlpha: CGFloat, card: NSImage?, wordRect: NSRect, saved: Bool = false) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.cgContext.translateBy(x: 0, y: H); ctx.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    background.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    windowColor.setFill(); NSBezierPath(roundedRect: window, xRadius: 12, yRadius: 12).fill()
    for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {  // the title bar's buttons
        c.setFill(); NSBezierPath(ovalIn: NSRect(x: window.minX + 18 + CGFloat(i) * 20, y: window.minY + 14, width: 12, height: 12)).fill()
    }
    NSAttributedString(string: sc.language, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                         .foregroundColor: NSColor(white: 1, alpha: 0.5)])
        .draw(at: NSPoint(x: window.midX - 30, y: window.minY + 11))
    if card != nil {
        NSColor.systemYellow.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: wordRect.insetBy(dx: -2, dy: 0), xRadius: 3, yRadius: 3).fill()
    }
    NSAttributedString(string: sc.sentence, attributes: [.font: textFont, .foregroundColor: NSColor(white: 0.92, alpha: 1)]).draw(at: textOrigin)
    if let card {
        // the card above the word, as Look Up's popover: its top part, with an arrow down to the word
        let width: CGFloat = 420, src = NSRect(x: 0, y: card.size.height - min(card.size.height, 300), width: card.size.width, height: min(card.size.height, 300))
        let height = width * src.height / src.width
        let x = min(max(wordRect.midX - width / 2, window.minX + 16), window.maxX - width - 16)
        let r = NSRect(x: x, y: wordRect.minY - 14 - height, width: width, height: height)
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowBlurRadius = 18; shadow.shadowColor = NSColor(white: 0, alpha: 0.6); shadow.set()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: wordRect.midX - 11, y: r.maxY - 1)); arrow.line(to: NSPoint(x: wordRect.midX, y: r.maxY + 11))
        arrow.line(to: NSPoint(x: wordRect.midX + 11, y: r.maxY - 1)); arrow.close()
        NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB).map { _ in NSColor(white: 0.12, alpha: 1) }!.setFill()
        let body = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10); body.append(arrow); body.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).addClip()
        card.draw(in: r, from: src, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        NSGraphicsContext.current?.restoreGraphicsState()
    }
    if badgeAlpha > 0 { badge("⌥ ⌥  double-tap", badgeAlpha) }
    if saved { badge("✓ Saved to your vocabulary", 1, color: NSColor(red: 0.5, green: 0.88, blue: 0.69, alpha: 1)) }
    if let p = pointerAt { pointer(at: p) }
    NSGraphicsContext.current = nil
    return rep.cgImage!
}

var frames: [(CGImage, Double)] = []
var at = NSPoint(x: 120, y: 520)  // where the pointer starts
for sc in scenes {
    let card = NSImage(contentsOf: docs.appendingPathComponent(sc.card))!
    card.size = NSSize(width: CGFloat(card.representations[0].pixelsWide) / 2, height: CGFloat(card.representations[0].pixelsHigh) / 2)
    let attrs: [NSAttributedString.Key: Any] = [.font: textFont]
    let range = (sc.sentence as NSString).range(of: sc.word)
    let before = (sc.sentence as NSString).substring(to: range.location)
    let x0 = textOrigin.x + (before as NSString).size(withAttributes: attrs).width
    let size = (sc.word as NSString).size(withAttributes: attrs)
    let wordRect = NSRect(x: x0, y: textOrigin.y, width: size.width, height: size.height)
    let target = NSPoint(x: wordRect.midX - 2, y: wordRect.midY - 4)
    frames.append((frame(sc, pointerAt: at, badgeAlpha: 0, card: nil, wordRect: wordRect), 0.7))
    for i in 1...12 {  // the pointer glides to the word, easing out
        let t = 1 - pow(1 - Double(i) / 12, 3)
        let p = NSPoint(x: at.x + (target.x - at.x) * t, y: at.y + (target.y - at.y) * t)
        frames.append((frame(sc, pointerAt: p, badgeAlpha: 0, card: nil, wordRect: wordRect), 0.04))
    }
    frames.append((frame(sc, pointerAt: target, badgeAlpha: 1, card: nil, wordRect: wordRect), 0.5))
    frames.append((frame(sc, pointerAt: target, badgeAlpha: 1, card: card, wordRect: wordRect), 0.6))
    frames.append((frame(sc, pointerAt: target, badgeAlpha: 0, card: card, wordRect: wordRect, saved: true), 2.6))
    at = NSPoint(x: target.x, y: 520)
}

let out = docs.appendingPathComponent("demo.gif")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (img, delay) in frames {
    CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
}
print(CGImageDestinationFinalize(dest) ? "wrote \(out.path), \(frames.count) frames" : "failed")
