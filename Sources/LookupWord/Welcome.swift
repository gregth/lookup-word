// The welcome window: shown at launch while Accessibility is not allowed, which the app cannot work without (the
// double-tap and the selection both need it). It says why, opens the right Settings page, and notices by itself when
// the permission is given: no terminal, no restart. Screen Recording is not asked here: macOS asks the first time the
// user points at a word, and the card explains it then.
import AppKit
import SwiftUI

final class WelcomeModel: ObservableObject {
    @Published var trusted = AXIsProcessTrusted()
    var timer: Timer?
    func watch(_ done: @escaping () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self, AXIsProcessTrusted(), !self.trusted else { return }
            self.trusted = true
            t.invalidate()
            done()
        }
    }
    func openSettings() {
        // the prompt adds Lookup Word to the list (switched off), so there is nothing to find or drag in
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: appIcon).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Lookup Word").font(.title2.weight(.semibold))
                    Text("Select a word anywhere and double-tap \(hotkey.symbol).").foregroundStyle(.secondary)
                }
            }
            if model.trusted {
                Label("Ready: select a word, or point at one, and double-tap \(hotkey.symbol).", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Pointing at a word without selecting it needs Screen Recording as well; macOS asks the first time.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("It needs one permission first: **Accessibility**, to notice the double-tap and read the word you select. It reads nothing else, and nothing leaves your Mac.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Open the setting, switch Lookup Word on, and come back: this window notices by itself.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if !model.trusted {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the permission…").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if model.trusted {
                    Button("Done") { onDone() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Later") { onDone() }.keyboardShortcut(.cancelAction)
                    Button("Open Settings") { model.openSettings() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// the app's own icon: from its bundle, or from the source tree's docs/ for a copy run from the build folder
var appIcon: NSImage {
    let docs = Paths.packs.deletingLastPathComponent().appendingPathComponent("docs/AppIcon.icns")
    return (Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ?? docs).flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage
}

var welcomeWindow: NSWindow?
func showWelcome() {
    NSApp.activate(ignoringOtherApps: true)
    if let w = welcomeWindow { w.makeKeyAndOrderFront(nil); return }
    let model = WelcomeModel()
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.title = "Lookup Word"
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: WelcomeView(model: model) { welcomeWindow?.close(); welcomeWindow = nil })
    w.setContentSize(w.contentView!.fittingSize)
    w.center()
    w.makeKeyAndOrderFront(nil)
    welcomeWindow = w
    // once allowed: the shortcut's monitors again, since those added before the permission may not see other apps' keys
    model.watch {
        watchKeys()
        if let w = welcomeWindow { w.setContentSize(w.contentView!.fittingSize) }
    }
}
