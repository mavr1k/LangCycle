#!/bin/bash
# Prints the GitHub release notes for a tag: the commit subjects since the previous tag
# ("Bump version" commits left out), then install instructions and a changelog link.
#
#   ./release-notes.sh v1.1 > dist/release-notes.md
#
# The release workflow runs this; the notes can still be edited on GitHub afterwards.
set -euo pipefail
cd "$(dirname "$0")"

REPO="mavr1k/LangCycle"
tag="${1:?usage: release-notes.sh <tag>, e.g. v1.1}"
version="${tag#v}"
previous="$(git describe --tags --abbrev=0 "$tag^" 2>/dev/null || true)"

echo "## What's new"
echo
git log --no-merges --pretty='- %s' "${previous:+$previous..}$tag" | grep -vE '^- Bump version' || true
echo

sed "s/{{VERSION}}/$version/g" <<'EOF'
## Install or update

- Homebrew: `brew install --cask mavr1k/tap/langcycle` (or `brew upgrade --cask langcycle` if you already have it).
- Or download `LangCycle-{{VERSION}}.zip` below, unzip it and drag `LangCycle.app` to `/Applications`.

The app is ad-hoc signed, not notarized, so a downloaded copy needs a one-time **Open Anyway** in System Settings → Privacy & Security (the Homebrew install does this for you). See the [README](https://github.com/mavr1k/LangCycle#install) for details, and turn off the macOS ⌃Space input-source shortcut on first run.

Universal build (Apple Silicon and Intel), macOS 13 or later.
EOF

if [[ -n "$previous" ]]; then
  echo
  echo "**Full Changelog**: https://github.com/$REPO/compare/$previous...$tag"
fi
