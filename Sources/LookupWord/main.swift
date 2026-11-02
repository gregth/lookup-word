// Lookup Word: Look Up for a word in any of your languages, from the Mac's own dictionaries, with the word in your
// other languages, a 🔈 for each, saved to your vocabulary.
//
// A background app (no Dock icon). Double-tap ⌥ (or the modifier in the settings): it takes the selected text
// (accessibility, so it needs Accessibility once), or, with nothing selected, reads the word under the pointer off
// the screen (Screen Recording once), highlights it, and shows a popover pointing at it. Everything comes from the
// dictionaries enabled in Dictionary.app, offline. A click elsewhere, a key or 30 seconds close it.
import AppKit
import SwiftUI

let hotkey: (flag: NSEvent.ModifierFlags, symbol: String, name: String) = {
    switch config.hotkey {
    case "control", "ctrl", "⌃": return (.control, "⌃", "⌃ Control")
    case "command", "cmd", "⌘": return (.command, "⌘", "⌘ Command")
    case "shift", "⇧": return (.shift, "⇧", "⇧ Shift")
    case "option", "opt", "alt", "⌥": return (.option, "⌥", "⌥ Option")
    default: warn("hotkey \"\(config.hotkey)\" is not option, control, command or shift: using option"); return (.option, "⌥", "⌥ Option")
    }
}()
// The two ways to look a word up, said the same way everywhere (the welcome, the settings, the cards), for anyone:
// no "double-tap", "pointer reading" or permission names without what they mean.
let pressTwice = "press the \(hotkey.name) key twice, quickly"
let howSelect = "Select a word (double-click it, or drag over it), then \(pressTwice)."
let howPoint = "Rest the mouse pointer on a word, without selecting it, then \(pressTwice). This works on pictures and videos too."
let whyScreen = "To read a word you point at, Lookup Word takes a picture of a small area around the mouse pointer, only when you press the keys, and never saves or sends it. macOS calls this permission Screen Recording."

// saves one at a time, so two quick lookups never write the same file at once
let saves = DispatchQueue(label: "saves")

// the card's status line: the store's answer, and what is wrong with the settings, if anything
func status(_ s: String) -> String {
    ([s] + configWarnings.prefix(1).map { "Settings: " + $0 }).filter { !$0.isEmpty }.joined(separator: "\n")
}

// A word found: its entry from the dictionaries at once, then the store's answer in the status line.
func show(_ raw: String, _ rect: NSRect?, _ around: String, _ mine: Int, highlight: Bool = true) {
    let hint = language(around)
    guard let e = lookUpEntry(raw, hint: hint) ?? (raw.contains(" ") ? nil : corrected(raw.trimmingCharacters(in: .punctuationCharacters), hint: hint)) else {
        log("no entry for \(raw)")
        let w = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return present(message("“\(w)” is in none of your dictionaries" + (w.first?.isUppercase == true ? ": a name, perhaps. Dictionaries leave names out." : ".")), at: rect, highlight: highlight)
    }
    log("\(e.lang) \(e.word)")
    present(card(e, status: status(store is NoStore ? "" : "Saving…")), at: rect, highlight: highlight)
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
    if !AXIsProcessTrusted() {  // only checked: the card's Allow asks macOS, a lookup never does
        present(message("Lookup Word can't notice the keys or read the word you selected yet: it needs the permission macOS calls Accessibility. Click Allow: macOS asks you, and lets you turn it on. Then try again.", action: ("Allow…", "lookupword://open/accessibility")), at: nil)
    } else if let (word, rect, around) = selection() {
        show(word, rect, around, mine)
    } else {
        // nothing selected: the word under the pointer, read off the screen (macOS asks for Screen Recording the
        // first time; without it, the card says how to allow it, or to select the word instead)
        present(message("Reading the screen…"), at: nil)
        readPointer(mouse, mine)
    }
}

// The word under the pointer, read off the screen, then looked up.
func readPointer(_ mouse: NSPoint, _ mine: Int) {
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
            update(message("\(whyScreen)\n\nTo allow it, click Allow: macOS asks you, and lets you turn it on (it may ask to quit and reopen Lookup Word). Or select the word instead, then \(pressTwice).", action: ("Allow…", "lookupword://open/screen-recording")))
        } else {
            update(message("No word found under the mouse pointer.\n\n\(howSelect)\n\nOr: \(howPoint)"))
        }
    }
}

