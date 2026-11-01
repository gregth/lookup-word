// Draws a vocabulary file as a notes app shows it (title, "## Language" headings, tables) to a PNG, for the README:
// what Lookup Word's saves look like.
//
//   swift scripts/render-vocabulary.swift Vocabulary.md docs/vocabulary.png
import AppKit

let args = CommandLine.arguments
let text = try! String(contentsOfFile: args[1], encoding: .utf8)
let W: CGFloat = 900, pad: CGFloat = 36, scale: CGFloat = 2
let ink = NSColor(white: 0.92, alpha: 1), muted = NSColor(white: 0.6, alpha: 1), rule = NSColor(white: 1, alpha: 0.12)

enum Block { case title(String), heading(String), table([[String]]) }
var blocks: [Block] = [], rows: [[String]] = []
func flush() { if !rows.isEmpty { blocks.append(.table(rows)); rows = [] } }
for line in text.components(separatedBy: "\n") {
    if line.hasPrefix("|") {
        let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().dropLast().map { $0.trimmingCharacters(in: .whitespaces) }
        if !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) { rows.append(cells) }
        continue
    }
    flush()
    if line.hasPrefix("# ") { blocks.append(.title(String(line.dropFirst(2)))) }
    else if line.hasPrefix("## ") { blocks.append(.heading(String(line.dropFirst(3)))) }
}
flush()

func styled(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = ink) -> NSAttributedString {
    let bold = s.hasPrefix("**") && s.hasSuffix("**")
    return NSAttributedString(string: bold ? String(s.dropFirst(2).dropLast(2)) : s,
                              attributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : weight), .foregroundColor: color])
}
func height(_ a: NSAttributedString, _ w: CGFloat) -> CGFloat { ceil(a.boundingRect(with: NSSize(width: w, height: 1e4), options: [.usesLineFragmentOrigin]).height) }

// a table's column widths: the word as wide as its longest word, the rest sharing what is left in proportion to their
// longest text, within limits
func widths(_ t: [[String]]) -> [CGFloat] {
    let avail = W - 2 * pad, n = t[0].count
    let word = (t.map { styled($0[0], 14).size().width }.max() ?? 60) + 28
    let longest = (1..<n).map { c in CGFloat(t.map { $0.indices.contains(c) ? $0[c].count : 0 }.max() ?? 1) }
    let raw = longest.map { min(max($0, 10), 60) }, sum = raw.reduce(0, +)
    return [word] + raw.map { $0 / sum * (avail - word) }
}

// draw (or, with draw false, measure) the page; returns its height
func page(draw: Bool) -> CGFloat {
    var y: CGFloat = pad
    for b in blocks {
        switch b {
        case .title(let s):
            let a = styled(s, 26, .bold); if draw { a.draw(at: NSPoint(x: pad, y: y)) }; y += height(a, W) + 14
        case .heading(let s):
            y += 10
            let a = styled(s, 19, .semibold); if draw { a.draw(at: NSPoint(x: pad, y: y)) }; y += height(a, W) + 6
            if draw { rule.setFill(); NSRect(x: pad, y: y, width: W - 2 * pad, height: 1).fill() }; y += 10
        case .table(let t):
            let ws = widths(t)
            for (r, row) in t.enumerated() {
                let cells = row.enumerated().map { c, s in styled(s, r == 0 ? 13 : 14, r == 0 ? .semibold : .regular, r == 0 ? muted : ink) }
                let h = zip(cells, ws).map { height($0, $1 - 16) }.max() ?? 0
                if draw {
                    if r == 0 { NSColor(white: 1, alpha: 0.05).setFill(); NSRect(x: pad, y: y, width: W - 2 * pad, height: h + 14).fill() }
                    var x = pad
                    for (a, w) in zip(cells, ws) { a.draw(with: NSRect(x: x + 8, y: y + 7, width: w - 16, height: h), options: [.usesLineFragmentOrigin]); x += w }
                    rule.setFill(); NSRect(x: pad, y: y + h + 13, width: W - 2 * pad, height: 1).fill()
                }
                y += h + 14
            }
            y += 12
        }
    }
    return y + pad - 12
}

let H = page(draw: false)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
ctx.cgContext.translateBy(x: 0, y: H); ctx.cgContext.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
NSColor(white: 0.12, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
_ = page(draw: true)
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2]) \(Int(W))×\(Int(H))")
