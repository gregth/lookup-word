// Lookup Word: Look Up for a word in any of your languages, from the Mac's own dictionaries, with the word in your
// other languages, a 🔈 for each, saved to your vocabulary.
//
// A background app (no Dock icon). Double-tap ⌥ (or the modifier in the settings): it takes the selected text
// (accessibility, so it needs Accessibility once), or, with screen reading on, reads the word under the pointer off
// the screen (Screen Recording once), highlights it, and shows a popover pointing at it. Everything comes from the
// dictionaries enabled in Dictionary.app, offline. A click elsewhere, a key or 30 seconds close it.
import AppKit

let hotkey: (flag: NSEvent.ModifierFlags, symbol: String) = {
    switch config.hotkey {
    case "control", "ctrl", "⌃": return (.control, "⌃")
    case "command", "cmd", "⌘": return (.command, "⌘")
    case "shift", "⇧": return (.shift, "⇧")
    case "option", "opt", "alt", "⌥": return (.option, "⌥")
    default: warn("hotkey \"\(config.hotkey)\" is not option, control, command or shift: using option"); return (.option, "⌥")
    }
}()

// saves one at a time, so two quick lookups never write the same file at once
let saves = DispatchQueue(label: "saves")

// the card's status line: the store's answer, and what is wrong with the settings, if anything
func status(_ s: String) -> String {
    ([s] + configWarnings.prefix(1).map { "Settings: " + $0 }).filter { !$0.isEmpty }.joined(separator: "\n")
}

// A word found: its entry from the dictionaries at once, then the store's answer in the status line.
func show(_ raw: String, _ rect: NSRect?, _ around: String, _ mine: Int) {
    let hint = language(around)
    guard let e = lookUpEntry(raw, hint: hint) ?? (raw.contains(" ") ? nil : corrected(raw.trimmingCharacters(in: .punctuationCharacters), hint: hint)) else {
        log("no entry for \(raw)")
        let w = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return present(message("“\(w)” is in none of your dictionaries" + (w.first?.isUppercase == true ? ": a name, perhaps. Dictionaries leave names out." : ".")), at: rect)
    }
    log("\(e.lang) \(e.word)")
    present(card(e, status: status(store is NoStore ? "" : "Saving…")), at: rect)
    saves.async {
        let answer = store.save(e)
        DispatchQueue.main.async { if shown == mine { update(card(e, status: status(answer))) } }
    }
}

func lookUp() {
    close()
    shown += 1
    let mine = shown, mouse = NSEvent.mouseLocation
    monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { _ in close() }
    if config.closeAfter > 0 { timer = Timer.scheduledTimer(withTimeInterval: config.closeAfter, repeats: false) { _ in close() } }
    if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) {
        present(message("Allow Lookup Word in System Settings → Privacy & Security → Accessibility, then double-tap \(hotkey.symbol) again."), at: nil)
    } else if let (word, rect, around) = selection() {
        show(word, rect, around, mine)
    } else if !config.screenReading {
        present(message("Select a word, then double-tap \(hotkey.symbol). To look up the word under the pointer without selecting it, turn on screen reading in the settings (\"screenReading\": true)."), at: nil)
    } else {
        present(message("Reading the screen…"), at: nil)
        Task { @MainActor in
            let found = await byOCR(mouse)
            guard shown == mine, pop != nil else { return }
            if let (r, rect) = found {
                // the element's real text, when the app gives it, spells the word (a language the screen reading
                // cannot read, and misreads in any language) and gives the language
                if let text = textUnderPointer(mouse), let word = closest(r, in: text) {
                    if word != r.word { log("  is \(word) in the text") }
                    show(word, rect, text, mine)
                } else { show(r.word, rect, r.around, mine) }
            }
            else if !CGPreflightScreenCaptureAccess() {
                update(message("Allow Lookup Word in System Settings → Privacy & Security → Screen Recording, so it can read the word under the pointer, then double-tap \(hotkey.symbol) again."))
            } else {
                update(message("No word under the pointer. Select one, or point at it, then double-tap \(hotkey.symbol)."))
            }
        }
    }
}

// --- the shortcut: double-tap the modifier ---------------------------------------------------------------------
// Two taps of the modifier alone, each under 0.3 s, the second within 0.4 s of the first; any other key or modifier
// in between cancels, so its combinations (and a keyboard layout's ⌥ characters) never trigger it.

var downAt: Date?, lastTap = Date.distantPast
func onKey(_ e: NSEvent) {
    let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
    if e.type == .keyDown { downAt = nil; lastTap = .distantPast }
    else if flags == hotkey.flag { downAt = Date() }  // the modifier alone went down
    else if flags.isEmpty, let d = downAt, Date().timeIntervalSince(d) < 0.3 {  // …and came up quickly: a tap
        downAt = nil
        if Date().timeIntervalSince(lastTap) < 0.4 { lastTap = .distantPast; lookUp() } else { lastTap = Date() }
    } else { downAt = nil; lastTap = .distantPast }
}

