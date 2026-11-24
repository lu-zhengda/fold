import XCTest
@testable import Fold

final class LibraryLocationTests: XCTestCase {
    func testMissingOverrideUsesApplicationSupport() {
        let support = URL(fileURLWithPath: "/fixture/fold-support", isDirectory: true)
        let folder = LibraryLocation.folder(arguments: ["Fold"], applicationSupport: support)
        XCTAssertNil(LibraryLocation.overrideFolder(arguments: ["Fold"]))
        XCTAssertEqual(folder.lastPathComponent, "Fold")
        XCTAssertEqual(folder.deletingLastPathComponent().path, support.path)
    }

    func testLibraryFolderArgumentOverridesTheDefault() {
        let arguments = ["Fold", "--library-folder", "/fixture/fold-history"]
        let support = URL(fileURLWithPath: "/fixture/fold-support", isDirectory: true)
        let folder = LibraryLocation.folder(arguments: arguments, applicationSupport: support)
        XCTAssertEqual(folder.path, "/fixture/fold-history")
    }

    func testIncompleteLibraryFolderArgumentIsIgnored() {
        XCTAssertNil(LibraryLocation.overrideFolder(arguments: ["Fold", "--library-folder"]))
        XCTAssertNil(LibraryLocation.overrideFolder(arguments: ["Fold", "--library-folder", "--other"]))
    }
}
