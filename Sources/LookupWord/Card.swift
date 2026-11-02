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

// Each sense number on a line of its own: a number in the place of one ("1 move", "2run", not "18th") counts only as
// the next in sequence, so a number in an example ("Dave has run 42 marathons") stays in its sentence.
func senseBreaks(_ text: String) -> String {
    guard let re = try? NSRegularExpression(pattern: #"\s(\d{1,2})\.?(?:\s(?=[\p{L}\[(<])|(?![a-z]{2}\b)(?=\p{L}))"#) else { return text }
    let ns = text as NSString
    var out = "", at = 0, next = 1
    for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        // the next number, or one a little further (a sense the pattern missed, as Greek "4(στη φρ.)", must not stop
        // every break after it), or a new 1
        guard let n = Int(ns.substring(with: m.range(at: 1))), n == 1 || (next...next + 3).contains(n) else { continue }
        out += ns.substring(with: NSRange(location: at, length: m.range.location - at)) + "\n\(n)\t"
        at = m.range.location + m.range.length
        next = n + 1
    }
    return out + ns.substring(from: at)
}

func formatted(_ text: String) -> NSAttributedString {
    var t = replacing(text, #"\s*\b(DERIVATIVES|PHRASES|PHRASAL VERBS|IDIOMS|ORIGIN|ANTONYMS|USAGE|SYNONYMS)\b\s*"#, "\n\n$1\n")
    t = replacing(t, #"\s*▸\s*"#, "\n▸ ")
    t = replacing(t, #"\s*•\s*"#, "\n• ")
    t = senseBreaks(t)
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

// The card on screen, to draw again when a section opens or closes; the sections opened or closed on it by hand; and
// whether they start closed, as the card's Collapse all left them for the next cards.
var shownCard: (entry: Entry, status: String)?
var toggled = Set<Int>()
var sectionStart: [Int: Int] = [:]  // each section's title, by its character position, for a flag's click
let collapsedKey = "sectionsCollapsed"
var collapsedByDefault: Bool { UserDefaults.standard.bool(forKey: collapsedKey) }

func card(_ e: Entry, status: String) -> NSAttributedString {
    if shownCard.map({ $0.entry.word != e.word || $0.entry.lang != e.lang }) ?? true { toggled = [] }
    shownCard = (e, status)
    sectionStart = [:]
    let out = NSMutableAttributedString()
    out.append(run(e.word, serif(26, .bold)))
    if !e.ipa.isEmpty { out.append(run("  | \(e.ipa) |", serif(16, .regular), .secondaryLabelColor)) }
    out.append(speaker(e.word, e.lang))
    for (code, words) in e.tr where !words.isEmpty {
        let flag = NSMutableAttributedString(attributedString: run("\n" + (pack(code)?.flag ?? code.uppercased()) + "  ", .systemFont(ofSize: 15)))
        // the flag leads to its language's dictionary below ("Greek – English"), when the card has one
        if let name = pack(code)?.name, let i = e.sections.firstIndex(where: { $0.0.contains(name) }) {
            flag.addAttributes([.link: URL(string: "lookupword://section/\(i)")!, .cursor: NSCursor.pointingHand],
                               range: NSRange(location: 1, length: flag.length - 3))
        }
        out.append(flag)
        out.append(run(words, serif(17, .semibold)))
        out.append(speaker(words, code))
    }
    // Collapse all (or Expand all), small and muted, at the right above the first dictionary, where its reader is
    if !e.sections.isEmpty {
        let font = NSFont.systemFont(ofSize: 11)
        let all = NSMutableAttributedString(string: "\n" + (collapsedByDefault ? "Expand all" : "Collapse all"),
                                            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        all.addAttributes([.link: URL(string: "lookupword://toggle/all")!, .cursor: NSCursor.pointingHand], range: NSRange(location: 1, length: all.length - 1))
        let right = NSMutableParagraphStyle(); right.alignment = .right; right.paragraphSpacingBefore = 10
        all.addAttribute(.paragraphStyle, value: right, range: NSRange(location: 0, length: all.length))
        out.append(all)
    }
    for (i, (name, text)) in e.sections.enumerated() {
        let open = collapsedByDefault == toggled.contains(i)
        // the dictionary's name, a click opening or closing it, and a thin rule to the right edge, as Look Up's: a line
        // drawn as an attachment as wide as what is left of the row
        let font = NSFont.systemFont(ofSize: 20, weight: .light)
        let label = (open ? "▾ " : "▸ ") + name + "  "
        let title = NSMutableAttributedString(string: "\n" + label, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        title.addAttributes([.link: URL(string: "lookupword://toggle/\(i)")!, .cursor: NSCursor.pointingHand],
                            range: NSRange(location: 1, length: (label as NSString).length - 2))
        let room = cardWidth - 2 * 24 - 16 - (label as NSString).size(withAttributes: [.font: font]).width  // the card's margins
        if room > 20 {
            let line = NSImage(size: NSSize(width: room, height: 1), flipped: false) { r in NSColor.separatorColor.setFill(); r.fill(); return true }
            let rule = NSTextAttachment()
            rule.image = line
            rule.bounds = NSRect(x: 0, y: font.xHeight / 2, width: room, height: 1)
            title.append(NSAttributedString(attachment: rule))
        }
        if open { title.append(NSAttributedString(string: "\n")) }  // a closed one: the next title right below
        let gap = NSMutableParagraphStyle(); gap.paragraphSpacingBefore = open ? 16 : 8; gap.paragraphSpacing = 4  // not a blank line
        title.addAttribute(.paragraphStyle, value: gap, range: NSRange(location: 0, length: title.length))
        sectionStart[i] = out.length + 1
        out.append(title)
        if open { out.append(formatted(text)) }
    }
    if !status.isEmpty { out.append(run("\n\n" + status, .systemFont(ofSize: 11), .tertiaryLabelColor)) }
    out.append(footer(e))
    return out
}

// The card's foot, small and muted: the word's own language's dictionaries online.
func footer(_ e: Entry) -> NSAttributedString {
    let font = NSFont.systemFont(ofSize: 11)
    func link(_ title: String, _ url: URL) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .link: url, .cursor: NSCursor.pointingHand])
    }
    let out = NSMutableAttributedString(attributedString: run("\n" + (e.sections.isEmpty ? "" : "\n"), font))
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#&=+")
    let links = (pack(e.lang)?.links ?? []).compactMap { l -> (String, URL)? in
        guard let w = e.word.addingPercentEncoding(withAllowedCharacters: allowed),
              let u = URL(string: l.url.replacingOccurrences(of: "{word}", with: w)) else { return nil }
        return (l.name, u)
    }
    if !links.isEmpty {
        out.append(run("Read more: ", font, .tertiaryLabelColor))
        for (i, (name, u)) in links.enumerated() {
            if i > 0 { out.append(run(" · ", font, .tertiaryLabelColor)) }
            out.append(link(name, u))
        }
    }
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

var voice = AVSpeechSynthesizer(), stopped: AVSpeechSynthesizer?  // (the one stopped, kept until the next)
// A row of several words ("γιατί, που", "weather · time"): each said on its own, with a short pause between, not one
// run-on sentence with its commas and the · read out (his report, 2026-11-02: "the speaker sounds abnormal")
func speak(_ text: String, _ lang: String) {
    log("say (\(lang)): \(text)")
    // a new synthesizer each time: one stopped mid-row could drop the words queued right after (a click while a row
    // still played stayed silent, 1 in 10 clicks in a test)
    voice.stopSpeaking(at: .immediate)
    stopped = voice; voice = AVSpeechSynthesizer()
    let items = text.components(separatedBy: CharacterSet(charactersIn: ",·;")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    for item in items.isEmpty ? [text] : items {
        let u = AVSpeechUtterance(string: item)
        u.voice = AVSpeechSynthesisVoice(language: pack(lang)?.voice ?? "en-GB")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        u.postUtteranceDelay = 0.35
        voice.speak(u)
    }
}

// The card's text. A double-tap shows the card while another app stays active, and a window of an inactive app
// takes the first click only to activate it: so the first click on a speaker or a link did nothing (his report,
// 2026-11-02: "the sound does not play some times"). It takes that click too.
final class CardText: NSTextView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class Card: NSViewController, NSTextViewDelegate {
    let text = CardText(frame: NSRect(x: 0, y: 0, width: cardWidth, height: 100))
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
        scroll.autoresizingMask = [.width, .height]  // the popover's size, whatever resizes it
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
    // the card drawn again in place, at the same scroll, after a section opened or closed
    func redraw() {
        guard let c = shownCard else { return }
        let at = scroll.contentView.bounds.origin
        set(card(c.entry, status: c.status))
        pop?.contentSize = preferredContentSize
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(at.y, max(0, text.frame.height - scroll.contentView.bounds.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func scrollToSection(_ i: Int) {
        guard let at = sectionStart[i], let lm = text.layoutManager, let tc = text.textContainer else { return }
        let glyphs = lm.glyphRange(forCharacterRange: NSRange(location: at, length: 1), actualCharacterRange: nil)
        let y = lm.boundingRect(forGlyphRange: glyphs, in: tc).minY + text.textContainerInset.height - 12
        let most = max(0, text.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), most)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func top() {
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    // the guard against the card opening scrolled above its top, blank there and cut at the bottom (his report,
    // 2026-11-02, a typed word's card; not reproduced: whatever scrolls it does so after top())
    // The guard against a card blank at its top and cut at its bottom (his reports, 2026-11-02, typed words' cards; not
    // reproduced here with a fresh card, a scrolled one before it, several in a row, or the box low on the screen): the
    // scroll view fills the popover and starts at its top, and what was wrong goes to the log, to find the cause.
    override func viewDidLayout() {
        super.viewDidLayout()
        let wrongFrame = pop.map { scroll.frame.size != $0.contentSize } ?? false
        let aboveTop = scroll.contentView.bounds.origin.y < 0 || scroll.contentInsets.top != 0
        guard wrongFrame || aboveTop else { return }
        log("card layout fixed: scroll=\(scroll.frame) for \(pop?.contentSize ?? .zero), clip=\(scroll.contentView.bounds), insets=\(scroll.contentInsets.top), window=\(view.window?.frame ?? .zero), safeArea=\(view.window?.contentView?.safeAreaInsets.top ?? 0)")
        if wrongFrame, let size = pop?.contentSize { scroll.setFrameSize(size) }
        scroll.contentInsets = NSEdgeInsets()
        if scroll.contentView.bounds.origin.y < 0 { top() }
    }
    func textView(_ v: NSTextView, clickedOnLink link: Any, at i: Int) -> Bool {
        if let u = link as? URL, u.scheme == "https" {  // Read more: in the browser, the card closed
            NSWorkspace.shared.open(u)
            if typeBox?.pinned != true { close() }
            return true
        }
        if let u = link as? URL, u.scheme == "lookupword" {
            switch (u.host ?? "") + u.path {
            case "open/accessibility": askPermission("Privacy_Accessibility")
            case "open/screen-recording": askPermission("Privacy_ScreenCapture")
            case "toggle/all":
                UserDefaults.standard.set(!collapsedByDefault, forKey: collapsedKey)
                toggled = []
                redraw()
            case let t where t.hasPrefix("section/"):
                guard let i = Int(t.dropFirst("section/".count)) else { return false }
                if collapsedByDefault != toggled.contains(i) { toggled.formSymmetricDifference([i]); redraw() }  // opened first
                scrollToSection(i)
            case let t where t.hasPrefix("toggle/"):
                guard let i = Int(t.dropFirst("toggle/".count)) else { return false }
                if toggled.contains(i) { toggled.remove(i) } else { toggled.insert(i) }
                redraw()
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
    pop?.close(); mark.map { m in m.parent?.removeChildWindow(m) }; mark?.orderOut(nil)
    pop = nil; mark = nil
    if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    timer?.invalidate(); timer = nil
}

// The anchor the popover points at: the word's yellow highlight, as Look Up's, or an invisible spot at the pointer
// (or at r, for a word typed into the box, which has no word on screen to highlight).
func anchor(_ r: NSRect?, highlight: Bool = true) -> NSView {
    mark.map { m in m.parent?.removeChildWindow(m) }  // (one the box carried: not shown again with it)
    mark?.orderOut(nil)
    let frame = r?.insetBy(dx: -1, dy: -1) ?? NSRect(origin: NSEvent.mouseLocation, size: NSSize(width: 2, height: 2))
    let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    w.isOpaque = false; w.backgroundColor = .clear; w.ignoresMouseEvents = true; w.hasShadow = false
    w.level = .popUpMenu; w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let v = NSView(frame: NSRect(origin: .zero, size: frame.size))
    v.wantsLayer = true
    if r != nil, highlight {
        v.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.45).cgColor
        v.layer?.cornerRadius = 3
    }
    w.contentView = v
    w.orderFrontRegardless()
    mark = w
    return v
}

// Show text in the popover pointing at the word (or the pointer): above it, as Look Up, below when there is no room.
func present(_ s: NSAttributedString, at r: NSRect?, highlight: Bool = true) {
    pop?.close()
    let v = anchor(r, highlight: highlight)
    content.set(s)
    let p = NSPopover()
    p.contentViewController = content
    p.behavior = .applicationDefined
    p.animates = false
    p.contentSize = content.preferredContentSize
    p.show(relativeTo: v.bounds, of: v, preferredEdge: highlight ? .maxY : .minY)  // a typed word's card hangs below the box
    pop = p
    DispatchQueue.main.async { content.top() }  // again once the popover has laid it out
}

func update(_ s: NSAttributedString) {
    guard let p = pop else { return }
    content.set(s)
    p.contentSize = content.preferredContentSize
    DispatchQueue.main.async { content.top() }
}
