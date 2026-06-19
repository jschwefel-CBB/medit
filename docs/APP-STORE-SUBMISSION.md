# medit — Mac App Store Submission Checklist

Status of everything needed to ship medit on the Mac App Store. Items are grouped
by whether they can be done **without** an Apple Developer account (pre-tackled
here) vs. **blocked** on the account / business setup.

medit is unusually well-prepared: the App Sandbox + security-scoped-bookmark
foundation (the part that usually requires the most rework) is already correct.

---

## ✅ Done (no account required)

- **App Sandbox enabled** — `App/medit.entitlements`:
  `com.apple.security.app-sandbox` + `com.apple.security.files.user-selected.read-write`.
  Minimal entitlements; no temporary-exception entitlements (which draw review
  scrutiny).
- **Security-scoped bookmarks** for sidebar roots — resolve with `.withSecurityScope`,
  `startAccessingSecurityScopedResource`, stale-refresh, re-persist
  (`SidebarViewController`). This is the sandbox-correct way to remember folder
  access across launches.
- **Hardened Runtime** — `ENABLE_HARDENED_RUNTIME = YES` in the project.
- **No sandbox-incompatible APIs** — no `NSTask`/`Process`/`system()`/`fork`/
  `popen`, no private APIs, no `performSelector` tricks. Pure AppKit + public
  frameworks. Printing uses public `NSPrintOperation`.
- **No network, accounts, or analytics** — nothing to declare beyond "no data
  collected" on the privacy nutrition label.
- **`LSApplicationCategoryType`** = `public.app-category.developer-tools` (Info.plist).
- **`ITSAppUsesNonExemptEncryption`** = `false` (Info.plist) — pre-answers the
  export-compliance question so uploads aren't gated on it.
- **`NSHumanReadableCopyright`** set (Info.plist).
- **Versioning** — `CFBundleShortVersionString` = the marketing version (2.4.x);
  build number auto-stamped from the git commit count by
  `scripts/set-build-number.sh` (updates both `CFBundleVersion` and
  `CURRENT_PROJECT_VERSION`). Run it before any release/archive build so each
  upload gets a unique, increasing build number.
- **Licenses** — top-level `LICENSE` (MIT) + `THIRD-PARTY-LICENSES.md` (HighlighterSwift
  MIT, highlight.js BSD-3, swift-markdown Apache-2.0). All App-Store-compatible.
- **Screenshots** — 16 captured in `docs/images/` (see `docs/images/README.md`);
  App Store listing screenshots can be derived from these.
- **Universal build** — builds `x86_64 arm64`.
- **Document types / UTIs** — `CFBundleDocumentTypes` + `LSItemContentTypes`
  declared (plain text, source, Markdown).

---

## ⛔ Blocked on the Apple Developer account / business setup

These need the paid Apple Developer Program membership (under the business) and an
App Store Connect record. Do them once the account is live:

1. **Developer Team / signing**
   - Set `DEVELOPMENT_TEAM` (the business's Team ID) in the project.
   - Switch signing from ad-hoc to **App Store** distribution (`CODE_SIGN_STYLE`
     is already `Automatic` — it will pick up the team).
   - Confirm the app signs with a **3rd Party Mac Developer Application** /
     distribution certificate for upload.
2. **App Store Connect record**
   - Create the app with bundle ID **`com.jschwefel.medit`** (decided; permanent
     once submitted).
   - **Decision to confirm:** the app ships under the business but the bundle ID +
     copyright currently name the individual. Decide whether the **copyright /
     seller name** should be the business (LLC) even though the bundle ID stays
     `com.jschwefel.*`. If so, update `NSHumanReadableCopyright` accordingly.
   - Register the bundle ID as an **App ID** with the App Sandbox capability.
3. **Provisioning** — a Mac App Store provisioning profile (auto-managed via
   `Automatic` signing once the team is set).
4. **Archive & upload** — `xcodebuild archive` → `xcodebuild -exportArchive` with
   an App Store export options plist, then upload via Xcode Organizer or
   `xcrun altool`/`notarytool`-equivalent (`xcrun altool --upload-app` /
   Transporter). Notarization is **not** needed for App Store (that's for direct
   distribution); App Store has its own review.
5. **App Store metadata** (App Store Connect web UI)
   - Name, subtitle, description, keywords, support URL, marketing URL.
   - **Privacy nutrition label:** "Data Not Collected."
   - **Screenshots** at required resolutions (derive from `docs/images/`).
   - Category: Developer Tools (matches `LSApplicationCategoryType`).
   - Age rating (4+), pricing (free or paid — TBD).
6. **Export compliance** — already pre-answered via `ITSAppUsesNonExemptEncryption
   = false`; confirm in App Store Connect at submission.

---

## Pre-submission verification (run before each upload)

```sh
# 1. Stamp the build number from commit count
scripts/set-build-number.sh

# 2. Full test gate
swift test

# 3. Archive for App Store (once a team is set)
xcodebuild -project App/medit.xcodeproj -scheme medit -configuration Release \
  -archivePath build/medit.xcarchive archive

# 4. Validate the archive against App Store rules (catches most rejections early)
#    (via Xcode Organizer “Validate App”, or xcodebuild -exportArchive then altool)
```

### Things review commonly flags — already handled
- ❌ *Uses a private API* — none.
- ❌ *Not sandboxed* — sandboxed.
- ❌ *Requests broad file access without justification* — only user-selected R/W.
- ❌ *Crashes on launch / no functionality* — 350+ tests; ships working.
- ❌ *Missing privacy policy for data collection* — collects no data.

---

## Open decisions for you

- **Copyright / seller identity** — business (LLC) vs. individual (see #2 above).
- **Pricing** — free vs. paid.
- **App Store name** — "medit" may be taken; have a fallback (e.g. "medit — Text
  Editor"). Check availability in App Store Connect when reserving.
