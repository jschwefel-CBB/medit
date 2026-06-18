import AppKit
import MeditKit

// medit's entry point. The whole app lives in the MeditKit library; this thin
// target just boots an NSApplication with our delegate. We avoid @main /
// @NSApplicationMain attributes and drive the run loop manually so the app
// works identically whether launched from Xcode or the command line.

// Test hook: start from a clean preferences/state baseline when launched by
// autopilot (the GUI test driver). Must run before AppDelegate reads prefs and
// before AppKit restores any saved window. LaunchReset clears the sidebar root
// bookmarks, disables window restoration, and deletes the saved-state bundle so
// no previous document reopens — a plain domain wipe is not enough.
LaunchReset.perform(
    arguments: CommandLine.arguments,
    bundleID: Bundle.main.bundleIdentifier,
    appName: (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? "medit",
    defaults: .standard
)

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
