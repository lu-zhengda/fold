import Foundation

/// Where clipboard history is stored.
///
/// Production launches use Application Support. `--library-folder <directory>`
/// is a test-only override so a smoke check can read `History.plist` from a
/// temporary directory without touching the real library.
enum LibraryLocation {
    static func folder(arguments: [String], applicationSupport: URL) -> URL {
        overrideFolder(arguments: arguments) ?? applicationSupport.appendingPathComponent("Fold", isDirectory: true)
    }

    static func overrideFolder(arguments: [String]) -> URL? {
        guard let flag = arguments.firstIndex(of: "--library-folder") else { return nil }
        let valueIndex = arguments.index(after: flag)
        guard valueIndex < arguments.endIndex else { return nil }
        let value = arguments[valueIndex]
        guard !value.isEmpty, !value.hasPrefix("-") else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }
}
