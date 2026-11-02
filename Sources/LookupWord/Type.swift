// The type-a-word box: a shortcut (⌃⌘L by default) from anywhere opens a small box near the top of the screen, as Spotlight's;
// type a word, press Return, and its card shows below the box, saved like any other lookup. Escape or a click
// elsewhere closes it. The shortcut is a hot key registered with macOS (Carbon's RegisterEventHotKey), which needs no
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

final class TypeBox: NSPanel, NSTextFieldDelegate {
    let field = NSTextField()
    let pin = NSButton()
    // pinned, a click outside leaves the box and its card open; Escape still closes them (his ask, 2026-11-02)
    var pinned = false { didSet { showPin() } }
    init() {
        let size = NSSize(width: 460, height: 56)
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
        let icon = NSImageView(frame: NSRect(x: 16, y: 16, width: 24, height: 24))
        icon.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        icon.contentTintColor = .secondaryLabelColor
        field.frame = NSRect(x: 50, y: 14, width: size.width - 98, height: 28)
        field.placeholderString = "Type a word in any of your languages, then press Return"
        field.font = .systemFont(ofSize: 20)
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.delegate = self
        pin.frame = NSRect(x: size.width - 44, y: 14, width: 28, height: 28)
        pin.isBordered = false; pin.bezelStyle = .regularSquare; pin.imagePosition = .imageOnly
        pin.target = self; pin.action = #selector(togglePin)
        showPin()
        glass.addSubview(icon); glass.addSubview(field); glass.addSubview(pin)
        contentView = glass
    }
    @objc func togglePin() { pinned.toggle() }
    func showPin() {
        pin.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: pinned ? "Unpin" : "Pin")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        pin.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        pin.toolTip = pinned ? "Pinned: stays open when you click elsewhere" : "Pin: keep it open when you click elsewhere"
    }
    override var canBecomeKey: Bool { true }

    // centred, a fifth of the way down the screen the pointer is on, at every open (his report, 2026-11-02: "did not
    // open in the center"; the box is made once, so placing it only then left it where it first opened or was dragged)
    func place() {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main!
        let v = screen.visibleFrame
        setFrameOrigin(NSPoint(x: v.midX - frame.width / 2, y: v.maxY - frame.height - v.height * 0.18))
    }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { closeTypeBox(); return true }
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
func closeUnlessPinned() { if typeBox?.pinned != true { closeTypeBox() } }

// The typed word's card, hanging below the box; the text's language is the word's own (there is no text around it).
func lookUpTyped(_ word: String, below box: NSRect) {
    close()
    shown += 1
    let mine = shown
    // a click outside the box and the card closes both; keys go to the box, so typing the next word just works
    monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in closeUnlessPinned() }
    if config.closeAfter > 0, typeBox?.pinned != true { timer = Timer.scheduledTimer(withTimeInterval: config.closeAfter, repeats: false) { _ in close() } }
    show(word, NSRect(x: box.midX - 1, y: box.minY - 1, width: 2, height: 2), word, mine, highlight: false)
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
