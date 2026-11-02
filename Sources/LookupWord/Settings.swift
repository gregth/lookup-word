// The settings window: every setting as a control, saved to config.json (any other key in the file kept), then a
// restart to apply them.
import AppKit
import ScreenCaptureKit
import SwiftUI

final class SettingsModel: ObservableObject {
    struct Language: Identifiable { var id: String { code }; var code: String; var name: String; var flag: String; var missing: [String]; var ids: [String] }

    @Published var languages: Set<String>
    @Published var hotkey: String
    @Published var typeKey: String
    @Published var menuBar: Bool
    @Published var closeAfter: Double
    @Published var storeType: String
    @Published var storePath: String
    @Published var saveDate: Bool
    @Published var enabling: Set<String> = []  // languages whose dictionaries are downloading
    let available: [Language]
    struct Snapshot: Equatable { var languages: Set<String>; var hotkey: String; var typeKey: String; var menuBar: Bool; var closeAfter: Double; var storeType, storePath: String; var saveDate: Bool }
    var snapshot: Snapshot { Snapshot(languages: languages, hotkey: hotkey, typeKey: typeKey, menuBar: menuBar, closeAfter: closeAfter, storeType: storeType, storePath: storePath, saveDate: saveDate) }
    var saved = Snapshot(languages: [], hotkey: "", typeKey: "", menuBar: false, closeAfter: 0, storeType: "", storePath: "", saveDate: false)

    init() {
        // what the file says now (it may have changed since launch), falling back to the settings in force
        let file = (try? Data(contentsOf: Paths.config)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? config
        languages = Set(file.languages + ["en"])
        hotkey = ["option", "control", "command", "shift"].contains(file.hotkey) ? file.hotkey : "option"
        typeKey = Shortcut.from(file.typeShortcut).id
        menuBar = file.menuBar
        closeAfter = file.closeAfter
        storeType = file.store.type
        storePath = file.store.path ?? ""
        saveDate = file.store.saveDate
        available = availablePacks.compactMap(loadPack).map { p in
            Language(code: p.code, name: p.name, flag: p.flag ?? "", missing: [p.monolingual, p.bilingual].compactMap { $0 }.filter { dictionaries[$0] == nil },
                     ids: p.dictionaryIds ?? [])
        }.sorted { ($0.code == "en" ? "" : $0.name) < ($1.code == "en" ? "" : $1.name) }
        saved = snapshot
    }

    var changed: Bool { saved != snapshot }
    var defaultPath: String { Paths.support.appendingPathComponent(storeType == "json" ? "vocabulary.json" : "Vocabulary.md").path }

    // into config.json: these keys only; any other key stays
    func save() {
        let data = try? Data(contentsOf: Paths.config)
        var dict = (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        if let data, !data.isEmpty, dict.isEmpty {  // not JSON: kept aside, not lost, before the window's settings replace it
            try? data.write(to: Paths.support.appendingPathComponent("config.broken.json"))
        }
        let order = available.map(\.code).filter { languages.contains($0) }
        dict["languages"] = ["en"] + order.filter { $0 != "en" }
        dict["hotkey"] = hotkey
        dict["typeShortcut"] = typeKey
        dict["screenReading"] = nil  // from versions with a switch for it
        dict["menuBar"] = menuBar
        dict["closeAfter"] = closeAfter
        var store = dict["store"] as? [String: Any] ?? [:]
        store["type"] = storeType
        let path = storePath.trimmingCharacters(in: .whitespaces)
        store["path"] = path.isEmpty ? nil : path
        store["saveDate"] = saveDate
        dict["store"] = store
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? (data + Data("\n".utf8)).write(to: Paths.config, options: .atomic)
        }
        saved = snapshot
    }

    func enable(_ lang: Language) {
        enableDictionaries(lang.ids)
        enabling.insert(lang.code)
        languages.insert(lang.code)
    }

    @Published var recordingShortcut = false
    var recorder: Any?
    func startRecording() {
        recordingShortcut = true
        recorder = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == 53, e.modifierFlags.intersection([.control, .option, .command]).isEmpty { self.stopRecording(); return nil }  // Escape
            if let s = Shortcut.from(e) { self.typeKey = s.id; self.stopRecording() } else { NSSound.beep() }
            return nil
        }
    }
    func stopRecording() {
        recordingShortcut = false
        if let m = recorder { NSEvent.removeMonitor(m); recorder = nil }
    }

