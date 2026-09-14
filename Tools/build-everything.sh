#!/usr/bin/env bash
# POL-243: nothing compiles the Swift before it reaches the owner's Mac.
#
# Everyone who writes Swift here reads it and no more: the orchestrator, the implementer and
# the reviewer all run on Linux, with no Swift, no Xcode and no macOS. CI is the only machine
# that compiles anything, and it compiles two thirds of the tree — never MdoroiOS, never its
# tests, never MdoroWidget. This is the one command that covers all of it, and it belongs to
# whoever has the Mac.
#
#   Tools/build-everything.sh
#
# It compiles. It does not run tests: that launches MdoroMac.app and is a slower, different
# thing (docs/DEVELOPMENT.md has those commands).
#
# **`build-for-testing`, not `build`.** The failure that prompted this was in a test file, and
# plain `build` would have walked straight past it.
#
# Every stage runs even if an earlier one fails, so one round trip says everything that is
# wrong rather than only the first thing.
set -u

cd "$(dirname "$0")/.." || exit 1

# Said plainly rather than reported as a compile failure: a missing tool is not a broken tree,
# and confusing the two is how a green or a red comes to mean nothing (POL-240).
for tool in swift xcodebuild; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        echo "$tool is not here, so nothing was compiled."
        echo "This needs a Mac with Xcode. It is the one step the cloud cannot take (POL-243)."
        exit 2
    fi
done

project=./PomodoroMac/PomodoroMac.xcodeproj
failed=()

announce() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }

announce "MdoroCore, and its tests"
if ! (cd Packages/MdoroCore && swift build --build-tests); then
    failed+=("MdoroCore")
fi

announce "MdoroMac, and MdoroMacTests"
# -destination is never omitted: without it xcodebuild builds Debug-iphoneos and installs onto
# whatever iPhone is plugged in (CLAUDE.md).
if ! xcodebuild build-for-testing \
    -project "$project" \
    -scheme MdoroMac \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO; then
    failed+=("MdoroMac")
fi

announce "MdoroiOS, MdoroiOSTests and MdoroWidget"
# A generic simulator destination rather than a named device: this only has to compile, and
# naming a device makes the command break when that device is not installed.
if ! xcodebuild build-for-testing \
    -project "$project" \
    -scheme MdoroiOS \
    -destination 'generic/platform=iOS Simulator' \
    CODE_SIGNING_ALLOWED=NO; then
    failed+=("MdoroiOS")
fi

printf '\n'
if [ ${#failed[@]} -eq 0 ]; then
    echo "ok — every target compiles, tests included"
    exit 0
fi
echo "these did not compile: ${failed[*]}"
echo "the errors are above, under the heading for each"
exit 1
