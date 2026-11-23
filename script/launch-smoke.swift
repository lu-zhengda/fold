// Run in a disposable GUI session. Fold starts its normal clipboard monitor.
import AppKit
import Darwin

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL " + message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let path = args.first, args.count == 1 || args == [path, "--executable"] else {
    fail("usage: launch-smoke.swift /path/to/Fold.app [--executable]")
}
let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL

func wait(seconds: TimeInterval, until predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return predicate()
}

var launched: NSRunningApplication?
if args.count == 2 {
    // A hosted runner has no person to acknowledge a Finder first-open sheet.
    // Exercise the installed binary after the separate Gatekeeper assessment.
    let child = Process()
    child.executableURL = url.appendingPathComponent("Contents/MacOS/Fold")
    try child.run()
    let registered = wait(seconds: 30) {
        launched = NSRunningApplication(processIdentifier: child.processIdentifier)
        return launched?.bundleIdentifier == "local.fold.clipboard" || !child.isRunning
    }
    if !registered || launched?.bundleIdentifier != "local.fold.clipboard" {
        if child.isRunning { child.terminate() }
        fail("installed executable did not register as Fold")
    }
} else {
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.activates = false
    var finished = false
    var launchError: Error?
    NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
        launched = app
        launchError = error
        finished = true
    }
    guard wait(seconds: 45, until: { finished }) else { fail("Launch Services timed out for " + path) }
    if let launchError { fail(launchError.localizedDescription) }
}

guard let app = launched,
      app.bundleURL?.resolvingSymlinksInPath().path == url.resolvingSymlinksInPath().path else {
    fail("unexpected running bundle: " + (launched?.bundleURL?.path ?? "none"))
}
let ready = wait(seconds: 15) { app.isFinishedLaunching || app.isTerminated }
let passed = ready && !app.isTerminated && app.activationPolicy == .accessory
app.terminate()
if !wait(seconds: 5, until: { app.isTerminated }) {
    app.forceTerminate()
}
guard passed, wait(seconds: 5, until: { app.isTerminated }) else {
    fail("Fold did not complete a menu bar app launch and shutdown")
}
print("PASS launched and quit " + path)
