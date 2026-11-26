import SwiftUI
import AppKit

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var history = History()
    @Published var boardID: UUID?
    @Published var query = ""
    @Published var selection: UUID?
    @Published var notice: String?
    @Published var openCount = 0
    @Published var searchFocusRequest = 0
    @Published var previewID: UUID?
    @Published var captureDenied = false
    @Published var shortcutAvailable = true
    @Published var paused = UserDefaults.standard.bool(forKey: "capturePaused") {
        didSet {
            lastChange = NSPasteboard.general.changeCount
            UserDefaults.standard.set(paused, forKey: "capturePaused")
        }
    }
    private var library: Library?
    /// Set only for `--library-folder`. Lets the smoke check capture even if
    /// the developer has paused capture, without writing that preference.
    private var smokeLibrary: URL?
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var noticeID = UUID()

    var visible: [Clip] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return history.clips.filter { clip in
            (boardID.map { clip.boards.contains($0) } ?? true) && clip.matches(term)
        }
    }
    var selected: Clip? { visible.first { $0.id == selection } ?? visible.first }

    func start() {
        do {
            let arguments = CommandLine.arguments
            let folder: URL
            if let override = LibraryLocation.overrideFolder(arguments: arguments) {
                smokeLibrary = override
                folder = override
            } else {
                let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                folder = LibraryLocation.folder(arguments: arguments, applicationSupport: root)
            }
            library = try Library(folder: folder)
            history = library!.history
        } catch { notice = "Couldn’t open local history. \(error.localizedDescription)"; return }
        let timer = Timer(timeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.capture() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func capture() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        captureDenied = board.accessBehavior == .alwaysDeny
        if captureDenied {
            noteCapture("denied")
            return
        }
        guard smokeLibrary != nil || !paused, let library else { return }
        guard let payload = Clipboard.read(board) else {
            noteCapture("unreadable")
            return
        }
        do {
            let app = NSWorkspace.shared.frontmostApplication
            try library.record(payload, source: app?.localizedName ?? "Clipboard", sourceBundleID: app?.bundleIdentifier)
            history = library.history
            noteCapture("recorded")
        } catch {
            noteCapture("save-failed")
            message("Couldn’t save this clip. \(error.localizedDescription)")
        }
    }

    /// Writes a one-line capture result next to the temporary history index.
    /// No-op unless `--library-folder` was passed.
    private func noteCapture(_ status: String) {
        guard let smokeLibrary else { return }
        let behavior: String
        switch NSPasteboard.general.accessBehavior {
        case .default: behavior = "default"
        case .ask: behavior = "ask"
        case .alwaysAllow: behavior = "alwaysAllow"
        case .alwaysDeny: behavior = "alwaysDeny"
        @unknown default: behavior = "unknown"
        }
        let line = status + " " + behavior + "\n"
        try? Data(line.utf8).write(to: smokeLibrary.appendingPathComponent("capture-status.txt"), options: .atomic)
    }

    func previewPayload(_ clip: Clip) -> Payload? {
        try? library?.payload(for: clip.id)
    }

    func restore(_ clip: Clip, authorizeFile: (URL) -> URL?) -> Bool {
        guard let library else { return false }
        do {
            var payload = try library.payload(for: clip.id)
            if clip.kind == .files {
                let bookmarks = payload.fileBookmarks
                try FileClips.restore(&payload, to: .general, authorize: authorizeFile)
                if payload.fileBookmarks != bookmarks { try library.savePayload(payload, for: clip.id) }
            } else if !Clipboard.write(payload, to: .general) {
                message("Couldn’t copy this clip.")
                return false
            }
            lastChange = NSPasteboard.general.changeCount
            return true
        } catch CocoaError.userCancelled { return false }
        catch { message("Couldn’t restore this clip. \(error.localizedDescription)"); return false }
    }

    func change(_ edit: (inout History) -> Void) {
        guard let library else { return }
        do {
            try library.update { state in edit(&state); Library.trim(&state) }
            history = library.history
        } catch { message("Couldn’t save changes. \(error.localizedDescription)") }
    }

    func toggle(_ clip: Clip, on board: Board) {
        change {
            guard let i = $0.clips.firstIndex(where: { $0.id == clip.id }) else { return }
            if $0.clips[i].boards.contains(board.id) { $0.clips[i].boards.remove(board.id) }
            else { $0.clips[i].boards.insert(board.id) }
        }
    }

    func move(_ delta: Int) {
        let cards = visible
        guard !cards.isEmpty else { return }
        let index = cards.firstIndex { $0.id == selection } ?? 0
        selection = cards[min(max(0, index + delta), cards.count - 1)].id
    }

    func delete(_ clip: Clip) {
        let cards = visible
        let wasSelected = selected?.id == clip.id
        change { $0.clips.removeAll { $0.id == clip.id } }
        guard wasSelected, !history.clips.contains(where: { $0.id == clip.id }),
              let index = cards.firstIndex(where: { $0.id == clip.id }) else { return }
        let remaining = visible
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }

    func message(_ text: String) {
        let id = UUID()
        noticeID = id
        notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard self?.noticeID == id else { return }
            self?.notice = nil
        }
    }
}