// --- the menu bar icon --------------------------------------------------------------------------------------------

final class Menu: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    override init() {
        super.init()
        item.button?.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "Lookup Word")
        let m = NSMenu()
        m.addItem(NSMenuItem(title: "Double-tap \(hotkey.symbol) to look up a word", action: nil, keyEquivalent: ""))
        m.addItem(.separator())
        if store.url != nil { add(m, "Open Vocabulary", #selector(vocabulary)) }
        add(m, "Open Settings", #selector(settings))
        add(m, "Restart to Apply Settings", #selector(restart))
        m.addItem(.separator())
        add(m, "Uninstall Lookup Word…", #selector(uninstall))
        add(m, "Quit Lookup Word", #selector(quit))
        item.menu = m
    }
    func add(_ m: NSMenu, _ title: String, _ sel: Selector) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: ""); i.target = self; m.addItem(i)
    }
    @objc func vocabulary() { if let u = store.url, FileManager.default.fileExists(atPath: u.path) { NSWorkspace.shared.open(u) } }
    @objc func settings() { NSWorkspace.shared.open(Paths.config) }
    // under its launch agent (KeepAlive after a failure), quitting with a failure status brings it straight back with
    // the new settings; started any other way, it opens a new copy of itself first
    @objc func restart() {
        if ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"]?.contains("lookup-word") != true {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "sleep 1; open -n \"$0\"", Bundle.main.bundlePath]
            try? p.run()
            exit(0)
        }
        exit(1)
    }
    // a clean exit: launchd's KeepAlive (SuccessfulExit false) leaves it stopped until the next login
    @objc func quit() { exit(0) }

    // what uninstall.sh does: the launch agent, the app and its permissions go; the settings and the support folder's
    // vocabulary only when asked, and a vocabulary file elsewhere (a note in a vault) never
    @objc func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Uninstall Lookup Word?"
        a.informativeText = "This removes the app, stops it starting at login, and resets its permissions."
            + (store.url.map { $0.path.hasPrefix(Paths.support.path) ? "" : "\n\nYour vocabulary at \($0.path) stays." } ?? "")
        a.showsSuppressionButton = true
        a.suppressionButton?.title = "Also delete my settings and the vocabulary in Lookup Word's own folder"
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        a.buttons[0].hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let fm = FileManager.default, label = Bundle.main.bundleIdentifier ?? "io.github.gregth.lookup-word"
        let home = fm.homeDirectoryForCurrentUser
        try? fm.removeItem(at: home.appendingPathComponent("Library/LaunchAgents/\(label).plist"))
        if a.suppressionButton?.state == .on {
            try? fm.removeItem(at: Paths.support)
            try? fm.removeItem(at: home.appendingPathComponent("Library/Logs/Lookup Word"))
        }
        if Bundle.main.bundlePath.hasSuffix(".app") { try? fm.removeItem(atPath: Bundle.main.bundlePath) }
        // the permissions and the launch agent last, from a shell that outlives this process
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; tccutil reset Accessibility \"$0\"; tccutil reset ScreenCapture \"$0\"; launchctl bootout gui/$(id -u)/\"$0\"", label]
        try? p.run()
        exit(0)
    }
}

// --- checks without the screen or the shortcut --------------------------------------------------------------------

let args = CommandLine.arguments

// `LookupWord --text WORD [lang]` prints the entry it would show, the text's language given
if let i = args.firstIndex(of: "--text"), i + 1 < args.count {
    let hint = i + 2 < args.count ? args[i + 2] : "en"
    if pack(hint) == nil { log("\(hint) is not among your languages (\(packs.map(\.code).joined(separator: ", "))): looking it up as text in those") }
    if let e = lookUpEntry(args[i + 1], hint: hint) ?? corrected(args[i + 1], hint: hint) {
        print("\(e.lang) \(e.word) |\(e.ipa)|"); e.tr.forEach { print("  \($0.0): \($0.1)") }
        print("  meaning: \(e.meaning)"); print("  sections: \(e.sections.map(\.0).joined(separator: ", "))")
    } else { print("no entry") }
    exit(0)
}

// `LookupWord --save WORD [lang]` looks the word up and saves it to the store in the settings
if let i = args.firstIndex(of: "--save"), i + 1 < args.count {
    let hint = i + 2 < args.count ? args[i + 2] : "en"
    if let e = lookUpEntry(args[i + 1], hint: hint) { print(store is NoStore ? "Not saved: the store is none." : store.save(e)) } else { print("no entry") }
    exit(0)
}

// `LookupWord --closest READ TEXT` prints the word of TEXT it would take for a reading
if let i = args.firstIndex(of: "--closest"), i + 2 < args.count {
    print(closest(args[i + 1], in: args[i + 2]) ?? "none"); exit(0)
}