// --- the shortcut: double-tap the modifier ---------------------------------------------------------------------
// The monitors that see it, in other apps (needs Accessibility) and in this one; set again once the permission is
// given, as those added before it may not see other apps' keys.
var keyMonitors: [Any] = []
func watchKeys() {
    keyMonitors.forEach(NSEvent.removeMonitor)
    keyMonitors = [NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown], handler: onKey),
                   NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { onKey($0); return $0 }].compactMap { $0 }
}
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
    let needs = NSMenuItem(title: "⚠︎ Not working yet: allow Accessibility…", action: #selector(welcome), keyEquivalent: "")
    let pointing = NSMenuItem(title: "Allow pointing at words (Screen Recording)…", action: #selector(allowPointing), keyEquivalent: "")
    override init() {
        super.init()
        let m = NSMenu()
        needs.target = self; pointing.target = self
        add(m, "About Lookup Word", #selector(about), symbol: "info.circle")
        m.addItem(.separator())
        // what to do, and what still stops it from working (shown only while it does)
        needs.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.systemOrange]))
        pointing.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: nil)
        m.addItem(needs)
        m.addItem(pointing)
        let how = NSMenuItem(title: "Select or point at a word, then press \(hotkey.symbol) twice", action: nil, keyEquivalent: "")
        how.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: nil)
        m.addItem(how)
        m.addItem(.separator())
        // its shortcut shown, the one chosen in Settings (the hot key itself works from any app)
        let typed = NSMenuItem(title: "Look Up a Word…", action: #selector(typeWord), keyEquivalent: typeShortcut.menuKey)
        typed.keyEquivalentModifierMask = typeShortcut.menuFlags
        typed.target = self
        typed.image = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: nil)
        m.addItem(typed)
        add(m, "Reset the Box's Position", #selector(resetBox), symbol: "arrow.up.and.down.and.arrow.left.and.right")
        if store.url != nil { add(m, "Open Vocabulary", #selector(vocabulary), key: "o", symbol: "book") }
        add(m, "Settings…", #selector(settings), key: ",", symbol: "gearshape")
        m.addItem(.separator())
        add(m, "Hide Menu Bar Icon", #selector(hide), symbol: "eye.slash")
        add(m, "Restart Lookup Word", #selector(restartNow), symbol: "arrow.clockwise")
        if isInstalledApp { add(m, "Uninstall Lookup Word…", #selector(uninstall), symbol: "trash") }  // never in a copy run from the build folder
        add(m, "Quit Lookup Word", #selector(quit), key: "q", symbol: "power")
        item.menu = m
        refresh()
    }
    // Without Accessibility the app cannot see the key presses, so nothing at all happens when they are pressed: the
    // icon says so (a warning sign in place of the book), and the menu's first line leads to the welcome window.
    // the warning: a small orange badge over the book's corner, as on an app's icon; the book itself stays a template
    // image, so it keeps the menu bar's own colour in light and dark
    let badge: NSImageView = {
        let v = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold).applying(.init(paletteColors: [.white, .systemOrange]))
        v.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        v.isHidden = true
        return v
    }()
    func refresh() {
        let ok = AXIsProcessTrusted()
        if item.button?.image == nil {
            item.button?.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: "Lookup Word")
        }
        if let b = item.button, badge.superview == nil {
            b.addSubview(badge)
            badge.frame = NSRect(x: b.bounds.maxX - 11, y: b.bounds.maxY - 11, width: 10, height: 10)
            badge.autoresizingMask = [.minXMargin, .minYMargin]
        }
        badge.isHidden = ok
        item.button?.setAccessibilityLabel(ok ? "Lookup Word" : "Lookup Word needs a permission")
        item.button?.toolTip = ok ? nil : "Lookup Word needs the Accessibility permission to work"
        needs.isHidden = ok
        pointing.isHidden = !ok || CGPreflightScreenCaptureAccess()  // the optional one, once the required one is there
    }
    @objc func welcome() { showWelcome() }
    @objc func typeWord() { showTypeBox() }
    @objc func resetBox() { resetTypeBoxPosition() }  // centred again, a fifth of the way down the screen
    // the standard About panel: the icon, name and version from the app's bundle, and these credits
    @objc func about() {
        NSApp.activate(ignoringOtherApps: true)
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let p = NSMutableParagraphStyle(); p.alignment = .center
        let credits = NSMutableAttributedString(string: "Look up any word on your Mac, in all your languages, offline, and keep the words you looked up.\n\n", attributes: [.font: small, .paragraphStyle: p, .foregroundColor: NSColor.labelColor])
        credits.append(NSAttributedString(string: "github.com/gregth/lookup-word", attributes: [.font: small, .paragraphStyle: p, .link: URL(string: "https://github.com/gregth/lookup-word")!]))
        credits.append(NSAttributedString(string: "\n\nMIT License, shared as is, with no warranty. Dictionary content comes from the dictionaries on your Mac and belongs to their publishers. Greek word forms from simplemma (Adrien Barbaresi) and its sources.", attributes: [.font: small, .paragraphStyle: p, .foregroundColor: NSColor.secondaryLabelColor]))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "Lookup Word",
                                                     .applicationIcon: appIcon])
    }
    @objc func allowPointing() { askPermission("Privacy_ScreenCapture") }
    func add(_ m: NSMenu, _ title: String, _ sel: Selector, key: String = "", symbol: String? = nil) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        i.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        m.addItem(i)
    }
    @objc func vocabulary() { if let u = store.url, FileManager.default.fileExists(atPath: u.path) { NSWorkspace.shared.open(u) } }
    @objc func settings() { showSettings() }
    @objc func restartNow() { restart() }

    // the icon goes, and stays gone (menuBar false in the settings); opening the app again shows the settings
    @objc func hide() {
        setSetting("menuBar", false)
        NSStatusBar.system.removeStatusItem(item)
        menu = nil
        present(message("Menu bar icon hidden. For the settings (and to show the icon again), open Lookup Word from your Applications folder."), at: nil)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { _ in close() }
        timer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in close() }
    }

    // a clean exit: launchd's KeepAlive (SuccessfulExit false) leaves it stopped until the next login
    @objc func quit() { exit(0) }

    // after a confirmation, uninstall() (below), then what it did, then the launch agent unloaded, which ends this too
    @objc func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Uninstall Lookup Word?"
        a.informativeText = "This removes the app, stops it starting at login, and resets its permissions."
            + (store.url.map { $0.path.hasPrefix(Paths.support.path + "/") ? "" : "\n\nYour vocabulary at \($0.path) stays." } ?? "")
        a.showsSuppressionButton = true
        a.suppressionButton?.title = "Also delete my settings and the vocabulary in Lookup Word's own folder"
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        a.buttons[0].hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let r = uninstallApp(purge: a.suppressionButton?.state == .on)
        let done = NSAlert()
        done.messageText = r.failed.isEmpty ? "Lookup Word is uninstalled" : "Lookup Word is partly uninstalled"
        done.informativeText = r.report
        done.alertStyle = r.failed.isEmpty ? .informational : .warning
        done.addButton(withTitle: "OK")
        done.runModal()
        unloadAgent()
        exit(0)
    }
}

