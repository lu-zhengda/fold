import AppKit
import CryptoKit

enum ClipKind: String, Codable, CaseIterable {
    case text, link, image, files, color, code

    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .files: "folder"
        case .color: "paintpalette"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct Clip: Identifiable, Codable {
    let id: UUID
    let digest: String
    var date: Date
    var source: String
    var sourceBundleID: String? = nil
    let kind: ClipKind
    let preview: String
    let detail: String
    let thumbnail: Data?
    let size: Int
    var boards: Set<UUID> = []
    var customName: String?

    mutating func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        customName = trimmed.isEmpty ? nil : trimmed
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || [customName ?? "", preview, source, detail, kind.rawValue].contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

struct Board: Identifiable, Codable {
    let id: UUID
    var name: String
    static let favorites = Board(id: UUID(uuidString: "E86A5809-F384-47AD-83AF-3E543F01C845")!, name: "Favorites")
}

struct History: Codable {
    var clips: [Clip] = []
    var boards = [Board.favorites]
}

struct Payload: Codable {
    var items: [[String: Data]]
    var fileBookmarks: [Int: Data]?

    mutating func saveBookmark(_ bookmark: Data, at index: Int) {
        if fileBookmarks == nil { fileBookmarks = [:] }
        fileBookmarks?[index] = bookmark
    }

    var size: Int { items.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } }
    var digest: String {
        var hash = SHA256()
        func addLength(_ length: Int) {
            withUnsafeBytes(of: UInt64(length).bigEndian) { hash.update(bufferPointer: $0) }
        }
        for item in items {
            addLength(item.count)
            for (type, data) in item.sorted(by: { $0.key < $1.key }) {
                let label = Data(type.utf8)
                addLength(label.count)
                hash.update(data: label)
                addLength(data.count)
                hash.update(data: data)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
