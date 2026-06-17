import AppKit
import MeditKit

// medit's entry point. The whole app lives in the MeditKit library; this thin
// target just boots an NSApplication with our delegate. We avoid @main /
// @NSApplicationMain attributes and drive the run loop manually so the app
// works identically whether launched from Xcode or the command line.

// Test hook: start from a clean preferences/state baseline when launched by
// autopilot (the GUI test driver). Must run before AppDelegate reads prefs.
if CommandLine.arguments.contains("--reset-state") {
    if let domain = Bundle.main.bundleIdentifier {
        UserDefaults.standard.removePersistentDomain(forName: domain)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
