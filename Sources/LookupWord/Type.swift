// The type-a-word box: a shortcut (⌃⌘L by default) from anywhere opens a small box near the top of the screen, as Spotlight's;
// type a word, press Return, and its card shows below the box, saved like any other lookup. Escape closes the card,
// and then the box; a click elsewhere closes both, unless the box is pinned. The shortcut is a hot key registered with macOS (Carbon's RegisterEventHotKey), which needs no
// permission, so the box works even before Accessibility is allowed.
import AppKit
import Carbon.HIToolbox

// The shortcuts to choose from (Settings), as few as keeps them easy: ⌃⌘L by default, as neither macOS nor the usual
// window managers use it (Rectangle takes ⌃⌥ with letters).
let typeShortcuts: [(id: String, key: UInt32, modifiers: UInt32, symbol: String)] = [
    ("control-command-l", UInt32(kVK_ANSI_L), UInt32(controlKey | cmdKey), "⌃⌘L"),
    ("option-command-l", UInt32(kVK_ANSI_L), UInt32(optionKey | cmdKey), "⌥⌘L"),
    ("control-option-command-l", UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey | cmdKey), "⌃⌥⌘L"),
    ("control-option-l", UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey), "⌃⌥L"),
    ("none", 0, 0, "none"),
]
let typeShortcut = typeShortcuts.first { $0.id == config.typeShortcut } ?? typeShortcuts[0]
var typeShortcutTaken = false  // macOS refused it: another app has it

let typeBoxOriginKey = "typeBoxOrigin"  // where he last dragged the box; none: centred

final class TypeBox: NSPanel, NSTextFieldDelegate, NSWindowDelegate {
    let field = NSTextField()
    let pin = NSButton()
    // pinned, a click outside leaves the box (and its card) open; Escape closes the card first, then the box
    var pinned = false { didSet { showPin() } }
    init() {
        let size = NSSize(width: 400, height: 44)  // small, as Spotlight's field (his report, 2026-11-02: "too big")
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .popover; glass.state = .active; glass.blendingMode = .behindWindow
        let icon = NSImageView(frame: NSRect(x: 14, y: 12, width: 20, height: 20))
        icon.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        icon.contentTintColor = .secondaryLabelColor
        field.frame = NSRect(x: 42, y: 11, width: size.width - 84, height: 22)
        field.placeholderString = "Type a word, then Return"
        field.font = .systemFont(ofSize: 16)
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.delegate = self
        pin.frame = NSRect(x: size.width - 38, y: 10, width: 24, height: 24)
        pin.isBordered = false; pin.bezelStyle = .regularSquare; pin.imagePosition = .imageOnly
        pin.target = self; pin.action = #selector(togglePin)
        showPin()
        glass.addSubview(icon); glass.addSubview(field); glass.addSubview(pin)
        contentView = glass
        delegate = self
    }
    @objc func togglePin() { pinned.toggle() }
    func showPin() {
        pin.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: pinned ? "Unpin" : "Pin")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        pin.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        pin.toolTip = pinned ? "Pinned: stays open when you click elsewhere" : "Pin: keep it open when you click elsewhere"
    }
    override var canBecomeKey: Bool { true }

    // the app has no Edit menu, so ⌘A, ⌘C, ⌘V, ⌘X and ⌘Z reach the field only from here (his ask, 2026-11-02: "cmd + A to
    // select all")
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function]) == .command,
              let key = e.charactersIgnoringModifiers?.lowercased() else { return super.performKeyEquivalent(with: e) }
        let actions: [String: Selector] = ["a": #selector(NSText.selectAll(_:)), "c": #selector(NSText.copy(_:)),
                                           "v": #selector(NSText.paste(_:)), "x": #selector(NSText.cut(_:)),
                                           "z": Selector(("undo:"))]
        if let a = actions[key], NSApp.sendAction(a, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: e)
    }

    // where he last dragged it, while that is still on a screen; else centred, a fifth of the way down the screen the
    // pointer is on (his reports, 2026-11-02: "did not open in the center", "an option to reset position")
    var placing = false
    func place() {
        placing = true; defer { placing = false }
        if let s = UserDefaults.standard.string(forKey: typeBoxOriginKey) {
            let saved = NSPointFromString(s)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(NSRect(origin: saved, size: frame.size)) }) {
                return setFrameOrigin(saved)
            }
        }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main!
        let v = screen.visibleFrame
        setFrameOrigin(NSPoint(x: v.midX - frame.width / 2, y: v.maxY - frame.height - v.height * 0.18))
    }
    func windowDidMove(_ n: Notification) {
        if !placing { UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: typeBoxOriginKey) }
    }

    // the text cleared: its card goes too
    func controlTextDidChange(_ n: Notification) {
        if field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty, pop != nil { closeCard() }
    }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        // Escape: the card first, leaving the box (pinned or not) for the next word; then the box
        if sel == #selector(NSResponder.cancelOperation(_:)) { if pop != nil { closeCard() } else { closeTypeBox() }; return true }
        if sel == #selector(NSResponder.insertNewline(_:)) {
            let word = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty { lookUpTyped(word, below: frame) }
            return true
        }
        return false
    }
}

