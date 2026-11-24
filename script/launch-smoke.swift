// Run in a disposable GUI session. Fold starts its normal clipboard monitor.
import AppKit
import Darwin

private var shouldStop: sig_atomic_t = 0
private var signalSources: [DispatchSourceSignal] = []
private var launched: NSRunningApplication?
private var libraryDirectory: URL?

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL " + message + "\n").utf8))
    shutdown()
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
let usage = "usage: launch-smoke.swift /path/to/Fold.app [--executable] [--check-history [--library directory]] | --self-test"

func wait(seconds: TimeInterval, until predicate: () -> Bool, interruptible: Bool = true) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate() && Date() < deadline && !(interruptible && shouldStop != 0) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    if interruptible && shouldStop != 0 { return false }
    return predicate()
}

func installSignals() {
    // Ignore the defaults so DispatchSource can observe them. Installed after a
    // direct Process launch so the app does not inherit the ignored disposition.
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    for number in [SIGINT, SIGTERM] {
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { shouldStop = 1 }
        source.resume()
        signalSources.append(source)
    }
}

func pidFileURL() -> URL? {
    guard let path = ProcessInfo.processInfo.environment["FOLD_SMOKE_PIDFILE"], !path.isEmpty else { return nil }
    return URL(fileURLWithPath: path)
}

func recordPID(_ pid: pid_t) {
    guard let url = pidFileURL() else { return }
    try? Data("\(pid)\n".utf8).write(to: url, options: .atomic)
}

func forgetPID() {
    guard let url = pidFileURL() else { return }
    try? FileManager.default.removeItem(at: url)
}

func makeTemporaryLibrary() -> URL {
    var directory = NSTemporaryDirectory()
    if !directory.hasSuffix("/") { directory += "/" }
    var template = Array((directory + "fold-smoke.XXXXXX").utf8CString)
    guard mkdtemp(&template) != nil else {
        fail("could not create a temporary history directory")
    }
    return URL(fileURLWithPath: String(cString: template), isDirectory: true)
}

func shutdown() {
    if let app = launched, !app.isTerminated {
        app.terminate()
        _ = wait(seconds: 5, until: { app.isTerminated }, interruptible: false)
        if !app.isTerminated {
            app.forceTerminate()
            _ = wait(seconds: 5, until: { app.isTerminated }, interruptible: false)
        }
    }
    if launched?.isTerminated == true {
        forgetPID()
    }
    if let libraryDirectory {
        try? FileManager.default.removeItem(at: libraryDirectory)
        libraryDirectory = nil
    }
}

func formatPreviews(_ items: [String]) -> String {
    let quoted = items.map { item -> String in
        let escaped = item
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"" + escaped + "\""
    }
    return "[" + quoted.joined(separator: ", ") + "]"
}

func historyMismatch(actual: [String], expected: [String]) -> String? {
    if actual == expected { return nil }
    return "clipboard history mismatch: expected newest-first \(formatPreviews(expected)) but found \(formatPreviews(actual))"
}

func runCheckerSelfTest() {
    let expected = ["fold-smoke-alpha", "https://example.com/fold-smoke"]
    if historyMismatch(actual: expected, expected: expected) != nil {
        fail("history checker rejected a matching snapshot")
    }
    let missing = historyMismatch(actual: [expected[1]], expected: expected)
    guard let missing, missing.contains("fold-smoke-alpha"), missing.contains("mismatch") else {
        fail("history checker accepted a snapshot that omitted an item")
    }
    guard historyMismatch(actual: expected + [expected[0]], expected: expected) != nil else {
        fail("history checker accepted a duplicate entry")
    }
    guard historyMismatch(actual: Array(expected.reversed()), expected: expected) != nil else {
        fail("history checker accepted the wrong order")
    }
}

struct StoredClip: Decodable {
    let preview: String
}

struct StoredHistory: Decodable {
    let clips: [StoredClip]
}

enum HistoryRead {
    case missing
    case unreadable
    case previews([String])
}

func readHistory(_ library: URL) -> HistoryRead {
    let index = library.appendingPathComponent("History.plist")
    guard FileManager.default.fileExists(atPath: index.path) else { return .missing }
    guard let data = try? Data(contentsOf: index),
          let history = try? PropertyListDecoder().decode(StoredHistory.self, from: data) else { return .unreadable }
    return .previews(history.clips.map(\.preview))
}

func captureStatus(_ library: URL) -> String? {
    let url = library.appendingPathComponent("capture-status.txt")
    guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }
    let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty, !line.contains("/"), line.count < 80 else { return nil }
    return line
}

