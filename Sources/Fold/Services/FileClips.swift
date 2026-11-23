import AppKit

enum FileClips {
    private static let type = NSPasteboard.PasteboardType.fileURL.rawValue

    static func capture(_ urls: [URL]) -> Payload {
        var payload = Payload(items: urls.map { [type: Data($0.absoluteString.utf8)] })
        for (index, url) in urls.enumerated() {
            if let bookmark = bookmark(for: url, userSelected: false) { payload.saveBookmark(bookmark, at: index) }
        }
        return payload
    }

    private static func inPrivateUserFolder(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return ["Desktop", "Documents", "Downloads", "Library/Mobile Documents", "Library/CloudStorage"].contains {
            let folder = home.appendingPathComponent($0).path
            return path == folder || path.hasPrefix(folder + "/")
        }
    }

    private static func bookmark(for url: URL, userSelected: Bool) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard scoped || userSelected || !inPrivateUserFolder(url) else { return nil }
        return try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                     includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func restore(_ payload: inout Payload, to board: NSPasteboard,
                        authorize: (URL) -> URL?) throws {
        let staging = NSPasteboard.withUniqueName()
        defer { staging.releaseGlobally() }
        var urls: [URL] = []
        var activeScopes: [URL] = []
        defer { for url in activeScopes { url.stopAccessingSecurityScopedResource() } }

        for (index, item) in payload.items.enumerated() {
            guard let bytes = item[type], let original = URL(dataRepresentation: bytes, relativeTo: nil),
                  original.isFileURL else { throw CocoaError(.fileReadCorruptFile) }
            var stale = false
            let saved = payload.fileBookmarks?[index].flatMap {
                try? URL(resolvingBookmarkData: $0, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                         relativeTo: nil, bookmarkDataIsStale: &stale)
            }
            var url = saved ?? original
            let scoped = url.startAccessingSecurityScopedResource()
            if scoped { activeScopes.append(url) }
            var userSelected = false
            if try !canShare(url, on: staging) {
                guard let chosen = authorize(url) else { throw CocoaError(.userCancelled) }
                guard chosen.standardizedFileURL == url.standardizedFileURL else {
                    throw RestoreError("Select the original item “\(url.lastPathComponent)”.")
                }
                url = chosen
                if url.startAccessingSecurityScopedResource() { activeScopes.append(url) }
                guard try canShare(url, on: staging) else {
                    throw RestoreError("macOS couldn’t make “\(url.lastPathComponent)” available to Finder.")
                }
                userSelected = true
                stale = true
            }
            if stale, let data = bookmark(for: url, userSelected: userSelected) {
                payload.saveBookmark(data, at: index)
            }
            urls.append(url)
        }

        guard !urls.isEmpty, publish(urls, to: board) else {
            throw RestoreError("macOS couldn’t put the selected files on the clipboard.")
        }
    }

    private static func canShare(_ url: URL, on staging: NSPasteboard) throws -> Bool {
        let accessible = try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw CocoaError(.fileReadInvalidFileName) }
            var info = stat()
            guard stat(path, &info) == 0 else {
                switch errno {
                case EACCES, EPERM: return false
                case ENOENT, ENOTDIR:
                    throw RestoreError("The original file is unavailable. Locate it in Finder and copy it again.")
                default: throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
            return true
        }
        guard accessible else { return false }
        // Set the actual file URL immediately. writeObjects can accept a promised
        // representation before the pasteboard server tries to issue file access.
        staging.declareTypes([.fileURL], owner: nil)
        return staging.setData(url.dataRepresentation, forType: .fileURL)
            && staging.data(forType: .fileURL) == url.dataRepresentation
    }

    private static func publish(_ urls: [URL], to board: NSPasteboard) -> Bool {
        board.clearContents()
        guard board.writeObjects(urls.map { $0 as NSURL }),
              board.types?.contains(.fileURL) == true,
              let items = board.pasteboardItems, items.count == urls.count else { return false }
        // writeObjects can return true even when macOS drops a protected file URL.
        return zip(items, urls).allSatisfy { item, expected in
            guard let data = item.data(forType: .fileURL),
                  let received = URL(dataRepresentation: data, relativeTo: nil) else { return false }
            return received.standardizedFileURL == expected.standardizedFileURL
        }
    }

    private struct RestoreError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
