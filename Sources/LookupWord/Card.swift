// The popover, as Look Up draws it: the headword, its pronunciation and a 🔈; the word in the other languages, each
// with a 🔈; then each dictionary's entry; and whether the word was saved.
import AppKit
import AVFoundation

let serif = { (size: CGFloat, weight: NSFont.Weight) -> NSFont in
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: f.fontDescriptor.withDesign(.serif) ?? f.fontDescriptor, size: size) ?? f
}
func italic(_ f: NSFont) -> NSFont { NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(.italic), size: f.pointSize) ?? f }

func run(_ s: String, _ font: NSFont, _ color: NSColor = .labelColor) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
}

// a speaker button that says the text in that language: the system's speaker symbol, in the accent colour
func speaker(_ text: String, _ lang: String, size: CGFloat = 14) -> NSAttributedString {
    var u = URLComponents(); u.scheme = "say"; u.host = lang; u.queryItems = [URLQueryItem(name: "t", value: text)]
    let out = NSMutableAttributedString(string: "  ")
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium).applying(.init(paletteColors: [.controlAccentColor]))
    if let image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Say it")?.withSymbolConfiguration(config) {
        let a = NSTextAttachment()
        a.image = image
        a.bounds = NSRect(x: 0, y: -2, width: image.size.width, height: image.size.height)
        out.append(NSAttributedString(attachment: a))
    } else { out.append(NSAttributedString(string: "🔈")) }
    out.addAttributes([.link: u.url!, .cursor: NSCursor.pointingHand], range: NSRange(location: 2, length: out.length - 2))
    return out
}

// One dictionary's plain text, laid out as Look Up shows it: each sense, example (▸), sub-sense (•) and section
// (DERIVATIVES, ORIGIN…) on its own line; the headword bold, pronunciations and examples muted, examples in italics.
func indent(_ first: CGFloat, _ rest: CGFloat, tab: CGFloat? = nil) -> NSParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.firstLineHeadIndent = first
    p.headIndent = rest
    p.paragraphSpacingBefore = 3
    if let tab { p.tabStops = [NSTextTab(textAlignment: .left, location: tab)] }
    return p
}