// What uninstall.sh does, from the app (the menu, or `LookupWord --uninstall [--purge]`): the launch agent's file, the
// app and its permissions go; the settings and the support folder's vocabulary only with purge; a vocabulary file
// elsewhere (a note in a vault) never. The permissions are reset here, while this process lives: launchd ends every
// process of the job when it exits, so a helper left to do it afterwards is killed first.
struct Uninstalled { var removed: [String], failed: [String], kept: [String]
    var report: String {  // in steps: as one expression, older Swift (macos-14 CI) gives up type-checking it
        var parts: [String] = ["Removed: " + removed.joined(separator: ", ") + "."]
        if !failed.isEmpty { parts.append("Could not remove: " + failed.joined(separator: "; ")) }
        parts += kept
        parts.append("To install it again, run install.sh from its folder.")
        return parts.joined(separator: "\n\n")
    }
}
// An installed app knows its own identifier; a copy run from the build folder has none, and must never guess one (it
// would act on another copy's launch agent, permissions and folders).
var isInstalledApp: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app") }
var agentLabel: String { Bundle.main.bundleIdentifier ?? "" }
func uninstallApp(purge: Bool) -> Uninstalled {
    let fm = FileManager.default, home = fm.homeDirectoryForCurrentUser
    var r = Uninstalled(removed: [], failed: [], kept: [])
    guard isInstalledApp else { r.failed.append("nothing: this copy is not an installed app"); return r }
    // each removal, reported: what it removed, or why not (a file already gone counts as removed)
    func remove(_ url: URL, _ what: String) {
        guard fm.fileExists(atPath: url.path) else { r.removed.append(what); return }
        do { try fm.removeItem(at: url); r.removed.append(what) } catch { r.failed.append("\(what): \(error.localizedDescription)") }
    }
    // the permissions first: tccutil finds the app by its identifier through macOS's app registry, which forgets it
    // once the app is deleted ("No such bundle identifier"), so resetting after the removal never worked
    var permissions = true
    for service in ["Accessibility", "ScreenCapture"] {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        t.arguments = ["reset", service, agentLabel]
        t.standardOutput = FileHandle.nullDevice
        if (try? t.run()) != nil { t.waitUntilExit() }
        if t.terminationStatus != 0 { permissions = false; r.failed.append("the \(service == "ScreenCapture" ? "Screen Recording" : service) permission") }
    }
    if permissions { r.removed.append("its permissions") }
    remove(home.appendingPathComponent("Library/LaunchAgents/\(agentLabel).plist"), "starting at login")
    if purge {
        remove(Paths.support, "your settings and Lookup Word's own folder")
        remove(Paths.logs, "its logs")
    }
    if Bundle.main.bundlePath.hasSuffix(".app") { remove(Bundle.main.bundleURL, "the app") }
    if !purge { r.kept.append("Your settings stay in \(Paths.support.path).") }
    if let u = store.url, !(purge && u.path.hasPrefix(Paths.support.path + "/")) { r.kept.append("Your vocabulary stays at \(u.path).") }
    return r
}
// the launch agent unloaded: ends the agent's process (this one, from the menu)
func unloadAgent() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = ["bootout", "gui/\(getuid())/\(agentLabel)"]
    p.standardError = FileHandle.nullDevice
    if (try? p.run()) != nil { p.waitUntilExit() }
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

