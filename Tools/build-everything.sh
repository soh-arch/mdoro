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
#
# **The run also counts the warnings, and says where they are** (POL-236). That row has sat
# here since 2026-09-12 carrying an inventory nobody could re-count: fourteen warnings in
# three files, read once off a CI log, and since then two of those files have changed. Nothing
# on this machine or any other said whether that was still true, and the numbers written into
# the row from a Linux session with no compiler turned out to be wrong. So this counts.
#
# ⚠ **It does not fail the run, and it does not fix anything.** Counting and fixing are two
# jobs; this is the first one, and the row says so.
#
# ⚠ **A warm build recompiles nothing and therefore warns about nothing.** A second run of
# this command reports zero and means it in a way a reader will misread. Each stage says
# whether it started cold, and the count says what to delete to make it cold again.
set -u

# Each compile is now teed to a log so the warnings can be counted out of it, and a pipeline's
# status is its last command's -- tee's -- which would turn every failed compile green. This is
# what stops that, and it is why the three `if ! xcodebuild` tests below still mean what they
# say. (CI does not need this: nothing there is piped, and a red is a red on a throwaway
# runner. Here the same line has to carry both the live output and the count.)
#
# It changes no decision already in this file: every other pipeline here is an assignment or a
# statement, and none of them is tested. Checked when this was added, because turning an option
# on globally is the kind of change that is right where it was aimed and wrong somewhere else.
set -o pipefail

cd "$(dirname "$0")/.." || exit 1

# Said plainly rather than reported as a compile failure: a missing tool is not a broken tree,
# and confusing the two is how a green or a red comes to mean nothing (POL-240).
#
# xcrun and python3 are on the list for exactly that reason, though neither compiles anything.
# They are what reads the number of tests back out of the result bundle, and without them a run
# that was fine is reported in the same words as a suite that never ran. Stopping here says
# which it is. (python3 can also be present and unable to start, which the Mac stage still has
# to report on its own; this catches the cheaper half.)
for tool in swift xcodebuild xcrun python3; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        echo "$tool is not here, so nothing was compiled."
        echo "This needs a Mac with Xcode. It is the one step the cloud cannot take (POL-243)."
        exit 2
    fi
done

project=./PomodoroMac/PomodoroMac.xcodeproj

# One directory per run, emptied on the way in: a log left over from last time would be counted
# as this time's. /tmp rather than the tree, because nothing here belongs in a diff.
logs=/tmp/mdoro-build-everything-logs
rm -rf "$logs"
mkdir -p "$logs" || exit 2

# **Warm or cold is part of the answer, not a detail.** The compiler emits a warning when it
# compiles the file, so a stage that recompiled nothing reports nothing wrong with code that is
# still exactly as wrong as it was. Asked before each stage runs, because running it is what
# makes it warm.
warmth() { [ -e "$1" ] && echo warm || echo cold; }
core_warmth=$(warmth Packages/MdoroCore/.build)

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
#
# The summary is written to a file rather than piped straight in, and what the read complained
# about is kept beside it, so that a failure to read can show what came back instead of only
# saying that nothing did. That is the debugging CI prints, and it is the debugging somebody
# needs on the one machine that can take the next step.
#
# $1 the bundle, $2 the file to write the summary to, $3 the file to keep the complaints in.
test_summary() {
    xcrun xcresulttool get test-results summary --path "$1" --format json > "$2" 2> "$3"
    python3 -c '
import json, sys

try:
    summary = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(summary, dict):
    sys.exit(1)

# JSON has one number type, so a count can arrive as 5 or as 5.0 and mean the same thing;
# reading only the first of those turns a sound run red. bool is a subclass of int in Python
# and is not a count: True would otherwise read as one test having run. NaN and infinity are
# accepted by this parser and survive neither comparison nor int(), so they are turned away
# here rather than further down.
count = summary.get("totalTestCount")
countable = not isinstance(count, bool) and isinstance(count, (int, float))
if countable:
    try:
        count = int(count)
    except (ValueError, OverflowError):
        countable = False

if countable:
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
' < "$2"
}

whole_run_started=$(date +%s)

