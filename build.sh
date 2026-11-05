#!/bin/bash
# Builds a universal (arm64 + x86_64) LangCycle.app, ad-hoc signs it and installs it to /Applications.
#
#   ./build.sh               build, install to /Applications and launch
#   ./build.sh --no-install  build only (result: build/LangCycle.app)
#
# A release build can set the version without editing Resources/Info.plist:
#   LANGCYCLE_VERSION=1.2.3 LANGCYCLE_BUILD=57 ./build.sh --no-install
#
# Needs only the Command Line Tools (xcode-select --install), not Xcode.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/LangCycle.app
binaries=()
for arch in arm64 x86_64; do
  # One architecture per build (a multi-arch SwiftPM build needs Xcode), each in its own
  # scratch folder so the second build does not overwrite the first one's product.
  opts=(-c release --triple "$arch-apple-macosx13.0" --scratch-path ".build/$arch")
  swift build "${opts[@]}"
  binaries+=("$(swift build "${opts[@]}" --show-bin-path)/LangCycle")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/LangCycle"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Stamp the release version into the built app only; the file in the repository is not touched.
if [[ -n "${LANGCYCLE_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $LANGCYCLE_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${LANGCYCLE_BUILD:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $LANGCYCLE_BUILD" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/LangCycle"))"

if [[ "${1:-}" != "--no-install" ]]; then
  # Stop a running copy (it has no unsaved state) and wait, or the new one would see it and quit.
  pkill -x LangCycle || true
  for _ in {1..50}; do pgrep -x LangCycle >/dev/null || break; sleep 0.1; done
  rm -rf /Applications/LangCycle.app
  ditto "$APP" /Applications/LangCycle.app
  open /Applications/LangCycle.app
  echo "Installed and launched /Applications/LangCycle.app"
fi
