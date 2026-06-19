#!/bin/zsh
# Pre-flight checks for a Mac App Store build — everything verifiable WITHOUT a
# developer account. Catches common rejection causes before you ever upload.
# Builds a Release .app and inspects it. Exit 0 = all green.
set -e
cd "$(dirname "$0")/.."
fail=0
ok()   { print "  ✅ $1" }
bad()  { print "  ❌ $1"; fail=1 }

print "==> Building Release app to inspect…"
xcodebuild -project App/medit.xcodeproj -scheme medit -configuration Release \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build >/dev/null 2>&1 || { print "build failed"; exit 1 }
APP="/Volumes/Scratch/Xcode/DerivedData/Release/medit.app"
[[ -d "$APP" ]] || APP="$(find ~/Library/Developer/Xcode/DerivedData -name medit.app -path '*Release*' 2>/dev/null | head -1)"
[[ -d "$APP" ]] || { print "  ❌ couldn't locate built medit.app"; exit 1 }
PLIST="$APP/Contents/Info.plist"
print "    inspecting: $APP\n"

print "Info.plist keys:"
for k in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion \
         LSApplicationCategoryType LSMinimumSystemVersion NSHumanReadableCopyright \
         ITSAppUsesNonExemptEncryption NSPrincipalClass; do
  v=$(/usr/libexec/PlistBuddy -c "Print $k" "$PLIST" 2>/dev/null) && ok "$k = $v" || bad "$k MISSING"
done

print "\nSandbox / signing:"
ENT=$(codesign -d --entitlements - "$APP" 2>/dev/null)
print "$ENT" | grep -q "app-sandbox" && ok "App Sandbox entitlement present" || bad "NOT sandboxed (App Store requires it)"
print "$ENT" | grep -qi "temporary-exception" && bad "uses a temporary-exception entitlement (review scrutiny)" || ok "no temporary-exception entitlements"
codesign -dv "$APP" 2>&1 | grep -q "flags=.*runtime" && ok "Hardened Runtime on" || print "  ⚠️  Hardened Runtime flag not seen (set at distribution signing)"

print "\nForbidden / sandbox-incompatible APIs in source:"
if grep -rEn "NSTask|Process\(\)|\bsystem\(|popen\(|\bfork\(\)" Sources/MeditKit/*.swift | grep -v "//" >/dev/null; then
  bad "found a process-spawning API (not allowed in sandbox)"
else ok "no process-spawning APIs"; fi
if grep -rEn "performSelector|NSClassFromString|_private" Sources/MeditKit/*.swift | grep -v "//" >/dev/null; then
  bad "possible private-API usage — review"
else ok "no obvious private-API usage"; fi

print "\nArchitectures:"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/medit" 2>/dev/null)
[[ "$ARCHS" == *arm64* ]] && ok "arm64 present ($ARCHS)" || bad "arm64 missing"

print ""
if (( fail )); then print "PREFLIGHT: ❌ issues above"; exit 1; else print "PREFLIGHT: ✅ all green"; fi
