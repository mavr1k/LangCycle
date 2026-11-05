#!/bin/bash
# Builds the files for a GitHub release and a Homebrew cask, in dist/:
#
#   dist/LangCycle-<version>.zip   the universal, ad-hoc signed app (attach this to the GitHub release)
#   dist/langcycle.rb              the Homebrew cask for that zip (copy to Casks/ in the mavr1k/homebrew-tap repo)
#
# <version> is CFBundleShortVersionString in Resources/Info.plist. Bump it there first for a new release.
#
# Normally GitHub Actions publishes a release: pushing the tag v<version> runs .github/workflows/release.yml,
# which runs this script, creates the GitHub release and updates the Homebrew cask.
#
# To publish by hand instead, after running this script:
#   1. git tag v<version> && git push origin v<version>   (this also starts the workflow; skip the tag to avoid that)
#   2. gh release create v<version> dist/LangCycle-<version>.zip --title "LangCycle <version>" --notes-file dist/release-notes.md
#      (write the notes with ./release-notes.sh v<version> > dist/release-notes.md)
#   3. cp dist/langcycle.rb <homebrew-tap checkout>/Casks/ and commit and push it there.
set -euo pipefail
cd "$(dirname "$0")"

REPO="mavr1k/LangCycle"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"

./build.sh --no-install
codesign --verify --deep --strict build/LangCycle.app

rm -rf dist
mkdir dist
zip="dist/LangCycle-$version.zip"
# --norsrc/--noextattr/--noqtn/--noacl: without them ditto stores macOS metadata as `._*` files, which plain
# `unzip` extracts into the bundle and which then break its code signature.
ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl build/LangCycle.app "$zip"
sha="$(shasum -a 256 "$zip" | awk '{print $1}')"

# Check the zip the way a user gets it: extracted with plain `unzip`, which is how stray `._*` files once
# broke the signature. Fails the script (and so the release workflow) if anything is wrong.
check="$(mktemp -d)"
trap 'rm -rf "$check"' EXIT
fail() { echo "error: $*" >&2; exit 1; }
unzip -q "$zip" -d "$check"
[[ "$(ls -A "$check")" == "LangCycle.app" ]] || fail "the zip should contain only LangCycle.app"
[[ -z "$(find "$check" -name '._*')" ]] || fail "the zip contains macOS metadata files (._*)"
codesign --verify --deep --strict "$check/LangCycle.app" || fail "the signature is broken after unzipping"
archs="$(lipo -archs "$check/LangCycle.app/Contents/MacOS/LangCycle")"
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || fail "the app is not universal (found: $archs)"
packaged="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$check/LangCycle.app/Contents/Info.plist")"
[[ "$packaged" == "$version" ]] || fail "the app says version $packaged, expected $version"
echo "Zip checked: only LangCycle.app, signature valid, $archs, version $packaged"

# The app is only ad-hoc signed (not notarized), so macOS quarantines it when downloaded.
# The cask clears that flag after installing, which avoids the "Apple could not verify…" warning.
cat > dist/langcycle.rb <<EOF
cask "langcycle" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/$REPO/releases/download/v#{version}/LangCycle-#{version}.zip"
  name "LangCycle"
  desc "Cycle keyboard layouts in a fixed order, with a large on-screen indicator"
  homepage "https://github.com/$REPO"

  depends_on macos: :ventura

  app "LangCycle.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args:         ["-dr", "com.apple.quarantine", "{{appdir}}/LangCycle.app"],
        must_succeed: false
  end

  zap trash: "~/Library/Preferences/com.local.langcycle.plist"
end
EOF

echo
echo "Release files for v$version:"
ls -lh dist
echo "sha256: $sha"
