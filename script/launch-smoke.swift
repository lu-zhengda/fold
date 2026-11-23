// Run in a disposable macOS GUI session. Fold starts its normal clipboard monitor.
import AppKit
import Darwin

let url = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let configuration = NSWorkspace.OpenConfiguration()
configuration.createsNewApplicationInstance = true
configuration.activates = false
var finished = false
var launched: NSRunningApplication?
var launchError: Error?
NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
    launched = app
    launchError = error
    finished = true
}

func wait(seconds: TimeInterval, until predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return predicate()
}

guard wait(seconds: 30, until: { finished }), let app = launched,
      app.bundleURL?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() else {
    fatalError("Could not launch the requested Fold.app: \(String(describing: launchError))")
}
let ready = wait(seconds: 15) { app.isFinishedLaunching || app.isTerminated }
let passed = ready && !app.isTerminated && app.activationPolicy == .accessory
app.terminate()
if !wait(seconds: 5, until: { app.isTerminated }) {
    app.forceTerminate()
}
guard passed, wait(seconds: 5, until: { app.isTerminated }) else {
    fatalError("Fold did not complete a menu bar app launch and shutdown")
}
print("PASS launched and quit \(url.path)")
