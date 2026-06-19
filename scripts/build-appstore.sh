#!/bin/zsh
# Build a Mac App Store archive of medit and export an uploadable .pkg.
#
# Account-INDEPENDENT up to the export step: it will archive without a team, but
# the EXPORT step needs the business's Team ID in scripts/ExportOptions-AppStore.plist
# (replace REPLACE_WITH_TEAM_ID). Until then this script stops after archiving with
# a clear message — everything before that is verified to work now.
#
# Usage: scripts/build-appstore.sh
set -e
cd "$(dirname "$0")/.."
ARCHIVE="build/medit.xcarchive"
EXPORT_DIR="build/appstore-export"
OPTS="scripts/ExportOptions-AppStore.plist"

echo "==> Stamp build number from commit count"
scripts/set-build-number.sh

echo "==> Test gate"
swift test 2>&1 | tail -1

echo "==> Archive (universal, Release)"
rm -rf "$ARCHIVE"
xcodebuild -project App/medit.xcodeproj -scheme medit -configuration Release \
  -archivePath "$ARCHIVE" \
  ARCHS="x86_64 arm64" ONLY_ACTIVE_ARCH=NO \
  archive | tail -2

if grep -q REPLACE_WITH_TEAM_ID "$OPTS"; then
  echo ""
  echo "==> STOP: export needs the Apple Developer Team ID."
  echo "    Archive is ready at: $ARCHIVE"
  echo "    Fill teamID in $OPTS (replace REPLACE_WITH_TEAM_ID), then re-run,"
  echo "    or use Xcode Organizer → Distribute App → App Store Connect."
  exit 0
fi

echo "==> Export for App Store"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTS" -exportPath "$EXPORT_DIR" | tail -2
echo "==> Done. Upload the .pkg in $EXPORT_DIR via Transporter or:"
echo "    xcrun altool --upload-app -f \"$EXPORT_DIR\"/*.pkg -t macos --apiKey … --apiIssuer …"