// `LookupWord --render-welcome out.png [ready]` draws the welcome window, dark, to an image
if let i = args.firstIndex(of: "--render-welcome"), i + 1 < args.count {
    NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    let model = WelcomeModel(); model.trusted = args.contains("ready"); model.screen = args.contains("ready")
    let v = NSHostingView(rootView: WelcomeView(model: model) { })
    v.appearance = NSAppearance(named: .darkAqua)
    v.frame = NSRect(origin: .zero, size: v.fittingSize)
    v.layoutSubtreeIfNeeded()
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
    print("wrote \(args[i + 1]) \(Int(v.bounds.width))×\(Int(v.bounds.height))"); exit(0)
}

// `LookupWord --render-settings out.png` draws the settings window, dark, to an image
if let i = args.firstIndex(of: "--render-settings"), i + 1 < args.count {
    NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    let v = NSHostingView(rootView: SettingsView(model: SettingsModel()) { _ in })
    v.appearance = NSAppearance(named: .darkAqua)
    v.frame = NSRect(origin: .zero, size: v.fittingSize)
    v.layoutSubtreeIfNeeded()
    let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
    v.cacheDisplay(in: v.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
    print("wrote \(args[i + 1]) \(Int(v.bounds.width))×\(Int(v.bounds.height))"); exit(0)
}

// `LookupWord --uninstall [--purge]` does what the menu's Uninstall does, without asking: for scripts and tests
if args.contains("--uninstall") {
    // only as an installed app, which knows its own identifier: never guess it (it would uninstall another copy)
    guard isInstalledApp else {
        print("Run it from the installed app: \"~/Applications/Lookup Word.app/Contents/MacOS/LookupWord\" --uninstall"); exit(1)
    }
    let r = uninstallApp(purge: args.contains("--purge"))
    unloadAgent()
    print(r.report); exit(r.failed.isEmpty ? 0 : 1)
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

// One copy at a time: a second (opened from Finder while the launch agent's runs, or a second install's) brings the
// running one forward and quits. A copy started by restart() says so (--replacing) and waits for the old one to go.
if let id = Bundle.main.bundleIdentifier {
    let others = { NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != getpid() } }
    if args.contains("--replacing") {
        for _ in 0..<50 where !others().isEmpty { Thread.sleep(forTimeInterval: 0.1) }
    } else if let running = others().first {
        log("already running (pid \(running.processIdentifier)): this copy quits")
        running.activate()
        exit(0)
    }
}
// a test copy (scripts/test-install.sh) runs without a menu bar icon or welcome window
let quiet = ProcessInfo.processInfo.environment["LOOKUP_QUIET"] != nil

let app = NSApplication.shared
DispatchQueue.main.async { for p in packs where p.lemmas != nil { _ = lemma("", p) } }  // read lemma lists at start, not on first use
app.setActivationPolicy(.accessory)
watchKeys()
registerTypeShortcut()
var menu = !quiet && (config.menuBar || !AXIsProcessTrusted()) ? Menu() : nil  // shown while it cannot work, even when hidden
// the icon kept up to date with the permission: back to the book once it is given (and gone again if the settings
// hide it), a warning again if it is taken away
Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
    if !AXIsProcessTrusted(), menu == nil, !quiet { menu = Menu() }
    if AXIsProcessTrusted(), !config.menuBar, let m = menu { NSStatusBar.system.removeStatusItem(m.item); menu = nil }
    menu?.refresh()
}
if shouldWelcome(), !quiet { DispatchQueue.main.async { showWelcome() } }  // the first launch, or while Accessibility is missing

// Opening the app while it runs (double-clicking it in Applications, Spotlight) shows its settings.
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // the way in when the icon is hidden: the welcome while it cannot work yet, else the settings
        if AXIsProcessTrusted() { showSettings() } else { showWelcome() }
        return false
    }
}
let delegate = Delegate()
app.delegate = delegate
if args.contains("--now") { DispatchQueue.main.async { lookUp() } }  // a test: look up at once
app.run()