func requireHistory(library: URL, expected: [String], context: String) {
    var actual: [String] = []
    var unreadable = false
    let matched = wait(seconds: 15) {
        if shouldStop != 0 { return true }
        switch readHistory(library) {
        case .missing:
            actual = []
            unreadable = false
            return false
        case .unreadable:
            actual = []
            unreadable = true
            return false
        case .previews(let previews):
            actual = previews
            unreadable = false
            return previews == expected
        }
    }
    if shouldStop != 0 { fail("interrupted") }
    if matched { return }
    let status = captureStatus(library).map { " Capture status: \($0)." } ?? ""
    if unreadable {
        fail(context + ": clipboard history file was unreadable." + status)
    }
    let mismatch = historyMismatch(actual: actual, expected: expected) ?? "clipboard history mismatch"
    fail(context + ": " + mismatch + "." + status)
}

func copyToPasteboard(_ text: String) {
    let board = NSPasteboard.general
    board.clearContents()
    guard board.setString(text, forType: .string) else {
        fail("could not write the system pasteboard")
    }
}

func checkClipboardHistory(library: URL) {
    let plain = "fold-smoke-alpha"
    let link = "https://example.com/fold-smoke"
    let lines = "fold-smoke-line-1\nfold-smoke-line-2"
    copyToPasteboard(plain)
    requireHistory(library: library, expected: [plain], context: "after the first copy")
    copyToPasteboard(link)
    requireHistory(library: library, expected: [link, plain], context: "after the link copy")
    copyToPasteboard(lines)
    requireHistory(library: library, expected: [lines, link, plain], context: "after the multi-line copy")
    copyToPasteboard(plain)
    requireHistory(library: library, expected: [plain, lines, link], context: "after copying the first item again")
}

if args == ["--self-test"] {
    runCheckerSelfTest()
    print("PASS history checker flags a missing item")
    exit(0)
}

var executable = false
var checkHistory = false
var libraryArg: String?
var path: String?
var index = 0
while index < args.count {
    let arg = args[index]
    switch arg {
    case "--executable":
        executable = true
    case "--check-history":
        checkHistory = true
    case "--library":
        index += 1
        guard index < args.count, !args[index].hasPrefix("-") else { fail(usage) }
        libraryArg = args[index]
    default:
        if path == nil, !arg.hasPrefix("-") {
            path = arg
        } else {
            fail(usage)
        }
    }
    index += 1
}
guard let path else { fail(usage) }
if libraryArg != nil && !checkHistory { fail(usage) }

let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
if checkHistory {
    if let libraryArg {
        let directory = URL(fileURLWithPath: libraryArg, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fail("could not create a temporary history directory")
        }
        libraryDirectory = directory
    } else {
        libraryDirectory = makeTemporaryLibrary()
    }
}

let launchArguments = libraryDirectory.map { ["--library-folder", $0.path] } ?? []

if executable {
    // A hosted runner has no person to acknowledge a Finder first-open sheet.
    // Exercise the installed binary after the separate Gatekeeper assessment.
    let child = Process()
    child.executableURL = url.appendingPathComponent("Contents/MacOS/Fold")
    if !launchArguments.isEmpty { child.arguments = launchArguments }
    do {
        try child.run()
    } catch {
        fail("could not launch Fold")
    }
    installSignals()
    recordPID(child.processIdentifier)
    let registered = wait(seconds: 30) {
        launched = NSRunningApplication(processIdentifier: child.processIdentifier)
        return launched?.bundleIdentifier == "local.fold.clipboard" || !child.isRunning
    }
    if shouldStop != 0 { fail("interrupted") }
    if !registered || launched?.bundleIdentifier != "local.fold.clipboard" {
        if child.isRunning { child.terminate() }
        fail("installed executable did not register as Fold")
    }
} else {
    installSignals()
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.activates = false
    if !launchArguments.isEmpty { config.arguments = launchArguments }
    var finished = false
    var launchError: Error?
    NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
        launched = app
        launchError = error
        if let app { recordPID(app.processIdentifier) }
        finished = true
    }
    guard wait(seconds: 45, until: { finished }) else { fail("Launch Services timed out for " + path) }
    if shouldStop != 0 { fail("interrupted") }
    if let launchError { fail(launchError.localizedDescription) }
}

guard let app = launched,
      app.bundleURL?.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path else {
    fail("unexpected running bundle: " + (launched?.bundleURL?.path ?? "none"))
}
let ready = wait(seconds: 15) { app.isFinishedLaunching || app.isTerminated }
if shouldStop != 0 { fail("interrupted") }
let passed = ready && !app.isTerminated && app.activationPolicy == .accessory
if passed, checkHistory, let libraryDirectory {
    checkClipboardHistory(library: libraryDirectory)
}
app.terminate()
if !wait(seconds: 5, until: { app.isTerminated }) {
    app.forceTerminate()
}
guard passed, wait(seconds: 5, until: { app.isTerminated }) else {
    fail("Fold did not complete a menu bar app launch and shutdown")
}
forgetPID()
if let libraryDirectory {
    try? FileManager.default.removeItem(at: libraryDirectory)
    libraryDirectory = nil
}
print("PASS launched and quit " + path)
if checkHistory {
    print("PASS clipboard history captured 3 items newest-first and ignored a duplicate copy")
}
