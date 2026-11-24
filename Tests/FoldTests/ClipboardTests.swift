import XCTest
import AppKit
@testable import Fold

private struct SmokeHistoryClip: Decodable {
    let preview: String
}

private struct SmokeHistoryFile: Decodable {
    let clips: [SmokeHistoryClip]
}

final class ClipboardTests: XCTestCase {
    private func withPasteboard(_ test: (NSPasteboard) throws -> Void) rethrows {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try test(board)
    }

    private func fileFixtures() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Project folder"), withIntermediateDirectories: true)
        for name in ["one.txt", "two.txt", "Brief #1.pdf"] {
            try Data("test".utf8).write(to: folder.appendingPathComponent(name))
        }
        return folder
    }

    func testRichTextAndFileReferencesRoundTrip() throws {
        try withPasteboard { board in
            let payload = Payload(items: [
                ["public.utf8-plain-text": Data("hello".utf8), "public.rtf": Data("{\\rtf1 hello}".utf8)]
            ])
            XCTAssertTrue(Clipboard.write(payload, to: board))
            let copy = try XCTUnwrap(Clipboard.read(board))
            XCTAssertEqual(copy.items, payload.items)
            let folder = try fileFixtures()
            defer { try? FileManager.default.removeItem(at: folder) }
            let files = Payload(items: ["one.txt", "two.txt"].map { ["public.file-url": Data(folder.appendingPathComponent($0).absoluteString.utf8)] })
            XCTAssertTrue(Clipboard.write(files, to: board))
            let restored = try XCTUnwrap(Clipboard.read(board))
            XCTAssertEqual(restored.items, files.items)
            let card = Clipboard.describe(restored, source: "Finder", digest: restored.digest)
            XCTAssertEqual(card.kind, .files)
            XCTAssertEqual(card.preview, "one.txt\ntwo.txt")
        }
    }

    func testOldFinderClipWithFilenameFallbackRestoresOnlyFiles() throws {
        try withPasteboard { board in
            let folder = try fileFixtures()
            defer { try? FileManager.default.removeItem(at: folder) }
            let urls = [folder.appendingPathComponent("Project folder", isDirectory: true),
                        folder.appendingPathComponent("Brief #1.pdf")]
            let oldClip = Payload(items: urls.map { url in
                ["public.utf8-plain-text": Data(url.lastPathComponent.utf8),
                 "public.file-url": Data(url.absoluteString.utf8)]
            })
            XCTAssertTrue(Clipboard.write(oldClip, to: board))
            let native = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            XCTAssertEqual(native, urls)
            XCTAssertTrue(try XCTUnwrap(board.pasteboardItems).allSatisfy { !$0.types.contains(.string) })
            XCTAssertEqual(try XCTUnwrap(Clipboard.read(board)).items,
                           urls.map { ["public.file-url": Data($0.absoluteString.utf8)] })
        }
    }

    func testLegacyFolderInAnAccessibleProjectRestoresWithoutPicker() throws {
        // Exercise the checkout's real location, including a checkout under Documents.
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let reference = try XCTUnwrap((folder as NSURL).fileReferenceURL())
        var clip = Payload(items: [["public.file-url": reference.dataRepresentation]])
        try withPasteboard { board in
            try FileClips.restore(&clip, to: board) { _ in
                XCTFail("Fold requested permission for a folder it can already share")
                return nil
            }
            let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            XCTAssertEqual(urls?.map { ($0 as NSURL).filePathURL?.standardizedFileURL.path }, [folder.standardizedFileURL.path])
        }
    }

    func testPersistedFileGrantRestoresAndMissingFilePreservesClipboard() throws {
        let folder = try fileFixtures()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("one.txt")
        let captured = FileClips.capture([url])
        XCTAssertNotNil(captured.fileBookmarks?[0])
        let libraryFolder = folder.appendingPathComponent("Library")
        let library = try Library(folder: libraryFolder)
        try library.record(captured, source: "Finder")
        let id = try XCTUnwrap(library.history.clips.first?.id)
        var persisted = try Library(folder: libraryFolder).payload(for: id)
        XCTAssertEqual(persisted.fileBookmarks, captured.fileBookmarks)
        try withPasteboard { board in
            try FileClips.restore(&persisted, to: board) { _ in XCTFail("Unexpected access request"); return nil }
            let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            XCTAssertEqual(urls?.map { $0.standardizedFileURL.path }, [url.standardizedFileURL.path])
            try FileManager.default.removeItem(at: url)
            board.clearContents()
            board.setString("previous clipboard", forType: .string)
            XCTAssertFalse(Clipboard.write(persisted, to: board))
            XCTAssertEqual(board.string(forType: .string), "previous clipboard")
        }
    }

    func testDeniedFolderRequestsAccessAndCancellationPreservesClipboard() throws {
        let parent = try fileFixtures()
        let folder = parent.appendingPathComponent("Project folder", isDirectory: true)
        var clip = Payload(items: [["public.file-url": folder.dataRepresentation]])
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            try? FileManager.default.removeItem(at: parent)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: parent.path)
        try XCTSkipIf(getuid() == 0, "Root can traverse the test directory regardless of its mode.")
        withPasteboard { board in
            board.setString("previous clipboard", forType: .string)
            var requests: [URL] = []
            do {
                try FileClips.restore(&clip, to: board) { requests.append($0); return nil }
                XCTFail("Expected cancellation")
            } catch {
                XCTAssertEqual((error as? CocoaError)?.code, .userCancelled)
            }
            XCTAssertEqual(requests, [folder])
            XCTAssertEqual(board.string(forType: .string), "previous clipboard")
        }
    }

    func testImagePreviewAndRestoration() throws {
        try withPasteboard { board in
            let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aK6kAAAAASUVORK5CYII="))
            let payload = Payload(items: [["public.png": png]])
            XCTAssertTrue(Clipboard.write(payload, to: board))
            let saved = try XCTUnwrap(Clipboard.read(board))
            XCTAssertEqual(saved.items, payload.items)
            let clip = Clipboard.describe(saved, source: "Preview", digest: saved.digest)
            XCTAssertEqual(clip.kind, .image)
            XCTAssertNotNil(clip.thumbnail)
            XCTAssertEqual(clip.detail, "1 × 1")
        }
    }

    func testConcealedContentAndOversizeItemsAreSkipped() {
        withPasteboard { board in
            let secret = NSPasteboardItem()
            secret.setString("private", forType: .string)
            secret.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
            board.writeObjects([secret])
            XCTAssertNil(Clipboard.read(board))
            XCTAssertTrue(Clipboard.write(Payload(items: [["public.png": Data(count: Clipboard.byteLimit + 1)]]), to: board))
            XCTAssertNil(Clipboard.read(board))
        }
    }

    func testNewestFirstOrderAndDuplicateMovesExistingEntry() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Library(folder: folder)
        func payload(_ text: String) -> Payload {
            Payload(items: [["public.utf8-plain-text": Data(text.utf8)]])
        }
        let plain = "fold-smoke-alpha"
        let link = "https://example.com/fold-smoke"
        let lines = "fold-smoke-line-1\nfold-smoke-line-2"
        try library.record(payload(plain), source: "Test")
        try library.record(payload(link), source: "Test")
        try library.record(payload(lines), source: "Test")
        XCTAssertEqual(library.history.clips.map(\.preview), [lines, link, plain])
        try library.record(payload(plain), source: "Test")
        XCTAssertEqual(library.history.clips.count, 3)
        XCTAssertEqual(library.history.clips.map(\.preview), [plain, lines, link])
        let index = try Data(contentsOf: folder.appendingPathComponent("History.plist"))
        let stored = try PropertyListDecoder().decode(SmokeHistoryFile.self, from: index)
        XCTAssertEqual(stored.clips.map(\.preview), [plain, lines, link])
    }

    func testPersistenceDeduplicationSearchAndRemoval() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try Library(folder: folder)
        let payload = Payload(items: [["public.utf8-plain-text": Data("https://example.com/fold".utf8)]])
        try first.record(payload, source: "Safari")
        let id = try XCTUnwrap(first.history.clips.first?.id)
        try first.update {
            $0.clips[0].boards.insert(Board.favorites.id)
            $0.clips[0].rename(to: "  Team invite  ")
        }
        try first.record(payload, source: "Notes")
        let reopened = try Library(folder: folder)
        XCTAssertEqual(reopened.history.clips.count, 1)
        let saved = try XCTUnwrap(reopened.history.clips.first)
        XCTAssertEqual(saved.id, id)
        XCTAssertEqual(saved.boards, [Board.favorites.id])
        XCTAssertEqual(saved.kind, .link)
        XCTAssertEqual(saved.listTitle, "Team invite")
        XCTAssertTrue(saved.matches("INVITE"))
        XCTAssertTrue(saved.matches("EXAMPLE"))
        XCTAssertTrue(saved.matches("Notes"))
        XCTAssertEqual(try reopened.payload(for: id).items, payload.items)
        try reopened.update { $0.clips[0].rename(to: "  ") }
        let reset = try XCTUnwrap(try Library(folder: folder).history.clips.first)
        XCTAssertNil(reset.customName)
        XCTAssertEqual(reset.listTitle, "example.com")
        XCTAssertFalse(reset.matches("invite"))
        try reopened.update { $0.clips.removeAll() }
        XCTAssertTrue(try Library(folder: folder).history.clips.isEmpty)
        XCTAssertThrowsError(try reopened.payload(for: id))
    }

    func testRecopyWithDifferentFormatsRestoresLatestPayload() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = try Library(folder: folder)
        let plain = Payload(items: [["public.utf8-plain-text": Data("Team invite".utf8)]])
        let styled = Payload(items: [["public.utf8-plain-text": Data("Team invite \n".utf8),
                                      "public.html": Data("<b>Team invite</b>".utf8)]])
        try library.record(plain, source: "Notes")
        let id = try XCTUnwrap(library.history.clips.first?.id)
        try library.update {
            $0.clips[0].boards.insert(Board.favorites.id)
            $0.clips[0].rename(to: "Invite")
        }
        try library.record(Payload(items: [["public.utf8-plain-text": Data("Different".utf8)]]), source: "Notes")
        try withPasteboard { board in
            XCTAssertTrue(Clipboard.write(styled, to: board))
            try library.record(XCTUnwrap(Clipboard.read(board)), source: "Browser", sourceBundleID: "test.browser")
            let reopened = try Library(folder: folder)
            XCTAssertEqual(reopened.history.clips.count, 2)
            let newest = try XCTUnwrap(reopened.history.clips.first)
            XCTAssertEqual(newest.id, id)
            XCTAssertEqual(newest.boards, [Board.favorites.id])
            XCTAssertEqual(newest.customName, "Invite")
            XCTAssertEqual(newest.sourceBundleID, "test.browser")
            XCTAssertEqual(newest.preview, "Team invite \n")
            XCTAssertEqual(newest.size, styled.size)
            XCTAssertTrue(try Clipboard.write(reopened.payload(for: id), to: board))
            XCTAssertEqual(Clipboard.read(board)?.items, styled.items)
        }
    }

    func testLegacyDuplicatesMergeOnOpen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        let board = Board(id: UUID(), name: "Work")
        var history = History()
        history.boards.append(board)
        for text in ["Hello", "Unrelated", "Hello\n"] {
            let payload = Payload(items: [["public.utf8-plain-text": Data(text.utf8)]])
            let clip = Clipboard.describe(payload, source: "Browser", digest: payload.digest)
            history.clips.append(clip)
            try encoder.encode(payload).write(to: folder.appendingPathComponent(clip.id.uuidString + ".clip"))
        }
        history.clips[0].boards = [board.id]
        history.clips[2].boards = [Board.favorites.id]
        history.clips[2].rename(to: "Greeting")
        try encoder.encode(history).write(to: folder.appendingPathComponent("History.plist"))
        for _ in 0..<2 {
            let library = try Library(folder: folder)
            XCTAssertEqual(library.history.clips.map(\.id), Array(history.clips.prefix(2)).map(\.id))
            let kept = try XCTUnwrap(library.history.clips.first)
            XCTAssertEqual(kept.customName, "Greeting")
            XCTAssertEqual(kept.boards, [board.id, Board.favorites.id])
            XCTAssertEqual(try library.payload(for: kept.id).items.first?["public.utf8-plain-text"], Data("Hello".utf8))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".clip") }.count, 2)
        }
    }

    func testTextMatchingUsesFullContentAndRespectsOtherPasteboardItems() {
        let type = NSPasteboard.PasteboardType.string.rawValue
        func key(_ string: String) -> String? { Payload(items: [[type: Data(string.utf8)]]).textDigest }
        let prefix = String(repeating: "a", count: 32_768)
        XCTAssertNotEqual(key(prefix + "1"), key(prefix + "2"))
        XCTAssertEqual(key("one\r\ntwo"), key("one\ntwo"))
        XCTAssertNotEqual(key("one\n  two"), key("one\ntwo"))
        XCTAssertNotEqual(key(" One"), key("One"))
        let text = Data("example".utf8)
        XCTAssertNil(Payload(items: [[type: text], [type: text]]).textDigest)
        for format in ["public.url", "public.file-url", "public.png", "com.apple.flat-rtfd"] {
            XCTAssertNil(Payload(items: [[type: text, format: Data("different".utf8)]]).textDigest)
        }
    }

    func testPinnedClipsSurviveRetentionLimit() {
        let payload = Payload(items: [["public.utf8-plain-text": Data("hello".utf8)]])
        var sample = Clipboard.describe(payload, source: "Notes", digest: "sample")
        var history = History()
        history.clips = Array(repeating: sample, count: 501)
        sample.boards.insert(Board.favorites.id)
        history.clips.append(sample)
        Library.trim(&history)
        XCTAssertEqual(history.clips.count, 501)
        XCTAssertEqual(history.clips.last?.boards, [Board.favorites.id])
    }
}