    func choosePath() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = "Choose your vocabulary file (an existing note works: rows are only ever added)"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: storePath.isEmpty ? defaultPath : expand(storePath)).deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { storePath = url.path }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onDone: (Bool) -> Void  // true: restart with the new settings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    Picker("Key to press twice", selection: $model.hotkey) {
                        Text("⌥ Option").tag("option")
                        Text("⌃ Control").tag("control")
                        Text("⌘ Command").tag("command")
                        Text("⇧ Shift").tag("shift")
                    }
                    // the two ways, each with its permission: for anyone, in the words the welcome window uses
                    HowRow(title: "Select a word, then press the key twice",
                           text: "Double-click the word, or drag over it. Needs the Accessibility permission.",
                           allowed: AXIsProcessTrusted(), pane: "Privacy_Accessibility")
                    HowRow(title: "Point at a word, then press the key twice",
                           text: "Rest the mouse pointer on a word, without selecting it; works on pictures and videos too. Needs the Screen Recording permission: Lookup Word takes a picture of a small area around the pointer, only when you press the keys.",
                           allowed: CGPreflightScreenCaptureAccess(), pane: "Privacy_ScreenCapture")
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Or type a word, with a shortcut")
                            Text("Press it in any app: a box opens; type the word and press Return. Needs no permission.")
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Reset the box's position") { resetTypeBoxPosition() }
                                .buttonStyle(.link).font(.caption)
                                .help("The box opens where you last dragged it; this centres it again.")
                            if typeShortcutTaken && model.typeKey == typeShortcut.id {
                                Text("\(typeShortcut.symbol) is taken by another app: choose another.").font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        ShortcutRecorder(model: model)
                    }
                    Toggle("Show the menu bar icon", isOn: $model.menuBar)
                    HStack {
                        Text("Close the card after")
                        Spacer()
                        TextField("", value: $model.closeAfter, format: .number).frame(width: 50).multilineTextAlignment(.trailing)
                        Stepper("", value: $model.closeAfter, in: 0...600, step: 5).labelsHidden()
                        Text(model.closeAfter == 0 ? "never" : "seconds").foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                    }
                } header: { Text("How to look up a word") }

                Section {
                    ForEach(model.available) { lang in
                        HStack {
                            Toggle(isOn: Binding(get: { model.languages.contains(lang.code) },
                                                 set: { on in if on { model.languages.insert(lang.code) } else { model.languages.remove(lang.code) } })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(lang.flag)  \(lang.name)")
                                    if lang.code == "en" {
                                        Text("Always on: other languages translate through English").font(.caption).foregroundStyle(.secondary)
                                    }
                                    if model.enabling.contains(lang.code) {
                                        Text("Downloading in Dictionary.app, usually under two minutes. Then Save and Restart.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else if !lang.missing.isEmpty {
                                        Text((lang.missing.count == 1 ? "Needs the dictionary " : "Needs the dictionaries ") + lang.missing.joined(separator: ", ")
                                             + (lang.ids.isEmpty ? ": tick them in Dictionary → Settings…" : ""))
                                            .font(.caption).foregroundStyle(.orange)
                                    }
                                }
                            }.disabled(lang.code == "en")
                            if !lang.missing.isEmpty, !lang.ids.isEmpty, !model.enabling.contains(lang.code) {
                                Spacer()
                                Button("Enable") { model.enable(lang) }
                            }
                        }
                    }
                    if model.available.contains(where: { !$0.missing.isEmpty && $0.ids.isEmpty }) {
                        Button("Open Dictionary…") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Dictionary.app")) }
                    }
                } header: { Text("Languages") }

                Section {
                    Picker("Save words to", selection: $model.storeType) {
                        Text("A Markdown file").tag("markdown")
                        Text("A JSON file").tag("json")
                        Text("Nowhere").tag("none")
                    }
                    if model.storeType != "none" {
                        HStack {
                            TextField("File", text: $model.storePath, prompt: Text("\(model.storeType == "json" ? "vocabulary.json" : "Vocabulary.md") in Lookup Word's folder"))
                            Button("Choose…") { model.choosePath() }
                        }
                        Toggle("Also save the date and time of each lookup", isOn: $model.saveDate)
                        HStack {
                            Button("Show in Finder") {
                                let p = expand(model.storePath.isEmpty ? model.defaultPath : model.storePath)
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
                            }
                        }
                    }
                } header: { Text("Vocabulary") }
            }
            .formStyle(.grouped)

            HStack {
                if model.changed { Text("Changes apply after a restart.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { onDone(false) }.keyboardShortcut(.cancelAction)
                Button("Save and Restart") { model.save(); onDone(true) }
                    .keyboardShortcut(.defaultAction).disabled(!model.changed)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// The type-a-word box's shortcut, recorded: click, then press the combination (with ⌃, ⌥ or ⌘); Escape cancels; Off
// turns it off. The press is caught in this window only, while recording. (Its state lives in SettingsModel: the
// Command Line Tools' SwiftUI has no @State.)
struct ShortcutRecorder: View {
    @ObservedObject var model: SettingsModel
    var body: some View {
        HStack(spacing: 6) {
            Button(model.recordingShortcut ? "Press a shortcut…" : Shortcut.from(model.typeKey).symbol) {
                model.recordingShortcut ? model.stopRecording() : model.startRecording()
            }
            .frame(minWidth: 110)
            .help("Click, then press the keys: at least one of ⌃ Control, ⌥ Option or ⌘ Command, and a key. Escape cancels.")
            if model.typeKey != "none" && !model.recordingShortcut {
                Button("Off") { model.typeKey = "none" }.help("No shortcut: the box opens from the menu bar menu only")
            }
        }
        .onDisappear { model.stopRecording() }
    }
}

// one way to look a word up: what to do, what it needs, and whether that is allowed, with a button to allow it
struct HowRow: View {
    var title: String, text: String, allowed: Bool, pane: String
    @ObservedObject var asked = Asked.shared
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if allowed { Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.titleAndIcon) }
            else {
                Button(permissionButton(pane)) { askPermission(pane) }
            }
        }
    }
}