func formatted(_ text: String) -> NSAttributedString {
    var t = replacing(text, #"\s*\b(DERIVATIVES|PHRASES|PHRASAL VERBS|IDIOMS|ORIGIN|ANTONYMS|USAGE|SYNONYMS)\b\s*"#, "\n\n$1\n")
    t = replacing(t, #"\s*▸\s*"#, "\n▸ ")
    t = replacing(t, #"\s*•\s*"#, "\n• ")
    t = replacing(t, #"\s(\d{1,2})\.?(?:\s(?=[\p{L}\[(<])|(?![a-z]{2}\b)(?=\p{L}))"#, "\n$1\t")  // senses, not "18th"
    let body = serif(15, .regular), out = NSMutableAttributedString()
    for (i, line) in t.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).enumerated() {
        if i > 0 { out.append(run("\n", body)) }
        if matches(line, #"^[A-Z][A-Z ]+$"#) { out.append(run(line, .systemFont(ofSize: 11, weight: .semibold), .secondaryLabelColor)); continue }
        if line.hasPrefix("▸") {
            let m = NSMutableAttributedString(attributedString: run(line, italic(serif(14, .regular)), .secondaryLabelColor))
            m.addAttribute(.paragraphStyle, value: indent(20, 32), range: NSRange(location: 0, length: m.length))
            out.append(m); continue
        }
        let m = NSMutableAttributedString(attributedString: run(line, body))
        // a sense: its number hanging, its text indented; a sub-sense further in; anything else under the senses
        let style = matches(line, #"^\d{1,2}\t"#) ? indent(0, 20, tab: 20) : line.hasPrefix("•") ? indent(20, 32) : indent(i == 0 ? 0 : 20, 20)
        m.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: m.length))
        let ns = m.string as NSString
        if i == 0, let r = m.string.range(of: #"^[^|]+?(?=\s*\||\s)"#, options: .regularExpression) {
            m.addAttribute(.font, value: serif(17, .bold), range: NSRange(r, in: m.string))
        }
        for r in (try? NSRegularExpression(pattern: #"\|[^|]+\|"#))?.matches(in: m.string, range: NSRange(location: 0, length: ns.length)) ?? [] {
            m.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r.range)
        }
        for r in (try? NSRegularExpression(pattern: #"\[[^\]]+\]"#))?.matches(in: m.string, range: NSRange(location: 0, length: ns.length)) ?? [] {
            m.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r.range)  // [mass noun], [with object]
        }
        if let r = m.string.range(of: #"(?<=: ).+$"#, options: .regularExpression) {  // an example after the colon
            m.addAttributes([.font: italic(body), .foregroundColor: NSColor.secondaryLabelColor], range: NSRange(r, in: m.string))
        }
        out.append(m)
    }
    return out
}

let cardWidth: CGFloat = 460

func card(_ e: Entry, status: String) -> NSAttributedString {
    let out = NSMutableAttributedString()
    out.append(run(e.word, serif(26, .bold)))
    if !e.ipa.isEmpty { out.append(run("  | \(e.ipa) |", serif(16, .regular), .secondaryLabelColor)) }
    out.append(speaker(e.word, e.lang))
    for (code, words) in e.tr where !words.isEmpty {
        out.append(run("\n" + (pack(code)?.flag ?? code.uppercased()) + "  ", .systemFont(ofSize: 15)))
        out.append(run(words, serif(17, .semibold)))
        out.append(speaker(words, code))
    }
    for (name, text) in e.sections {
        // the dictionary's name and a thin rule to the right edge, as Look Up's: a line drawn as an attachment as wide
        // as what is left of the row
        let font = NSFont.systemFont(ofSize: 20, weight: .light)
        let title = NSMutableAttributedString(string: "\n" + name + "  ", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        let room = cardWidth - 2 * 24 - 16 - (name + "  " as NSString).size(withAttributes: [.font: font]).width  // the card's margins
        if room > 20 {
            let line = NSImage(size: NSSize(width: room, height: 1), flipped: false) { r in NSColor.separatorColor.setFill(); r.fill(); return true }
            let rule = NSTextAttachment()
            rule.image = line
            rule.bounds = NSRect(x: 0, y: font.xHeight / 2, width: room, height: 1)
            title.append(NSAttributedString(attachment: rule))
        }
        title.append(NSAttributedString(string: "\n"))
        let gap = NSMutableParagraphStyle(); gap.paragraphSpacingBefore = 16; gap.paragraphSpacing = 4  // not a blank line
        title.addAttribute(.paragraphStyle, value: gap, range: NSRange(location: 0, length: title.length))
        out.append(title)
        out.append(formatted(text))
    }
    if !status.isEmpty { out.append(run("\n\n" + status, .systemFont(ofSize: 11), .tertiaryLabelColor)) }
    return out
}

// a message for the card, with an optional button below it: a link the card handles (textView(_:clickedOnLink:at:))
func message(_ s: String, action: (title: String, url: String)? = nil) -> NSAttributedString {
    let m = NSMutableAttributedString(attributedString: run(s, .systemFont(ofSize: 13)))
    if let action, let url = URL(string: action.url) {
        m.append(run("\n\n", .systemFont(ofSize: 13)))
        m.append(NSAttributedString(string: action.title, attributes: [.link: url, .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                                     .foregroundColor: NSColor.controlAccentColor, .cursor: NSCursor.pointingHand]))
    }
    return m
}

let voice = AVSpeechSynthesizer()
func speak(_ text: String, _ lang: String) {
    let u = AVSpeechUtterance(string: text)
    u.voice = AVSpeechSynthesisVoice(language: pack(lang)?.voice ?? "en-GB")
    u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
    voice.stopSpeaking(at: .immediate)
    voice.speak(u)
}

final class Card: NSViewController, NSTextViewDelegate {
    let text = NSTextView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: 100))
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: cardWidth, height: 100))
    override func loadView() {
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 24, height: 20)  // Look Up's margins
        text.textContainer?.widthTracksTextView = true
        text.delegate = self
        text.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay  // a scroller that takes no width, so the text wraps as measured
        scroll.automaticallyAdjustsContentInsets = false  // no inset of its own, so it opens at the top
        scroll.contentInsets = NSEdgeInsets()
        scroll.drawsBackground = true  // a solid card, not the popover's see-through glass
        scroll.backgroundColor = .windowBackgroundColor
        view = scroll
    }
    func set(_ s: NSAttributedString) {
        _ = view
        text.textStorage?.setAttributedString(s)
        // measured at the card's own width, its margins included
        text.frame.size.width = cardWidth
        text.textContainer?.containerSize = NSSize(width: cardWidth - 2 * text.textContainerInset.width, height: .greatestFiniteMagnitude)
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        let used = ceil(text.layoutManager?.usedRect(for: text.textContainer!).height ?? 100)
        let full = used + 2 * text.textContainerInset.height
        text.frame.size = NSSize(width: cardWidth, height: full)
        preferredContentSize = NSSize(width: cardWidth, height: min(full, 520))
        top()
    }
    func top() {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func textView(_ v: NSTextView, clickedOnLink link: Any, at i: Int) -> Bool {
        if let u = link as? URL, u.scheme == "lookupword" {
            switch (u.host ?? "") + u.path {
            case "open/accessibility": NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            case "open/screen-recording": NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            default: return false
            }
            return true
        }
        guard let u = link as? URL, u.scheme == "say",
              let t = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first?.value else { return false }
        speak(t, u.host ?? "en")
        return true
    }
}

var pop: NSPopover?, mark: NSWindow?, monitor: Any?, timer: Timer?, shown = 0
let content = Card()

func close() {
    pop?.close(); mark?.orderOut(nil)
    pop = nil; mark = nil
    if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    timer?.invalidate(); timer = nil
}

// The anchor the popover points at: the word's yellow highlight, as Look Up's, or an invisible spot at the pointer.
func anchor(_ r: NSRect?) -> NSView {
    mark?.orderOut(nil)
    let frame = r?.insetBy(dx: -1, dy: -1) ?? NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 2, height: 2))
    let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.isOpaque = false; w.backgroundColor = .clear; w.ignoresMouseEvents = true; w.hasShadow = false
    w.level = .popUpMenu; w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let v = NSView(frame: NSRect(origin: .zero, size: frame.size))
    v.wantsLayer = true
    if r != nil {
        v.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.45).cgColor
        v.layer?.cornerRadius = 3
    }
    w.contentView = v
    w.orderFrontRegardless()
    mark = w
    return v
}

// Show text in the popover pointing at the word (or the pointer): above it, as Look Up, below when there is no room.
func present(_ s: NSAttributedString, at r: NSRect?) {
    pop?.close()
    let v = anchor(r)
    content.set(s)
    let p = NSPopover()
    p.contentViewController = content
    p.behavior = .applicationDefined
    p.animates = false
    p.contentSize = content.preferredContentSize
    p.show(relativeTo: v.bounds, of: v, preferredEdge: .maxY)
    pop = p
    DispatchQueue.main.async { content.top() }  // again once the popover has laid it out
}

func update(_ s: NSAttributedString) {
    guard let p = pop else { return }
    content.set(s)
    p.contentSize = content.preferredContentSize
    DispatchQueue.main.async { content.top() }
}
