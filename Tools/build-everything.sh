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
# **Two of the three stages also run what they built.** MdoroCore's suite needs nothing but
# swift, and MdoroMacTests needs nothing but a Mac — no simulator, no device, no LAN, no
# runner. Compiling those two and stopping there left proven, runnable checks unrun on the one
# machine that could run them. The iOS stage still only compiles: running it needs a simulator,
# which is a separate question with a separate answer.
#
# ⚠ **The MdoroMac stage launches MdoroMac.app**, because the app is the test host. Do not run
# this while using Mdoro on this Mac (docs/DEVELOPMENT.md says the same of the command it
# documents).
#
# **`build-for-testing`, not `build`.** The failure that prompted this was in a test file, and
# plain `build` would have walked straight past it.
#
# Every stage runs even if an earlier one fails, so one round trip says everything that is
# wrong rather than only the first thing. A compile error, a failing test and a suite that
# never ran are reported as three different things, because they are three different things.
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

# Strings, not arrays. macOS still ships bash 3.2 as /bin/bash, and before 4.4 an empty
# array read under `set -u` is an unbound variable -- so `${#failed[@]}` would have failed
# exactly when all three stages passed. Found by the reviewer, who could not run a 3.2 to
# prove it either; a string costs nothing and the question stops mattering.
not_compiled=""
tests_failed=""
never_ran=""

announce() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }

# Measured, not estimated. The last time the length of a step here was guessed at, the guess
# was five to ten minutes and the truth was under one; the way to stop guessing is to make the
# thing say how long it took. `date +%s` rather than bash's SECONDS so each stage is timed on
# its own.
took() {
    elapsed=$(( $(date +%s) - $1 ))
    printf '\n\033[1m--- %s: %dm%02ds ---\033[0m\n' "$2" "$(( elapsed / 60 ))" "$(( elapsed % 60 ))"
}

# **A green has to mean that tests ran.** xcodebuild prints TEST SUCCEEDED having run nothing
# at all: one wrong character in -only-testing: buys a success with a count of zero. That was
# measured on this project and is written up in docs/DEVELOPMENT.md, and CI reads the count
# back out of the result bundle on every run because of it. So does this.
#
# python3 rather than the jq CI uses: jq is not on a stock Mac, python3 arrives with the tools
# Xcode installs, and docs/DEVELOPMENT.md already reads this same bundle with python3 by hand.
#
# The count comes out on the first line and the failures after it, because xcodebuild's own
# output says that a test failed without saying why — not the expectation, not the file. The
# bundle has that text.
#
# A bundle that cannot be read, or a summary whose count is renamed or is not a number, prints
# nothing or prints zero. Both are failures here rather than something to shrug at: the caller
# reports them, and neither can be mistaken for a passing run.
test_summary() {
    xcrun xcresulttool get test-results summary --path "$1" --format json 2> /dev/null \
        | python3 -c '
import json, sys

try:
    summary = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(summary, dict):
    sys.exit(1)
count = summary.get("totalTestCount")
if isinstance(count, int):
    print(count)
else:
    # Read as zero, and fail, rather than guessing at another name for it. The scalars are
    # printed under the names the bundle itself uses, so a renamed field shows up as itself.
    print(0)
    print("--- no numeric totalTestCount in the summary; what it does have ---")
    for key, value in summary.items():
        if isinstance(value, (int, float, str)):
            print("%s: %s" % (key, value))
for failure in summary.get("testFailures") or []:
    print("--- %s (%s) ---" % (failure.get("testName", "?"), failure.get("targetName", "?")))
    print(failure.get("failureText", "no text"))
'
}

whole_run_started=$(date +%s)

announce "MdoroCore, and its tests"
stage_started=$(date +%s)
# The build is kept in front of the test rather than letting `swift test` do both. It is what
# separates "this does not compile" from "this compiles and a test is wrong", and once the
# build has been done the test run reuses it, so the stage is not paid for twice.
#
# No count is read back on this side. The hole the Mac stage guards against was opened by a
# selector -- one wrong character in -only-testing: and nothing runs -- and nothing is selected
# here. What is left is the test target vanishing from Package.swift, which is a line in a
# diff. Counting would mean parsing swift-testing's own output, whose exact wording nobody who
# writes this script can check from Linux, and a guess at it would fail a run that was fine.
if ! (cd Packages/MdoroCore && swift build --build-tests); then
    not_compiled="$not_compiled MdoroCore"
elif ! (cd Packages/MdoroCore && swift test); then
    tests_failed="$tests_failed MdoroCoreTests"
fi
took "$stage_started" "MdoroCore"