// A permission asked for through macOS's own prompt, which explains it and offers to open System Settings; the app
// opens nothing itself. macOS shows that prompt only the first time an app asks, so a second click (the button now
// says "Open Settings…") opens the setting's page instead, rather than seem to do nothing. Asking also lists the app
// under that permission, ready to switch on.
final class Asked: ObservableObject {
    static let shared = Asked()
    @Published var panes: Set<String> = []
}
func permissionButton(_ pane: String) -> String { Asked.shared.panes.contains(pane) ? "Open Settings…" : "Allow…" }
func askPermission(_ pane: String) {
    guard !Asked.shared.panes.contains(pane) else {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
        return
    }
    Asked.shared.panes.insert(pane)
    if pane == "Privacy_ScreenCapture" {
        // one way of asking only (two meant two prompts): a real attempt to capture, keeping nothing, which shows
        // macOS's prompt and lists the app, where CGRequestScreenCaptureAccess alone may not list it on recent macOS
        Task { _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }
    }
    else { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
}

// one settings window at a time, brought to the front
var settingsWindow: NSWindow?
func showSettings() {
    NSApp.activate(ignoringOtherApps: true)
    if let w = settingsWindow { w.makeKeyAndOrderFront(nil); return }
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.title = "Lookup Word Settings"
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: SettingsView(model: SettingsModel()) { restartNow in
        settingsWindow?.close(); settingsWindow = nil
        if restartNow { restart() }
    })
    w.setContentSize(w.contentView!.fittingSize)
    w.center()
    w.makeKeyAndOrderFront(nil)
    settingsWindow = w
}

// Turns dictionaries on as ticking them in Dictionary → Settings… does: their identifiers join Dictionary.app's list
// (DCSActiveDictionaries), and with Dictionary.app open macOS downloads the missing ones by itself (French, Spanish and
// German took under two minutes, 2026-11-02). With no list saved yet, macOS's own choice stands: the dictionaries in
// use now are written in first, so turning on one never turns the others off.
func enableDictionaries(_ ids: [String]) {
    let app = "com.apple.DictionaryServices" as CFString, key = "DCSActiveDictionaries" as CFString
    var active = CFPreferencesCopyAppValue(key, app) as? [String]
    if active == nil, let f = dlsym(dlopen(nil, RTLD_NOW), "DCSDictionaryGetIdentifier") {
        let id = unsafeBitCast(f, to: NameFn.self)
        active = dictionaries.values.compactMap { id($0)?.takeUnretainedValue() as String? }
    }
    var list = active ?? []
    list += ids.filter { !list.contains($0) }
    CFPreferencesSetAppValue(key, list as CFArray, app)
    CFPreferencesAppSynchronize(app)
    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Dictionary.app"))
}

// A restart with the new settings. The launch agent's copy (install.sh marks it with LOOKUP_AGENT) asks launchd to
// restart its job (kickstart -k), at once; a helper left to reopen the app afterwards would die with it, since launchd
// ends every process of the job. Any other copy (opened from Finder, Terminal, swift run), or a kickstart refused,
// opens a new copy of itself before this one quits.
func restart() {
    if ProcessInfo.processInfo.environment["LOOKUP_AGENT"] != nil, isInstalledApp {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["kickstart", "-k", "gui/\(getuid())/\(agentLabel)"]
        if (try? p.run()) != nil { p.waitUntilExit() }
        // launchctl answers before launchd has stopped this copy: wait to be stopped, rather than also opening a new
        // copy below (which left two running, two menu bar icons)
        if p.terminationStatus == 0 { Thread.sleep(forTimeInterval: 10); exit(1) }
    }
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.createsNewApplicationInstance = true
    cfg.arguments = ["--replacing"]  // the new copy waits for this one to quit, instead of deferring to it
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in exit(0) }
}
