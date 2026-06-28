# Multi-File Open → Tabs (v2.7.1) Implementation Plan

**Goal:** Fix the v2.7.0 regression where opening multiple files at once (launch
args / Finder "Open With" / dragging multiple files onto the app icon) scatters
them into separate windows instead of tabs; add durable AutoPilot coverage for
every open permutation.

**Architecture:** Route `application(_:openFiles:)`'s document opens through the
front window's `EditorWindowController.openFiles(at:)` — the one open-into-tabs
implementation (explicit `addTabbedWindow`) — instead of N independent
`openDocument` calls that relied on the removed `.preferred` auto-merge. Keep
`tabbingMode = .automatic` so ⇧⌘N stays a separate window.

**Tech stack:** Swift 6 / AppKit, SwiftPM `MeditKit`, thin Xcode app target,
AutoPilot GUI tests.

## Global Constraints

- `tabbingMode` stays `.automatic` (⇧⌘N = separate window; everything else = tabs).
- Shipping (Release) build stays **sandboxed** (`App/medit.entitlements`). Only
  the **Debug** build is sandbox-off (`App/medit-debug.entitlements`), test-only.
- No unguarded debug output in source. Build numbers from git commit count.

---

## Task 1: Route `application(_:openFiles:)` through `openFiles(at:)` (the fix)

**Files:** `Sources/MeditKit/AppDelegate.swift`

- Collect non-directory paths into `[URL]`; directories still go to
  `openFolderInFrontWindow`.
- Add `openFilesAsTabsInFrontWindow(_:)`: ensure an untitled host window exists,
  grab the front `EditorWindowController`, call `controller.openFiles(at: urls)`.
- Add `scheduleLonePristineUntitledCleanup(retriesLeft:)`: once the opened files
  exist beside a lone pristine Untitled, close the Untitled; retry on the main
  runloop (open is async) until content appears or the budget runs out.
- Remove the now-unused `closePristineUntitledDocuments(excluding:)`.
- Guard the `--reset-state` deferred `closeAllRestoredDocuments()` with
  `!didOpenFilesAtLaunch` so it never closes files opened at launch.

**Verify:** `open-into-tabs-launch.json` → 1 `AXWindow`, N+1 tabs minus the
trimmed Untitled; Release build via `launchFiles` → 1 window, N tabs.

## Task 2: Test infra — sandbox-off Debug build

**Files:** `App/medit-debug.entitlements` (new), `App/medit.xcodeproj/project.pbxproj`

- New entitlements file with `com.apple.security.app-sandbox = false`.
- Point ONLY the Debug app build config's `CODE_SIGN_ENTITLEMENTS` at it; Release
  keeps `medit.entitlements`.

**Verify:** `codesign -d --entitlements -` shows sandbox false (Debug) / true
(Release).

## Task 3: Test infra — sidebar row identifiers + `--open-files` hook

**Files:** `Sources/MeditKit/SidebarViewController.swift`,
`Sources/MeditKit/LaunchReset.swift`, `Sources/MeditKit/AppDelegate.swift`,
`Tests/MeditKitTests/LaunchResetTests.swift`

- Outline cell text field gets `setAccessibilityIdentifier("sidebarRow:" +
  node.url.lastPathComponent)`.
- `LaunchReset.openFilesFlag = "--open-files"` + `requestedFilesToOpen(in:)`
  (collect paths until the next `--flag`, skip empties). Unit-tested.
- `AppDelegate.openLaunchFilesIfRequested()` opens them via the front window's
  `openFiles(at:)` ~1s after launch.

**Verify:** `testRequestedFilesToOpenParsing` passes; `open-into-tabs-runtime.json`
and `sidebar-open*.json` resolve rows and open files.

## Task 4: AutoPilot regression plans + fixtures

**Files:** `uitests/open-into-tabs-launch.json`, `open-into-tabs-runtime.json`,
`sidebar-open-file.json`, `sidebar-open-second-file.json`,
`uitests/fixtures/open-{a,b,c}.txt`, `uitests/fixtures/open-folder/*`,
`uitests/stage-fixtures.sh`, `uitests/README.md`

- Plans assert 1 `AXWindow` + correct contents for: multi-file launch, multi-file
  runtime, sidebar open, sidebar open-second.
- `stage-fixtures.sh` stages the new files + folder. README documents the
  sandbox-off Debug build, `sidebarRow:` ids, the `--open-files` hook, and the
  process gotcha (kill all instances between runs).

**Verify:** all five plans (incl. `multi-window.json`) pass on a clean sweep.

## Task 5: Version bump + docs

**Files:** `App/Info.plist` (2.7.1 + build number), `docs/autopilot-feedback.md`,
this plan, the design spec.

**Verify:** `swift test` green (387), full AP suite green, universal Release build
embeds 2.7.1.
