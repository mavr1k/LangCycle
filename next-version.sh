#!/bin/bash
# Prints the version for the next automatic release.
#
#   ./next-version.sh <latest-tag> <info-plist-version>     e.g. ./next-version.sh v1.1 1.1   ->   1.1.1
#   ./next-version.sh --self-test
#
# - Normally the patch number of the latest tag goes up by one: v1.1 -> 1.1.1, v1.1.1 -> 1.1.2.
# - If the version in Resources/Info.plist is higher than the latest tag, exactly that version is released.
#   Raise it to start a new line (1.2, 2.0); patch numbers then count up from there.
# - With no tags yet, the Info.plist version is used.
set -euo pipefail

next_version() {
  local latest="${1#v}" plist="$2" major minor patch
  if [[ -z "$latest" ]]; then
    echo "$plist"
    return
  fi
  if [[ "$plist" != "$latest" && "$(printf '%s\n%s\n' "$latest" "$plist" | sort -V | tail -n 1)" == "$plist" ]]; then
    echo "$plist"
    return
  fi
  IFS=. read -r major minor patch <<< "$latest"
  echo "$major.${minor:-0}.$((10#${patch:-0} + 1))"
}

if [[ "${1:-}" == "--self-test" ]]; then
  failures=0
  check() { # latest-tag plist-version expected
    local got
    got="$(next_version "$1" "$2")"
    if [[ "$got" != "$3" ]]; then
      echo "FAIL next_version '$1' '$2': expected $3, got $got"
      failures=$((failures + 1))
    fi
  }
  check ""      1.1  1.1      # no tags yet
  check v1.1    1.1  1.1.1    # normal: patch bump
  check v1.1.1  1.1  1.1.2
  check v1.1.9  1.1  1.1.10   # counted as a number, not text
  check v1.1.1  1.2  1.2      # Info.plist raised: release exactly that
  check v1.2    1.2  1.2.1    # ... and then patch bumps resume
  check v1.9.3  1.10 1.10     # 1.10 is higher than 1.9.3
  check v1.10   1.9  1.10.1   # Info.plist behind the tag: ignored
  check v1.1    1.0  1.1.1
  check v2.0    1.9  2.0.1
  if ((failures > 0)); then exit 1; fi
  echo "next-version self-test: ok"
  exit 0
fi

next_version "${1:-}" "${2:?usage: next-version.sh <latest-tag> <info-plist-version>}"
