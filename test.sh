#!/bin/bash
# Runs the unit tests (Swift Testing). Extra arguments are passed to `swift test`.
#
# With only the Command Line Tools installed, SwiftPM does not find the Swift Testing macro
# plugin by itself ("plugin for module 'TestingMacros' not found"), so its folder is passed
# explicitly when it exists. With Xcode installed nothing extra is needed.
set -euo pipefail
cd "$(dirname "$0")"

args=()
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$plugins" ]]; then
  args=(-Xswiftc -plugin-path -Xswiftc "$plugins")
fi
swift test ${args[@]+"${args[@]}"} "$@"
