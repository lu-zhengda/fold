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
    var matchingDigest: String?
    /// Staged payload id until the history index commits a replacement clip.
    var payloadID: UUID?
    var storageID: UUID { payloadID ?? id }
    var date: Date
    var source: String
    var sourceBundleID: String?
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
    static let favorites = Board(
        id: UUID(uuid: (0xE8, 0x6A, 0x58, 0x09, 0xF3, 0x84, 0x47, 0xAD, 0x83, 0xAF, 0x3E, 0x54, 0x3F, 0x01, 0xC8, 0x45)),
        name: "Favorites"
    )
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

    var textDigest: String? {
        guard items.count == 1, let item = items.first,
              item.keys.allSatisfy(Self.textFormats.contains) else { return nil }
        let plain = item[NSPasteboard.PasteboardType.string.rawValue]
        let url = item[NSPasteboard.PasteboardType.URL.rawValue]
        guard plain == nil || url == nil || plain == url,
              let data = plain ?? url, var text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let singleLine = text.dropLast(text.reversed().prefix(while: \.isWhitespace).count)
        if !singleLine.isEmpty && !singleLine.contains(where: \.isNewline) {
            text = String(singleLine)
        }
        let bytes = Data(text.precomposedStringWithCanonicalMapping.utf8)
        return "text:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static let textFormats = Set([NSPasteboard.PasteboardType.string, .URL, .html, .rtf].map(\.rawValue))

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