announce "MdoroMac, and MdoroMacTests"
echo "this launches MdoroMac.app as the test host"
stage_started=$(date +%s)
# -destination is never omitted: without it xcodebuild builds Debug-iphoneos and installs onto
# whatever iPhone is plugged in (CLAUDE.md).
#
# -only-testing: is here for a second reason. Both schemes' test actions still name UI test
# targets that do not exist -- `UITests` appears nowhere in project.pbxproj, and the blueprint
# ids resolve to nothing (POL-248). Whether xcodebuild refuses a dangling reference or ignores
# it is not recorded anywhere, and no runner has ever taken that path. Naming the suite keeps
# this command on the shape CI has proven, rather than finding out on the owner's Mac.
#
# CODE_SIGNING_ALLOWED=NO is what lets the tests run at all on a machine with no development
# team configured: without it the suite dies before the first test with an early unexpected
# exit while preparing to run tests -- reproduced twice, and written up in
# docs/DEVELOPMENT.md. The Keychain and the notification centre are reached through injected
# seams, so an unsigned host is enough.
#
# Two verbs rather than CI's single `xcodebuild test`. CI does not need to tell a compile error
# from a failing test -- a red is a red on a throwaway runner -- but this command exists to say
# what is wrong in one round trip, and those are different answers with different next steps.
# The arguments are identical between the two so that the second is certainly looking at what
# the first built.
#
# CI's steps carry `set -o pipefail` and these do not: pipefail rescues an exit status that a
# pipeline would otherwise throw away, and nothing here pipes xcodebuild into anything. The one
# pipeline in this script reads the result bundle, and a read that comes back empty is already
# reported as a failure of its own.
#
# -derivedDataPath, which the iOS stage below does not use, is what makes "identical arguments"
# true of the products as well: the run finds exactly the build. It also keeps this out of the
# DerivedData the owner's Xcode is using. It persists between runs, so it is cold the first
# time and warm after, until something clears /tmp.
mac_derived=/tmp/mdoro-build-everything
mac_result=$mac_derived/result.xcresult

if ! xcodebuild build-for-testing \
    -project "$project" \
    -scheme MdoroMac \
    -destination 'platform=macOS' \
    -only-testing:MdoroMacTests \
    -derivedDataPath "$mac_derived" \
    CODE_SIGNING_ALLOWED=NO; then
    not_compiled="$not_compiled MdoroMac"
else
    # xcodebuild stops with `Existing file at -resultBundlePath` rather than overwriting, and
    # then the count read afterwards is last run's (measured 2026-09-14, one wasted round trip).
    rm -rf "$mac_result"
    if xcodebuild test-without-building \
        -project "$project" \
        -scheme MdoroMac \
        -destination 'platform=macOS' \
        -only-testing:MdoroMacTests \
        -derivedDataPath "$mac_derived" \
        -resultBundlePath "$mac_result" \
        CODE_SIGNING_ALLOWED=NO; then
        xcodebuild_said=passed
    else
        xcodebuild_said=failed
    fi

    summary=$(test_summary "$mac_result")
    if [ -z "$summary" ]; then
        echo "the result bundle gave no answer, so nothing here says whether a test ran"
        echo "(xcrun xcresulttool, or python3, could not read $mac_result)"
        never_ran="$never_ran MdoroMacTests"
    else
        ran=$(printf '%s\n' "$summary" | sed -n 1p)
        case "$ran" in
            '' | *[!0-9]*) ran=0 ;;
        esac
        printf '%s\n' "$summary" | sed -n '2,$p'

        if [ "$ran" -eq 0 ]; then
            # Zero covers two different mishaps -- a success that ran nothing, and a run that
            # died before the first test, which is what an unlaunchable host looks like. Both
            # mean the same thing here, so both are said the same way.
            echo "no test ran at all — what xcodebuild printed says nothing about the code"
            never_ran="$never_ran MdoroMacTests"
        elif [ "$xcodebuild_said" = passed ]; then
            echo "MdoroMacTests: $ran ran, all passed"
        else
            echo "MdoroMacTests: $ran ran, and the failures are above"
            tests_failed="$tests_failed MdoroMacTests"
        fi
    fi
fi
took "$stage_started" "MdoroMac"

announce "MdoroiOS, MdoroiOSTests and MdoroWidget"
stage_started=$(date +%s)
# This one compiles and stops there. Running it needs a simulator, and whether that belongs in
# this command is a separate question with a separate answer.
#
# A generic simulator destination rather than a named device: this only has to compile, and
# naming a device makes the command break when that device is not installed.
#
# MdoroWidget is not named because it does not have to be: MdoroiOS depends on it and embeds
# it, and the scheme builds implicit dependencies.
#
# No CODE_SIGNING_ALLOWED=NO on this one. It is needed on the Mac side, where dropping it
# stops the run before a test begins (POL-157), but nothing in docs/DEVELOPMENT.md has ever
# passed it to an iOS build, and a flag no one here has tried does not belong in the command
# meant to be the safe one.
if ! xcodebuild build-for-testing \
    -project "$project" \
    -scheme MdoroiOS \
    -destination 'generic/platform=iOS Simulator' \
    -only-testing:MdoroiOSTests; then
    not_compiled="$not_compiled MdoroiOS"
fi
took "$stage_started" "MdoroiOS"

took "$whole_run_started" "all of it"
printf '\n'
if [ -z "$not_compiled$tests_failed$never_ran" ]; then
    echo "ok — every target compiles, and every test that can run here ran and passed"
    exit 0
fi
[ -z "$not_compiled" ] || echo "these did not compile:$not_compiled"
[ -z "$tests_failed" ] || echo "these compiled, and tests failed:$tests_failed"
[ -z "$never_ran" ] || echo "nothing proves a test ran here:$never_ran"
echo "the errors are above, under the heading for each"
exit 1