// `LookupWord --dictionaries` lists the dictionaries Dictionary.app makes available, and what each pack needs
if args.contains("--dictionaries") {
    print("Available: " + dictionaries.keys.sorted().joined(separator: ", "))
    for p in packs {
        let need = [p.monolingual, p.bilingual].compactMap { $0 }
        let missing = need.filter { dictionaries[$0] == nil }
        print("\(p.code) \(p.name): " + (missing.isEmpty ? "ready" : "enable in Dictionary.app → Settings: " + missing.joined(separator: ", ")))
    }
    configWarnings.forEach { print("Settings: " + $0) }
    exit(0)
}

// `LookupWord --render WORD LANG out.png` draws the card, dark, to an image
if let i = args.firstIndex(of: "--render"), i + 3 < args.count {
    NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    if let e = lookUpEntry(args[i + 1], hint: args[i + 2]) {
        content.set(card(e, status: "Saved to Vocabulary."))
        let v = content.view
        v.appearance = NSAppearance(named: .darkAqua)
        v.frame = NSRect(origin: .zero, size: content.preferredContentSize)
        v.layoutSubtreeIfNeeded()
        let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 3]))
        print("wrote \(args[i + 3]) \(Int(v.bounds.width))×\(Int(v.bounds.height))")
    } else { print("no entry") }
    exit(0)
}

// `LookupWord --ocr "a line of text" 0.4` draws the line and reads the word at 40% of its width
if let i = args.firstIndex(of: "--ocr"), i + 2 < args.count, let x = Double(args[i + 2]) {
    let s = NSAttributedString(string: args[i + 1], attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black])
    let size = NSSize(width: ceil(s.size().width) + 40, height: 60)
    let img = NSImage(size: size, flipped: false) { r in NSColor.white.setFill(); r.fill(); s.draw(at: NSPoint(x: 20, y: 20)); return true }
    var rect = NSRect(origin: .zero, size: size)
    let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    let pt = CGPoint(x: (20 + s.size().width * x) / size.width, y: (20 + s.size().height / 2) / size.height)
    if let (rd, box) = wordAt(cg, pt) {
        print("\(rd.word)  box x \(String(format: "%.0f", box.minX * size.width - 20))…\(String(format: "%.0f", box.maxX * size.width - 20)) of \(String(format: "%.0f", s.size().width)) pt")
    } else { print("none") }
    exit(0)
}

// `LookupWord --pointer "TEXT" [size] [bold] [dark] [spread]` draws TEXT, points at each of its words in turn, reads
// it off the image, matches the reading against TEXT, and prints one line per word: OK or MISS, the word, what was
// read, what was matched
if let i = args.firstIndex(of: "--pointer"), i + 1 < args.count {
    let text = args[i + 1]
    let size = i + 2 < args.count ? CGFloat(Double(args[i + 2]) ?? 15) : 15, bold = args.contains("bold")
    let font = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    let dark = args.contains("dark")  // light text on a dark background
    let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: dark ? NSColor(white: 0.9, alpha: 1) : NSColor.black])
    let isize = NSSize(width: ceil(s.size().width) + 40, height: ceil(s.size().height) + 40)
    let img = NSImage(size: isize, flipped: false) { r in (dark ? NSColor(white: 0.12, alpha: 1) : NSColor.white).setFill(); r.fill(); s.draw(at: NSPoint(x: 20, y: 20)); return true }
    var rect = NSRect(origin: .zero, size: isize)
    let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    var ok = 0, all = 0, worst = 0.0
    text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, r, _, _ in
        guard let word else { return }
        let x0 = NSAttributedString(string: String(text[..<r.lowerBound]), attributes: [.font: font]).size().width
        let x1 = NSAttributedString(string: String(text[..<r.upperBound]), attributes: [.font: font]).size().width
        for at in (args.contains("spread") ? [0.2, 0.5, 0.8] : [0.5]) as [CGFloat] {  // where in the word the pointer is
            let pt = CGPoint(x: (20 + x0 + (x1 - x0) * at) / isize.width, y: (20 + s.size().height / 2) / isize.height)
            let got = wordAt(cg, pt)
            let matched = got.flatMap { closest($0.0, in: text) } ?? "—"
            let good = fold(matched) == fold(word)
            all += 1; if good { ok += 1 }
            // the box's left edge against the word's: how far before the first letter the highlight starts (pt)
            var edge = ""
            if let b = got?.1 {
                let gap = (20 + x0) - b.minX * isize.width
                worst = max(worst, gap); edge = String(format: " | starts %+.1f pt before", gap)
            }
            print("\(good ? "OK  " : "MISS") \(word) | read \(got?.0.word ?? "—") | matched \(matched)\(edge)")
        }
    }
    print("\(ok)/\(all)  worst start \(String(format: "%.1f", worst)) pt before a word")
    exit(0)
}

let app = NSApplication.shared
DispatchQueue.main.async { for p in packs where p.lemmas != nil { _ = lemma("", p) } }  // read lemma lists at start, not on first use
app.setActivationPolicy(.accessory)
NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: onKey)
_ = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { onKey($0); return $0 }
let menu = config.menuBar ? Menu() : nil
if args.contains("--now") { DispatchQueue.main.async { lookUp() } }  // a test: look up at once
app.run()