announce "MdoroCore, and its tests"
stage_started=$(date +%s)
# The build is kept in front of the test rather than letting `swift test` do both. It is what
# separates "this does not compile" from "this compiles and a test is wrong", and once the
# build has been done the test run reuses it, so the stage is not paid for twice.
#
# A green has to mean something here too, and what it is read from is `swift test list`. The
# Mac stage's hole was opened by a selector -- one wrong character in -only-testing: and nothing
# runs -- and nothing is selected here. But a suite can empty out from the other end: the test
# target stays in Package.swift, in plain sight of any diff, while the tests inside it are
# deleted or commented out. `swift build --build-tests` still compiles, `swift test` then finds
# nothing to run and exits zero, and the stage goes green having proven nothing -- the same
# shape as the green that means nothing on the Mac stage above, which docs/DEVELOPMENT.md
# writes up.
#
# `swift test list`, not `swift test --list-tests`: the flag is deprecated and says so --
# "use 'swift test list' instead". Measured on the owner's Mac, 2026-09-15, as is everything in
# the next paragraph; none of it is inferred from here, where there is no swift to ask.
#
# What comes back is the build's own noise -- [1/1] Planning build, Building for debugging...,
# Build complete! -- and then one line per test:
#
#   MdoroCoreTests.ARefusalIsNotAReasonToDialAgainTests/anErrorThatIsNotARefusalStillReachesTheBanner()
#
# Module.Suite/name(). Every line of noise carries whitespace and no test line does, which is
# what the pattern leans on, together with the slash. It ends at `)` rather than at `()` on
# purpose: what a test whose name carries argument labels lists as has not been seen here, and
# a pattern too narrow for those would turn a sound run red, which is the worse of the two ways
# to be wrong. stderr is folded into stdout because which of the two the listing comes out on
# was not measured either; the pattern discards the extra noise along with the rest.
#
# **This narrows the hole. It does not close it.** What stays open:
#
#   - tests that are listed and never run. Every one of them .disabled, or every one skipped at
#     run time, and this stage counts them and goes green just the same. Listing and running are
#     two different questions and only the first is asked here.
#   - whether `swift test list` prints a .disabled test at all. Nobody has looked. If it leaves
#     them out, a wholly disabled suite lists as zero and is caught here; if it prints them, it
#     is not. Which of those is true is unknown, not decided.
#   - a test named in backticks. Swift takes an identifier with spaces in it that way, and a
#     test named so puts whitespace into its own line, slipping past a pattern built on noise
#     being the only thing that has any. There are none in Packages/MdoroCore/Tests today, and
#     the pattern is left as it is: such a test goes uncounted rather than miscounted, and one
#     ordinarily named test beside it keeps the count off zero.
#
# And once in the other direction, towards a red that is not earned: `swift test list` is a
# second process, so it can come back non-zero for a reason that has nothing to do with finding
# tests, after `swift test` has already passed. The whole of what it printed goes out under the
# heading below, which is what lets the next person tell that from a suite with nothing in it.
#
# The listing is only read when `swift test` came back clean. A suite that failed has already
# proven that a test ran, and that is the only thing the count is for.
if ! (cd Packages/MdoroCore && swift build --build-tests) 2>&1 | tee "$logs/MdoroCore.log"; then
    not_compiled="$not_compiled MdoroCore"
elif ! (cd Packages/MdoroCore && swift test); then
    tests_failed="$tests_failed MdoroCoreTests"
else
    core_listing=$( (cd Packages/MdoroCore && swift test list) 2>&1 )
    core_list_status=$?
    core_listed=$(printf '%s\n' "$core_listing" | grep -c '^[^[:space:]]*/[^[:space:]]*)$')
    case "$core_listed" in
        '' | *[!0-9]*) core_listed=0 ;;
    esac

    core_trouble=
    if [ "$core_list_status" -ne 0 ]; then
        core_trouble="swift test list exited $core_list_status, so nothing here says whether a test exists"
    elif [ "$core_listed" -eq 0 ]; then
        core_trouble="no test was listed at all — what swift test printed says nothing about the code"
    fi

    if [ -n "$core_trouble" ]; then
        # What came back is printed, not summarised. The read is the whole of the evidence, and
        # a red that does not show it leaves the next person with nowhere to start.
        echo "$core_trouble"
        echo "--- what the listing said ---"
        printf '%s\n' "$core_listing" | head -c 4000
        printf '\n'
        never_ran="$never_ran MdoroCoreTests"
    else
        # "listed", not "ran". The Mac stage's number comes from a result bundle and is a count
        # of tests that ran; this one is a count of tests that exist. They are not the same
        # fact and they do not get the same word.
        echo "MdoroCoreTests: $core_listed listed, and swift test passed"
    fi
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
# The build is teed to a log and the run is not, because only a compile emits warnings. `set -o
# pipefail` at the top is what keeps the teed line's status the compiler's rather than tee's;
# the result bundle is still read through a file, which is what keeps the complaints from that
# read.
#
# -derivedDataPath, which the iOS stage below does not use, is what makes "identical arguments"
# true of the products as well: the run finds exactly the build. It also keeps this out of the
# DerivedData the owner's Xcode is using. It persists between runs, so it is cold the first
# time and warm after, until something clears /tmp.
mac_derived=/tmp/mdoro-build-everything
mac_result=$mac_derived/result.xcresult
mac_summary=$mac_derived/summary.json
mac_read_complaints=$mac_derived/reading-the-summary.txt
mac_warmth=$(warmth "$mac_derived")

