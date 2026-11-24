import SwiftUI
import Carbon
import ApplicationServices

private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@main
@MainActor
enum FoldApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = FoldDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class FoldDelegate: NSObject, NSApplicationDelegate {
    private let store = ShelfStore()
    private lazy var settings = FoldSettings()
    private var settingsWindow: NSWindow?
    private var panel: NSPanel!
    private var status: NSStatusItem!
    private var hotKey: HotKey?
    private var keyMonitor: Any?
    private var target: NSRunningApplication?
    private var outsideClickMonitor: Any?
    private var choosingFile = false
    private var lastExternalApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        rememberExternalApp(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated(_:)),
                                                         name: NSWorkspace.didActivateApplicationNotification, object: nil)
        installEditMenu()
        store.start()
        _ = settings
        panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "Fold clipboard history"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ShelfView(
            store: store, use: { [weak self] in self?.use($0) },
            copy: { [weak self] in self?.copyClip($0) },
            dismiss: { [weak self] in self?.hide() },
            openSettings: { [weak self] in self?.openSettings() },
            enablePaste: { [weak self] in self?.enablePaste() },
            canPaste: { [weak self] in self?.canPaste ?? false }
        ))
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            button.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Fold clipboard history")
            button.toolTip = "Fold · Clipboard history (⌃⌥V)"
            button.target = self
            button.action = #selector(statusClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        hotKey = HotKey { [weak self] in self?.toggle() }
        store.shortcutAvailable = hotKey?.register() == true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        if launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue != keyAELaunchedAsLogInItem { show() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        dismissPanel()
    }

    private func rememberExternalApp(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
        lastExternalApp = app
    }

    @objc private func appActivated(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        rememberExternalApp(app)
        if !choosingFile, panel?.isVisible == true, let app, app != .current, let target, app != target {
            dismissPanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return false
    }

    @objc private func statusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for (title, action) in [("Open Fold", #selector(show)), ("Settings…", #selector(openSettings)), ("Check for Updates…", #selector(checkForUpdates)), (store.paused ? "Resume Capture" : "Pause Capture", #selector(pauseCapture)), ("Quit Fold", #selector(quit))] {
                let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
                item.target = self
                if action == #selector(checkForUpdates) { item.isEnabled = settings.canCheck }
            }
            status.menu = menu
            status.button?.performClick(nil)
            status.menu = nil
        } else { toggle() }
    }

    @objc private func openSettings() {
        dismissPanel()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 290),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Fold Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: FoldSettingsView(settings: settings))
            window.center()
            settingsWindow = window
        }
        settings.refreshLoginStatus()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkForUpdates() {
        dismissPanel()
        NSApp.activate()
        settings.checkNow()
    }

    @objc private func pauseCapture() { store.paused.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func toggle() {
        if panel.isKeyWindow && panel.isVisible { hide() } else { show() }
    }

    @objc private func show() {
        rememberExternalApp(NSWorkspace.shared.frontmostApplication)
        target = lastExternalApp
        store.capture()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        let width = bounds.width - 16
        panel.setFrame(NSRect(x: bounds.midX - width / 2, y: bounds.minY + 8, width: width, height: ShelfLayout.cardSize(width) + 78), display: true)
        store.previewID = nil
        store.searching = false
        store.query = ""
        store.selection = nil
        store.openCount += 1
        // A nonactivating panel borrows keyboard focus while the editor remains active.
        // Ordering it out gives the next keystroke back to the same editing window.
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.dismissPanel()
            }
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
    }

    private func dismissPanel() {
        guard !choosingFile else { return }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        panel?.orderOut(nil)
    }

    private func hide() {
        dismissPanel()
        // Explicit launches and some AppKit controls can still activate Fold.
        if NSApp.isActive {
            if let target, !target.isTerminated {
                NSApp.yieldActivation(to: target)
                target.activate(from: .current, options: [])
            }
            NSApp.hide(nil)
        }
    }

    private var canPaste: Bool { target?.isTerminated == false && AXIsProcessTrusted() }

    private func authorizeFile(_ url: URL) -> URL? {
        let picker = NSOpenPanel()
        picker.title = "Allow Fold to Copy This Item"
        picker.message = "Select “\(url.lastPathComponent)” to let Fold put it on the clipboard."
        picker.prompt = "Allow"
        picker.directoryURL = url.deletingLastPathComponent()
        picker.nameFieldStringValue = url.lastPathComponent
        picker.canChooseDirectories = url.hasDirectoryPath
        picker.canChooseFiles = !url.hasDirectoryPath
        picker.allowsMultipleSelection = false
        choosingFile = true
        defer { choosingFile = false }
        let accepted = picker.runModal() == .OK
        if !accepted { panel.makeKeyAndOrderFront(nil) }
        return accepted ? picker.url : nil
    }

    private func copyClip(_ clip: Clip) {
        if store.restore(clip, authorizeFile: authorizeFile) { hide() }
    }

    private func use(_ clip: Clip) {
        guard store.restore(clip, authorizeFile: authorizeFile) else { return }
        let destination = canPaste ? target : nil
        hide()
        if let destination {
            pasteWhenActive(destination, revision: NSPasteboard.general.changeCount, attempts: 12)
        }
    }

    private func pasteWhenActive(_ app: NSRunningApplication, revision: Int, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) { [weak self] in
            guard !app.isTerminated, NSPasteboard.general.changeCount == revision else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                if attempts > 1 { self?.pasteWhenActive(app, revision: revision, attempts: attempts - 1) }
                return
            }
            let source = CGEventSource(stateID: .privateState)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
                event?.flags = .maskCommand
                event?.postToPid(app.processIdentifier)
            }
        }
    }

    private func enablePaste() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        store.message(AXIsProcessTrustedWithOptions(options) ? "Automatic insertion is enabled" : "Allow Fold in System Settings → Privacy & Security → Accessibility")
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !choosingFile, panel.isVisible, panel.attachedSheet == nil,
              event.window === panel || (event.window == nil && panel.isKeyWindow) else { return event }
        let editing = (panel.firstResponder as? NSTextView)?.isFieldEditor == true
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad])
        if modifiers.subtracting(.capsLock) == .command, event.charactersIgnoringModifiers?.lowercased() == "c",
           !editing, store.previewID == nil, let clip = store.selected {
            copyClip(clip)
            return nil
        }
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "f" {
            store.previewID = nil
            store.searching = true
            store.searchFocusRequest += 1
            return nil
        }
        guard modifiers.subtracting([.shift, .capsLock]).isEmpty else { return event }
        if store.previewID != nil {
            if [kVK_Space, kVK_Escape].contains(Int(event.keyCode)) {
                store.previewID = nil
                return nil
            }
            return event
        }
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            guard !editing, modifiers.subtracting(.capsLock).isEmpty else { return event }
            if !event.isARepeat, let clip = store.selected { store.delete(clip) }
        case kVK_Space where !editing && !store.searching:
            store.previewID = store.selected?.id
        case kVK_Escape:
            if !store.query.isEmpty { store.query = "" }
            else if store.searching { store.searching = false }
            else { hide() }
        case kVK_LeftArrow where !editing: store.move(-1)
        case kVK_RightArrow where !editing: store.move(1)
        case kVK_Return where !editing, kVK_ANSI_KeypadEnter where !editing:
            if let clip = store.selected { use(clip) }
        default:
            guard !editing, let characters = event.characters, !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }) else { return event }
            store.searching = true
            store.searchFocusRequest += 1
            store.query += characters
        }
        return nil
    }

    private func installEditMenu() {
        let main = NSMenu()
        let menu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            menu.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        let item = main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        item.submenu = menu
        NSApp.mainMenu = main
    }
}
