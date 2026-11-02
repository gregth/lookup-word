// The welcome window: the two permissions, each with why and a button to its setting. Accessibility is required (the
// double-tap and the selection need it); Screen Recording is optional, for pointing at a word without selecting it,
// and can wait: pointing at a word later asks again, from the card. It shows at the first launch, and after that only
// while Accessibility is missing; it notices by itself when a permission is given: no terminal, no restart.
import AppKit
import SwiftUI

final class WelcomeModel: ObservableObject {
    @Published var trusted = AXIsProcessTrusted()
    @Published var screen = CGPreflightScreenCaptureAccess()
    var timer: Timer?
    func watch(_ gotAccessibility: @escaping () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.trusted, AXIsProcessTrusted() { self.trusted = true; gotAccessibility() }
            if !self.screen, CGPreflightScreenCaptureAccess() { self.screen = true }
        }
    }
}

struct PermissionRow: View {
    var title: String, badge: String, text: String, granted: Bool, pane: String
    @ObservedObject var asked = Asked.shared
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle").font(.title2)
                .foregroundStyle(granted ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Text(badge).font(.caption).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.2)))
                }
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if granted { Text("Allowed").font(.callout).foregroundStyle(.secondary) }
            else { Button(permissionButton(pane)) { askPermission(pane) } }
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: appIcon).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Lookup Word").font(.title2.weight(.semibold))
                    Text("Look up any word on your Mac, in all your languages.").foregroundStyle(.secondary)
                }
            }
            Text("There are two ways to look up a word you see on screen. Each needs a permission from you, which macOS asks for in System Settings.")
                .fixedSize(horizontal: false, vertical: true)
            PermissionRow(title: "Select a word", badge: "Needed",
                          text: "\(howSelect) For this, Lookup Word needs the permission macOS calls Accessibility, to notice the keys and read the word you selected.",
                          granted: model.trusted, pane: "Privacy_Accessibility")
            PermissionRow(title: "Point at a word", badge: "Optional",
                          text: "\(howPoint) \(whyScreen) You can allow it later: pointing at a word will ask again.",
                          granted: model.screen, pane: "Privacy_ScreenCapture")
            Text("You can also press \(typeShortcut.symbol) anywhere to type a word into a box: that needs no permission.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("When you click Allow, macOS asks you; choose Open System Settings there, turn on the switch next to Lookup Word, then come back here. This window updates by itself. For pointing, macOS may ask to quit and reopen Lookup Word.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if model.trusted {
                    Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the first permission…").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.trusted ? "Done" : "Later") { onDone() }.keyboardShortcut(model.trusted ? .defaultAction : .cancelAction)
            }
        }
        .padding(24)
        .frame(width: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// the app's own icon: from its bundle, or from the source tree's docs/ for a copy run from the build folder
var appIcon: NSImage {
    let docs = Paths.packs.deletingLastPathComponent().appendingPathComponent("docs/AppIcon.icns")
    let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ?? docs
    return NSImage(contentsOf: url) ?? NSApp.applicationIconImage
}

// the first launch, remembered, so the window shows once with both permissions and afterwards only while
// Accessibility is missing
var welcomed: URL { Paths.support.appendingPathComponent("welcomed") }
func shouldWelcome() -> Bool { !AXIsProcessTrusted() || !FileManager.default.fileExists(atPath: welcomed.path) }

var welcomeWindow: NSWindow?
func showWelcome() {
    NSApp.activate(ignoringOtherApps: true)
    if let w = welcomeWindow { w.makeKeyAndOrderFront(nil); return }
    FileManager.default.createFile(atPath: welcomed.path, contents: Data())
    let model = WelcomeModel()
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    w.title = "Lookup Word"
    w.isReleasedWhenClosed = false
    w.contentView = NSHostingView(rootView: WelcomeView(model: model) { welcomeWindow?.close(); welcomeWindow = nil })
    w.setContentSize(w.contentView!.fittingSize)
    w.center()
    w.makeKeyAndOrderFront(nil)
    welcomeWindow = w
    // once Accessibility is allowed: the shortcut's monitors again, since those added before it may not see other
    // apps' keys
    model.watch { watchKeys() }
}