if ! xcodebuild build-for-testing \
    -project "$project" \
    -scheme MdoroMac \
    -destination 'platform=macOS' \
    -only-testing:MdoroMacTests \
    -derivedDataPath "$mac_derived" \
    CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$logs/MdoroMac.log"; then
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

    summary=$(test_summary "$mac_result" "$mac_summary" "$mac_read_complaints")
    if [ -z "$summary" ]; then
        echo "the result bundle gave no answer, so nothing here says whether a test ran"
        echo "($mac_result could not be read)"
        echo "--- what the read said ---"
        head -c 4000 "$mac_read_complaints" 2> /dev/null
        echo "--- what came back instead of a summary ---"
        head -c 4000 "$mac_summary" 2> /dev/null
        printf '\n'
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
    -only-testing:MdoroiOSTests 2>&1 | tee "$logs/MdoroiOS.log"; then
    not_compiled="$not_compiled MdoroiOS"
fi
took "$stage_started" "MdoroiOS"

# POL-236: the warnings, counted here rather than read off a log by hand once a month.
#
# ⚠ **The iOS stage's warmth cannot be asked.** It is the one stage with no -derivedDataPath,
# so it builds into whatever DerivedData the owner's Xcode is using, and whether that already
# held these objects is not this script's to know. Said as `unknown` rather than guessed at.
announce "warnings"
python3 - "$logs/MdoroCore.log:MdoroCore:$core_warmth" \
          "$logs/MdoroMac.log:MdoroMac:$mac_warmth" \
          "$logs/MdoroiOS.log:MdoroiOS:unknown" <<'COUNTING'
import os, re, sys

# A compiler diagnostic names a place: path, line, column. Everything else that says "warning"
# is kept apart rather than counted with it -- `xcodebuild: WARNING: Using the first of
# multiple matching destinations` is not a thing wrong with the code, and a number that mixes
# the two is the number this row already got wrong once.
located = re.compile(r"^(?P<path>\S.*?):(?P<line>\d+):(?P<col>\d+): warning: (?P<text>.*)$")
# Anchored at the start of the line, because the compiler echoes the offending source after
# each diagnostic, and a source line with the word in it would otherwise be counted as one.
elsewhere = re.compile(r"^(\S+: )?(warning|WARNING): ")

root = os.getcwd() + os.sep
total_occurrences = 0
total_distinct = 0

for argument in sys.argv[1:]:
    path, stage, warmth = argument.split(":", 2)
    print("")
    try:
        with open(path, errors="replace") as log:
            lines = log.read().splitlines()
    except OSError:
        # A stage whose log is missing is not a stage with no warnings, and the difference is
        # the whole point of this section.
        print("%s: no log, so nothing here says anything about its warnings" % stage)
        continue

    seen = []
    counts = {}
    others = []
    for line in lines:
        hit = located.match(line)
        if hit:
            place = hit.group("path")
            if place.startswith(root):
                place = place[len(root):]
            one = (place, int(hit.group("line")), int(hit.group("col")), hit.group("text"))
            counts[place] = counts.get(place, 0) + 1
            if one not in seen:
                seen.append(one)
        elif elsewhere.search(line) and line not in others:
            others.append(line.strip())

    occurrences = sum(counts.values())
    total_occurrences += occurrences
    total_distinct += len(seen)

    print("%s (%s build): %d occurrence(s), %d distinct, in %d file(s)"
          % (stage, warmth, occurrences, len(seen), len(counts)))

    # ⚠ Zero from a build that compiled nothing is not evidence, and it is the easiest number
    # here to misread. It says so on the line where it would be misread.
    if occurrences == 0 and warmth != "cold":
        print("  ⚠ this build was %s, so it may have compiled nothing. Zero proves nothing here."
              % warmth)
        print("  to ask again from cold: rm -rf Packages/MdoroCore/.build "
              "/tmp/mdoro-build-everything, and for the iOS stage, Xcode's own DerivedData")

    for place in sorted(counts, key=lambda k: (-counts[k], k)):
        print("  %-60s %d" % (place, counts[place]))
    for place, line, column, text in sorted(seen):
        print("    %s:%d:%d  %s" % (place, line, column, text))
    for line in others:
        print("  (not about the code) %s" % line[:200])

print("")
print("all stages: %d occurrence(s), %d distinct" % (total_occurrences, total_distinct))
print("counted, not fixed, and never a reason for this command to fail (POL-236)")
COUNTING

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