var typeBox: TypeBox?
func showTypeBox() {
    close()  // a card already open
    if typeBox == nil { typeBox = TypeBox() }
    typeBox?.place()
    // a click outside closes it, before a word is typed too (his ask, 2026-11-02)
    monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in closeUnlessPinned() }
    NSApp.activate(ignoringOtherApps: true)
    typeBox?.makeKeyAndOrderFront(nil)
    typeBox?.field.selectText(nil)  // the last word, selected: type over it or press Return again
}
func closeTypeBox() { typeBox?.orderOut(nil); close() }
func resetTypeBoxPosition() {
    UserDefaults.standard.removeObject(forKey: typeBoxOriginKey)
    if typeBox?.isVisible == true { typeBox?.place() }
}
func closeUnlessPinned() { if typeBox?.pinned != true { closeTypeBox() } }
// the card only: the box stays, with its click-outside watch while it is not pinned
func closeCard() {
    close()
    if typeBox?.isVisible == true {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in closeUnlessPinned() }
    }
}

// The typed word's card, hanging below the box; the text's language is the word's own (there is no text around it).
func lookUpTyped(_ word: String, below box: NSRect) {
    close()
    shown += 1
    let mine = shown
    // a click outside the box and the card closes both; keys go to the box, so typing the next word just works
    monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in closeUnlessPinned() }
    if config.closeAfter > 0, typeBox?.pinned != true { timer = Timer.scheduledTimer(withTimeInterval: config.closeAfter, repeats: false) { _ in close() } }
    show(word, NSRect(x: box.midX - 1, y: box.minY - 1, width: 2, height: 2), word, mine, highlight: false)
    // the box keeps the keyboard, so the next word can be typed at once (showing the card would take it)
    DispatchQueue.main.async {
        guard let b = typeBox else { return }
        b.makeKeyAndOrderFront(nil)
        b.makeFirstResponder(b.field)
        b.field.currentEditor()?.selectedRange = NSRange(location: b.field.stringValue.utf16.count, length: 0)
    }
}

// the hot key: registered once at launch; macOS calls back on the main thread
var hotKeyRef: EventHotKeyRef?
func registerTypeShortcut() {
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
        DispatchQueue.main.async { showTypeBox() }
        return noErr
    }, 1, &spec, nil, nil)
    let id = EventHotKeyID(signature: OSType(0x4C6B5764), id: 1)  // "LkWd"
    guard typeShortcut.id != "none" else { return }
    let status = RegisterEventHotKey(typeShortcut.key, typeShortcut.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    if status != noErr { typeShortcutTaken = true; log("the \(typeShortcut.symbol) shortcut is taken by another app (\(status))") }
}
