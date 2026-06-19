#!/bin/zsh
# Stamp the App Store build number from the git commit count, in BOTH places Xcode
# / the bundle read it: CFBundleVersion (Info.plist) and CURRENT_PROJECT_VERSION
# (the Xcode project). App Store requires a unique, increasing build number per
# upload; commit count gives that automatically. Run before any release/archive.
set -e
cd "$(dirname "$0")/.."
PLIST="${1:-App/Info.plist}"
PBXPROJ="App/medit.xcodeproj/project.pbxproj"
BUILD=$(git rev-list --count HEAD)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"
# Update every CURRENT_PROJECT_VERSION = N; line in the pbxproj.
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9][0-9]*;/CURRENT_PROJECT_VERSION = $BUILD;/g" "$PBXPROJ"
echo "build number = $BUILD  (git commit count)"
echo "  CFBundleVersion        → $PLIST"
echo "  CURRENT_PROJECT_VERSION → $PBXPROJ"
