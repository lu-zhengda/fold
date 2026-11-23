import Foundation

final class Library {
    private(set) var history: History
    private let folder: URL
    private var index: URL { folder.appendingPathComponent("History.plist") }
    private let file = FileManager.default

    init(folder: URL) throws {
        self.folder = folder
        history = History()
        try file.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if file.fileExists(atPath: index.path) {
            history = try PropertyListDecoder().decode(History.self, from: Data(contentsOf: index))
        }
        let live = Set(history.clips.map { payloadURL($0.id).lastPathComponent })
        for url in try file.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where url.pathExtension == "clip" && !live.contains(url.lastPathComponent) {
            try file.removeItem(at: url)
        }
    }

    private func payloadURL(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".clip") }

    func payload(for id: UUID) throws -> Payload {
        try PropertyListDecoder().decode(Payload.self, from: Data(contentsOf: payloadURL(id)))
    }

    func savePayload(_ payload: Payload, for id: UUID) throws {
        try PropertyListEncoder().encode(payload).write(to: payloadURL(id), options: .atomic)
    }

    func update(_ change: (inout History) -> Void) throws {
        var next = history
        change(&next)
        try PropertyListEncoder().encode(next).write(to: index, options: .atomic)
        let retained = Set(next.clips.map(\.id))
        let removed = history.clips.filter { !retained.contains($0.id) }
        history = next
        for clip in removed { try? file.removeItem(at: payloadURL(clip.id)) }
    }

    func record(_ payload: Payload, source: String, sourceBundleID: String? = nil) throws {
        let digest = payload.digest
        if let index = history.clips.firstIndex(where: { $0.digest == digest }) {
            if let bookmarks = payload.fileBookmarks {
                let id = history.clips[index].id
                var stored = try self.payload(for: id)
                for (index, data) in bookmarks { stored.saveBookmark(data, at: index) }
                try savePayload(stored, for: id)
            }
            try update {
                var clip = $0.clips.remove(at: index)
                clip.date = .now
                clip.source = source
                clip.sourceBundleID = sourceBundleID
                $0.clips.insert(clip, at: 0)
            }
            return
        }
        var clip = Clipboard.describe(payload, source: source, digest: digest)
        clip.sourceBundleID = sourceBundleID
        let url = payloadURL(clip.id)
        try PropertyListEncoder().encode(payload).write(to: url, options: .atomic)
        do {
            try update {
                $0.clips.insert(clip, at: 0)
                Self.trim(&$0)
            }
        } catch {
            try? file.removeItem(at: url)
            throw error
        }
    }

    static func trim(_ history: inout History) {
        var count = 0
        var bytes = 0
        history.clips = history.clips.filter {
            guard $0.boards.isEmpty else { return true }
            count += 1
            bytes += $0.size
            return count <= 500 && bytes <= 256 * 1024 * 1024
        }
    }
}
