// Draws docs/demo.gif (and the three mode GIFs: selecting, pointing, the type-a-word box): a sentence in each language, the pointer moving to a word, a double-tap of ⌥, and the card
// Lookup Word shows for it, with the four steps numbered along the bottom. The cards are the app's own, from `LookupWord --render WORD LANG docs/card-….png`; the
// window, pointer and steps around them are drawn here.
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

// the numbered steps along the bottom of the window, the current one lit
let steps = ["Point at a word", "Double-tap ⌥", "See the translations", "Word saved"]
func stepBar(_ current: Int) {
    let gap: CGFloat = 10, left = window.minX + 20, width = (window.width - 40 - gap * 3) / 4
    for (i, label) in steps.enumerated() {
        let on = i + 1 == current, done = i + 1 < current
        let r = NSRect(x: left + CGFloat(i) * (width + gap), y: H - 96, width: width, height: 48)
        (on ? NSColor(red: 0.5, green: 0.88, blue: 0.69, alpha: 0.22) : NSColor(white: 1, alpha: 0.06)).setFill()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
        let dot = NSRect(x: r.minX + 12, y: r.midY - 12, width: 24, height: 24)
        (on ? NSColor(red: 0.5, green: 0.88, blue: 0.69, alpha: 1) : NSColor(white: 1, alpha: done ? 0.45 : 0.18)).setFill()
        NSBezierPath(ovalIn: dot).fill()
        let n = NSAttributedString(string: "\(i + 1)", attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: NSColor(white: 0.1, alpha: 1)])
        n.draw(at: NSPoint(x: dot.midX - n.size().width / 2, y: dot.midY - n.size().height / 2))
        let t = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 13.5, weight: on ? .semibold : .regular),
                                                               .foregroundColor: NSColor(white: 1, alpha: on ? 1 : done ? 0.6 : 0.4)])
        t.draw(at: NSPoint(x: dot.maxX + 8, y: r.midY - t.size().height / 2))
    }
}

// The ⌥ key, up or pressed, in the window's empty upper right; and a ring spreading from the pointer on each tap.
func optionKey(pressed: Bool) {
    let up: CGFloat = pressed ? 0 : 5
    let base = NSRect(x: 640, y: 170, width: 120, height: 104)
    NSColor(white: 0.05, alpha: 1).setFill()  // the key's side
    NSBezierPath(roundedRect: base.offsetBy(dx: 0, dy: 5), xRadius: 16, yRadius: 16).fill()
    let top = base.offsetBy(dx: 0, dy: 5 - up - 5)
    (pressed ? NSColor(red: 0.5, green: 0.88, blue: 0.69, alpha: 1) : NSColor(white: 0.32, alpha: 1)).setFill()
    NSBezierPath(roundedRect: top, xRadius: 16, yRadius: 16).fill()
    let ink = pressed ? NSColor(white: 0.1, alpha: 1) : NSColor(white: 0.95, alpha: 1)
    let sym = NSAttributedString(string: "⌥", attributes: [.font: NSFont.systemFont(ofSize: 40, weight: .medium), .foregroundColor: ink])
    sym.draw(at: NSPoint(x: top.midX - sym.size().width / 2, y: top.minY + 14))
    let name = NSAttributedString(string: "option", attributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: ink])
    name.draw(at: NSPoint(x: top.midX - name.size().width / 2, y: top.maxY - 30))
}
func ring(at p: NSPoint, _ t: CGFloat) {  // t 0…1: grows and fades
    let r = 10 + 34 * t
    NSColor(red: 0.5, green: 0.88, blue: 0.69, alpha: 0.9 * (1 - t)).setStroke()
    let c = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)); c.lineWidth = 3; c.stroke()
}

