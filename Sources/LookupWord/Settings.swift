// The settings window: every setting as a control, saved to config.json (any other key in the file kept), then a
// restart to apply them.
import AppKit
import SwiftUI

final class SettingsModel: ObservableObject {
    struct Language: Identifiable { var id: String { code }; var code: String; var name: String; var flag: String; var missing: [String] }

    @Published var languages: Set<String>
    @Published var hotkey: String
    @Published var screenReading: Bool
    @Published var menuBar: Bool
    @Published var closeAfter: Double
    @Published var storeType: String
    @Published var storePath: String
    @Published var saveDate: Bool
    let available: [Language]
    struct Snapshot: Equatable { var languages: Set<String>; var hotkey: String; var screenReading, menuBar: Bool; var closeAfter: Double; var storeType, storePath: String; var saveDate: Bool }
    var snapshot: Snapshot { Snapshot(languages: languages, hotkey: hotkey, screenReading: screenReading, menuBar: menuBar, closeAfter: closeAfter, storeType: storeType, storePath: storePath, saveDate: saveDate) }
    var saved = Snapshot(languages: [], hotkey: "", screenReading: false, menuBar: false, closeAfter: 0, storeType: "", storePath: "", saveDate: false)

    init() {
        // what the file says now (it may have changed since launch), falling back to the settings in force
        let file = (try? Data(contentsOf: Paths.config)).flatMap { try? JSONDecoder().decode(Config.self, from: $0) } ?? config
        languages = Set(file.languages + ["en"])
        hotkey = ["option", "control", "command", "shift"].contains(file.hotkey) ? file.hotkey : "option"
        screenReading = file.screenReading
        menuBar = file.menuBar
        closeAfter = file.closeAfter
        storeType = file.store.type
        storePath = file.store.path ?? ""
        saveDate = file.store.saveDate
        available = availablePacks.compactMap(loadPack).map { p in
            Language(code: p.code, name: p.name, flag: p.flag ?? "", missing: [p.monolingual, p.bilingual].compactMap { $0 }.filter { dictionaries[$0] == nil })
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
        dict["screenReading"] = screenReading
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
                    Picker("Shortcut", selection: $model.hotkey) {
                        Text("Double-tap ⌥ Option").tag("option")
                        Text("Double-tap ⌃ Control").tag("control")
                        Text("Double-tap ⌘ Command").tag("command")
                        Text("Double-tap ⇧ Shift").tag("shift")
                    }
                    Toggle(isOn: $model.screenReading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Read the word under the pointer")
                            Text("When nothing is selected. Needs Screen Recording permission.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if model.screenReading && !CGPreflightScreenCaptureAccess() {
                        Button("Open Screen Recording Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                    Toggle("Show the menu bar icon", isOn: $model.menuBar)
                    HStack {
                        Text("Close the card after")
                        Spacer()
                        TextField("", value: $model.closeAfter, format: .number).frame(width: 50).multilineTextAlignment(.trailing)
                        Stepper("", value: $model.closeAfter, in: 0...600, step: 5).labelsHidden()
                        Text(model.closeAfter == 0 ? "never" : "seconds").foregroundStyle(.secondary).frame(width: 60, alignment: .leading)
                    }
                } header: { Text("Looking up") }

                Section {
                    ForEach(model.available) { lang in
                        Toggle(isOn: Binding(get: { model.languages.contains(lang.code) },
                                             set: { on in if on { model.languages.insert(lang.code) } else { model.languages.remove(lang.code) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(lang.flag)  \(lang.name)")
                                if lang.code == "en" {
                                    Text("Always on: other languages translate through English").font(.caption).foregroundStyle(.secondary)
                                }
                                if !lang.missing.isEmpty {
                                    Text("Enable in Dictionary.app → Settings: " + lang.missing.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }.disabled(lang.code == "en")
                    }
                    if model.available.contains(where: { !$0.missing.isEmpty }) {
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

// A restart with the new settings. Under its launch agent, launchd restarts the job itself (kickstart -k), at once and
// without the 10 s throttle a failure exit would wait; a helper left to reopen the app afterwards dies with it, since
// launchd ends every process of the job (the old way, which left it stopped). Started any other way (from Terminal,
// swift run), a new copy is opened before this one quits.
func restart() {
    let label = Bundle.main.bundleIdentifier ?? "io.github.gregth.lookup-word"
    if getppid() == 1 {  // launchd's child
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["kickstart", "-k", "gui/\(getuid())/\(label)"]
        if (try? p.run()) != nil { p.waitUntilExit() }  // launchd stops this process before it returns
        exit(1)  // kickstart refused (not loaded under that label): KeepAlive restarts it after the failure exit
    }
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { _, _ in exit(0) }
}
