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
            try migrateMatchingDigests()
        }
        let live = Set(history.clips.map { payloadURL($0.storageID).lastPathComponent })
        for url in try file.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        where url.pathExtension == "clip" && !live.contains(url.lastPathComponent) {
            try file.removeItem(at: url)
        }
    }

    private func payloadURL(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString + ".clip") }

    private func migrateMatchingDigests() throws {
        guard history.clips.contains(where: { $0.matchingDigest == nil }) else { return }
        var clips: [Clip] = []
        var positions: [String: Int] = [:]
        for var clip in history.clips {
            if clip.matchingDigest == nil {
                if clip.kind == .image || clip.kind == .files {
                    clip.matchingDigest = clip.digest
                } else if let stored = try? readPayload(clip.storageID) {
                    clip.matchingDigest = stored.textDigest ?? clip.digest
                }
            }
            if let key = clip.matchingDigest, let position = positions[key] {
                clips[position].boards.formUnion(clip.boards)
                if clips[position].customName == nil { clips[position].customName = clip.customName }
            } else {
                if let key = clip.matchingDigest { positions[key] = clips.count }
                clips.append(clip)
            }
        }
        try update { $0.clips = clips }
    }

    private func readPayload(_ storageID: UUID) throws -> Payload {
        try PropertyListDecoder().decode(Payload.self, from: Data(contentsOf: payloadURL(storageID)))
    }

    func payload(for id: UUID) throws -> Payload {
        guard let clip = history.clips.first(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        return try readPayload(clip.storageID)
    }

    func savePayload(_ payload: Payload, for id: UUID) throws {
        guard let clip = history.clips.first(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        try PropertyListEncoder().encode(payload).write(to: payloadURL(clip.storageID), options: .atomic)
    }

    func update(_ change: (inout History) -> Void) throws {
        var next = history
        change(&next)
        try PropertyListEncoder().encode(next).write(to: index, options: .atomic)
        let retained = Set(next.clips.map(\.storageID))
        let removed = history.clips.filter { !retained.contains($0.storageID) }
        history = next
        for clip in removed { try? file.removeItem(at: payloadURL(clip.storageID)) }
    }

    func record(_ payload: Payload, source: String, sourceBundleID: String? = nil) throws {
        let digest = payload.digest
        let key = payload.textDigest ?? digest
        let position = history.clips.firstIndex { $0.matchingDigest == key || $0.digest == digest }
        let existing = position.map { history.clips[$0] }
        if let position, let existing, existing.matchingDigest != nil, existing.digest == digest {
            if let bookmarks = payload.fileBookmarks {
                let id = existing.id
                var stored = try self.payload(for: id)
                for (index, data) in bookmarks { stored.saveBookmark(data, at: index) }
                try savePayload(stored, for: id)
            }
            try update {
                var clip = $0.clips.remove(at: position)
                clip.date = .now
                clip.source = source
                clip.sourceBundleID = sourceBundleID
                $0.clips.insert(clip, at: 0)
            }
            return
        }
        var clip = Clipboard.describe(payload, source: source, digest: digest, id: existing?.id ?? UUID())
        clip.matchingDigest = key
        clip.sourceBundleID = sourceBundleID
        if let existing {
            clip.boards = existing.boards
            clip.customName = existing.customName
            clip.payloadID = UUID()
        }
        let url = payloadURL(clip.storageID)
        try PropertyListEncoder().encode(payload).write(to: url, options: .atomic)
        do {
            try update {
                if let position { $0.clips.remove(at: position) }
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