// One frame: the window with its sentence and the steps, and optionally the pointer, the highlight and the card.
func frame(_ sc: Scene, pointerAt: NSPoint?, step: Int, card: NSImage?, wordRect: NSRect, key: Bool? = nil, ringAt: CGFloat? = nil,
           selected: CGFloat = 0) -> CGImage {
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
    if selected > 0 {  // the app's own selection behind the word, as far as the drag has reached (0…1)
        NSColor(red: 0.16, green: 0.38, blue: 0.86, alpha: 0.85).setFill()
        NSRect(x: wordRect.minX - 1, y: wordRect.minY + 1, width: (wordRect.width + 2) * selected, height: wordRect.height - 2).fill()
    } else if card != nil {
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
    if step > 0 { stepBar(step) }
    if let pressed = key { optionKey(pressed: pressed) }
    if let t = ringAt, let p = pointerAt { ring(at: NSPoint(x: p.x + 2, y: p.y + 2), t) }
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
    frames.append((frame(sc, pointerAt: at, step: 1, card: nil, wordRect: wordRect), 0.7))
    for i in 1...12 {  // the pointer glides to the word, easing out
        let t = 1 - pow(1 - Double(i) / 12, 3)
        let p = NSPoint(x: at.x + (target.x - at.x) * t, y: at.y + (target.y - at.y) * t)
        frames.append((frame(sc, pointerAt: p, step: 1, card: nil, wordRect: wordRect), 0.04))
    }
    // the double-tap: the key goes down and up twice, a ring spreading from the pointer with each tap
    frames.append((frame(sc, pointerAt: target, step: 2, card: nil, wordRect: wordRect, key: false), 0.3))
    for _ in 0..<2 {
        frames.append((frame(sc, pointerAt: target, step: 2, card: nil, wordRect: wordRect, key: true, ringAt: 0), 0.08))
        frames.append((frame(sc, pointerAt: target, step: 2, card: nil, wordRect: wordRect, key: true, ringAt: 0.35), 0.06))
        frames.append((frame(sc, pointerAt: target, step: 2, card: nil, wordRect: wordRect, key: false, ringAt: 0.7), 0.06))
        frames.append((frame(sc, pointerAt: target, step: 2, card: nil, wordRect: wordRect, key: false), 0.08))
    }
    frames.append((frame(sc, pointerAt: target, step: 3, card: card, wordRect: wordRect), 1.6))
    frames.append((frame(sc, pointerAt: target, step: 4, card: card, wordRect: wordRect), 1.6))
    at = NSPoint(x: target.x, y: 520)
}

// a GIF of each way to pick a word, cropped to the card and the sentence: selecting the word by dragging across it, and
// pointing at it with screen reading on; each with the double-tap and the card
func gif(_ name: String, _ frames: [(CGImage, Double)], crop: CGRect) {
    let url = docs.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (img, delay) in frames {
        CGImageDestinationAddImage(dest, img.cropping(to: crop)!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
    }
    print(CGImageDestinationFinalize(dest) ? "wrote docs/\(name), \(frames.count) frames" : "failed \(name)")
}
do {
    let sc = scenes[0]
    let card = NSImage(contentsOf: docs.appendingPathComponent(sc.card))!
    card.size = NSSize(width: CGFloat(card.representations[0].pixelsWide) / 2, height: CGFloat(card.representations[0].pixelsHigh) / 2)
    let attrs: [NSAttributedString.Key: Any] = [.font: textFont]
    let range = (sc.sentence as NSString).range(of: sc.word)
    let x0 = textOrigin.x + ((sc.sentence as NSString).substring(to: range.location) as NSString).size(withAttributes: attrs).width
    let size = (sc.word as NSString).size(withAttributes: attrs)
    let w = NSRect(x: x0, y: textOrigin.y, width: size.width, height: size.height)
    let crop = CGRect(x: 20, y: 110, width: W - 40, height: 400)
    let start = NSPoint(x: 320, y: 500)
    func glide(_ from: NSPoint, _ to: NSPoint, selected: CGFloat = 0) -> [(CGImage, Double)] {
        (1...10).map { i in
            let t = 1 - pow(1 - Double(i) / 10, 3)
            return (frame(sc, pointerAt: NSPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), step: 0, card: nil, wordRect: w, selected: selected), 0.04)
        }
    }
    func tap(at p: NSPoint, selected: CGFloat) -> [(CGImage, Double)] {
        var out = [(frame(sc, pointerAt: p, step: 0, card: nil, wordRect: w, key: false, selected: selected), 0.3)]
        for _ in 0..<2 {
            out.append((frame(sc, pointerAt: p, step: 0, card: nil, wordRect: w, key: true, ringAt: 0, selected: selected), 0.08))
            out.append((frame(sc, pointerAt: p, step: 0, card: nil, wordRect: w, key: true, ringAt: 0.35, selected: selected), 0.06))
            out.append((frame(sc, pointerAt: p, step: 0, card: nil, wordRect: w, key: false, ringAt: 0.7, selected: selected), 0.06))
            out.append((frame(sc, pointerAt: p, step: 0, card: nil, wordRect: w, key: false, selected: selected), 0.08))
        }
        return out
    }
    // selection: to the word's start, drag across it, double-tap, the card
    let left = NSPoint(x: w.minX, y: w.midY - 4), right = NSPoint(x: w.maxX, y: w.midY - 4)
    var sel = [(frame(sc, pointerAt: start, step: 0, card: nil, wordRect: w), 0.6)] + glide(start, left)
    sel += (1...10).map { i in
        let f = CGFloat(i) / 10
        return (frame(sc, pointerAt: NSPoint(x: left.x + (right.x - left.x) * f, y: left.y), step: 0, card: nil, wordRect: w, selected: f), 0.05)
    }
    sel += tap(at: right, selected: 1)
    sel.append((frame(sc, pointerAt: right, step: 0, card: card, wordRect: w, selected: 1), 3))
    gif("mode-selection.gif", sel, crop: crop)
    // screen reading: point at the word, nothing selected, double-tap, the word highlighted and the card
    let on = NSPoint(x: w.midX - 2, y: w.midY - 4)
    var scr = [(frame(sc, pointerAt: start, step: 0, card: nil, wordRect: w), 0.6)] + glide(start, on)
    scr += tap(at: on, selected: 0)
    scr.append((frame(sc, pointerAt: on, step: 0, card: card, wordRect: w), 3))
    gif("mode-screen.gif", scr, crop: crop)
}

// the type-a-word box: ⌃⌘L, the box near the top (as Type.swift lays it out: 400 × 44, the magnifier, the field, ⓧ and
// the pin), the word typed letter by letter, Return, and its card hanging below the box
do {
    let sc = Scene(language: "Notes", sentence: "Words to look up later: liep, outcome, είδε.", word: "liep", card: "card-dutch.png")
    let card = NSImage(contentsOf: docs.appendingPathComponent(sc.card))!
    card.size = NSSize(width: CGFloat(card.representations[0].pixelsWide) / 2, height: CGFloat(card.representations[0].pixelsHigh) / 2)
    let box = NSRect(x: (W - 400) / 2, y: 70, width: 400, height: 44)
    func symbol(_ name: String, _ size: CGFloat, _ color: NSColor, in r: NSRect) {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular).applying(.init(paletteColors: [color]))) else { return }
        img.draw(in: NSRect(x: r.midX - img.size.width / 2, y: r.midY - img.size.height / 2, width: img.size.width, height: img.size.height),
                 from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
    // the keys pressed, as chips in the window's lower right, lit while down
    func keys(_ labels: [String], lit: Bool) {
        var x = window.maxX - 30
        for label in labels.reversed() {
            let t = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .medium),
                                                                   .foregroundColor: lit ? NSColor(white: 0.1, alpha: 1) : NSColor(white: 0.95, alpha: 1)])
            let r = NSRect(x: x - max(56, t.size().width + 28), y: window.maxY - 82, width: max(56, t.size().width + 28), height: 52)
            (lit ? NSColor(red: 0.5, green: 0.88, blue: 0.69, alpha: 1) : NSColor(white: 0.32, alpha: 1)).setFill()
            NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
            t.draw(at: NSPoint(x: r.midX - t.size().width / 2, y: r.midY - t.size().height / 2))
            x = r.minX - 10
        }
    }
    func typeFrame(_ text: String?, keysDown: [String] = [], lit: Bool = false, showCard: Bool = false) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        ctx.cgContext.translateBy(x: 0, y: H); ctx.cgContext.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
        background.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
        windowColor.setFill(); NSBezierPath(roundedRect: window, xRadius: 12, yRadius: 12).fill()
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: window.minX + 18 + CGFloat(i) * 20, y: window.minY + 14, width: 12, height: 12)).fill()
        }
        NSAttributedString(string: sc.language, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.5)])
            .draw(at: NSPoint(x: window.midX - 20, y: window.minY + 11))
        NSAttributedString(string: sc.sentence, attributes: [.font: textFont, .foregroundColor: NSColor(white: 0.92, alpha: 1)]).draw(at: textOrigin)
        if let text {
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowBlurRadius = 14; shadow.shadowOffset = NSSize(width: 0, height: -4)
            shadow.shadowColor = NSColor(white: 0, alpha: 0.35); shadow.set()
            NSColor(white: 0.2, alpha: 1).setFill(); NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            symbol("text.magnifyingglass", 15, NSColor(white: 1, alpha: 0.55), in: NSRect(x: box.minX + 14, y: box.minY + 12, width: 20, height: 20))
            let font = NSFont.systemFont(ofSize: 16)
            let shown = NSAttributedString(string: text.isEmpty ? "Type a word, then Return" : text,
                                           attributes: [.font: font, .foregroundColor: NSColor(white: 1, alpha: text.isEmpty ? 0.3 : 0.92)])
            shown.draw(at: NSPoint(x: box.minX + 44, y: box.midY - shown.size().height / 2))
            let caretX = box.minX + 44 + (text.isEmpty ? 0 : shown.size().width) + 1
            NSColor.controlAccentColor.setFill(); NSRect(x: caretX, y: box.midY - 10, width: 2, height: 20).fill()
            if !text.isEmpty { symbol("xmark.circle.fill", 13, NSColor(white: 1, alpha: 0.3), in: NSRect(x: box.maxX - 64, y: box.minY + 10, width: 24, height: 24)) }
            symbol("pin", 13, NSColor(white: 1, alpha: 0.55), in: NSRect(x: box.maxX - 38, y: box.minY + 10, width: 24, height: 24))
        }
        if showCard {
            // the card's top part, below the box, with an arrow up to it
            let width: CGFloat = 420, src = NSRect(x: 0, y: card.size.height - min(card.size.height, 300), width: card.size.width, height: min(card.size.height, 300))
            let r = NSRect(x: box.midX - width / 2, y: box.maxY + 14, width: width, height: width * src.height / src.width)
            NSGraphicsContext.current?.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowBlurRadius = 18; shadow.shadowColor = NSColor(white: 0, alpha: 0.6); shadow.set()
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: box.midX - 11, y: r.minY + 1)); arrow.line(to: NSPoint(x: box.midX, y: r.minY - 11))
            arrow.line(to: NSPoint(x: box.midX + 11, y: r.minY + 1)); arrow.close()
            NSColor(white: 0.12, alpha: 1).setFill()
            let body = NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10); body.append(arrow); body.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).addClip()
            card.draw(in: r, from: src, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.current?.restoreGraphicsState()
        }
        if !keysDown.isEmpty { keys(keysDown, lit: lit) }
        NSGraphicsContext.current = nil
        return rep.cgImage!
    }
    let shortcut = ["⌃", "⌘", "L"]
    var typed = [(typeFrame(nil), 0.8), (typeFrame(nil, keysDown: shortcut), 0.3), (typeFrame(nil, keysDown: shortcut, lit: true), 0.25),
                 (typeFrame("", keysDown: shortcut), 0.6)]
    for n in 1...sc.word.count { typed.append((typeFrame(String(sc.word.prefix(n))), 0.18)) }
    typed += [(typeFrame(sc.word, keysDown: ["↩ return"]), 0.35), (typeFrame(sc.word, keysDown: ["↩ return"], lit: true), 0.2),
              (typeFrame(sc.word, showCard: true), 3.5)]
    gif("mode-type.gif", typed, crop: CGRect(x: 20, y: 20, width: W - 40, height: H - 40))
}

let out = docs.appendingPathComponent("demo.gif")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for (img, delay) in frames {
    CGImageDestinationAddImage(dest, img, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
}
print(CGImageDestinationFinalize(dest) ? "wrote \(out.path), \(frames.count) frames" : "failed")
