#!/usr/bin/env python3
"""What build-everything.sh must still decide when nobody is watching.

Two of that script's three stages now run what they build, and both of them read
a number back afterwards to find out whether anything really ran. Every judgment
around those two numbers fails the same way when it is wrong -- green, with
nothing having run -- which is the one outcome the script exists to make
impossible.

What these cases hold:

  - each stage names its own compile failure, and every stage runs even after an
    earlier one fails
  - a suite that failed is told apart from a suite that never ran, and the
    failure text from the bundle is printed
  - TEST SUCCEEDED with a count of zero is red
  - a bundle that cannot be read is red, and shows both what the read complained
    about and what came back instead
  - a count that is renamed, or is a bool, or is NaN, is red -- and a renamed one
    is printed under the name the bundle itself used
  - a count of 58.0 is 58, not a failure
  - on the MdoroCore side, a `swift test list` with no test in it is red, and so
    is a listing that will not come back at all; both print what did come back
  - the build's own noise is not counted as tests, and the count is called
    "listed" rather than "ran", because that is the fact it is
  - a missing swift, xcodebuild, xcrun or python3 stops everything at exit 2 and
    is not reported in the same words as broken code
  - a python3 that is present and will not run is not reported as a compile
    failure either
  - no xcodebuild call omits -destination; omitting it builds Debug-iphoneos and
    installs onto whatever iPhone is plugged in (docs/ORCHESTRATION.md §3)

What they cannot hold: nothing is compiled here and no test is run. swift,
xcodebuild and xcrun are stubs on PATH, every result bundle is text this file
wrote, and so is every listing. Whether the real arguments are right, whether
test-without-building finds what build-for-testing left in the same
-derivedDataPath, whether xcresulttool still calls the field totalTestCount, and
what `swift test list` actually prints are answerable only on a Mac with Xcode;
the owner's runs of 2026-09-15 answered all four once, and this file cannot
answer them again. It covers the reading and the reporting, and says so.

Nor can it hold what the script itself does not: a test that `swift test list`
prints and nothing ever runs -- disabled, or skipped at run time -- is counted
here exactly as the script counts it, because listing and running are different
questions and only the first is being asked.

The script's derived-data path is fixed at /tmp/mdoro-build-everything, so these
cases write there. They remove the two files they cause, and the directory
itself only if it was not already there -- a Mac keeps a warm build in it.

    python3 Tools/test-build-everything.py
"""
from __future__ import annotations
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "build-everything.sh"

# Fixed inside the script, which is why it is repeated rather than passed in.
DERIVED = Path("/tmp/mdoro-build-everything")

# PATH is cut down to one directory of our own so that a tool is absent exactly when a case
# wants it absent: there is no way to hide a real /usr/bin/python3 from `command -v` by adding
# to PATH, only by not having a PATH that reaches it. Everything the script and the stubs
# genuinely need is linked in beside them.
BORROWED = ("dirname", "date", "sed", "head", "rm", "mkdir", "cat", "grep", "tee")

A_PASSING_SUMMARY = {"title": "MdoroMac", "totalTestCount": 58, "passedTests": 58}
A_FAILING_SUMMARY = {
    "title": "MdoroMac",
    "totalTestCount": 58,
    "failedTests": 1,
    "testFailures": [
        {
            "testName": "aSeamHolds()",
            "targetName": "MdoroMacTests",
            "failureText": "expected the banner to carry the reason",
        }
    ],
}


def a_stub(body: str) -> str:
    return f"#!{shutil.which('bash')}\n" + body


# What the owner's Mac printed on 2026-09-15: the build's own noise first, then one line per
# test as Module.Suite/name(). The script has to find the second inside the first.
A_LISTING = """[1/1] Planning build
Building for debugging...
Build complete! (0.42s)
MdoroCoreTests.ARefusalIsNotAReasonToDialAgainTests/anErrorThatIsNotARefusalStillReachesTheBanner()
MdoroCoreTests.TheClockIsAbsoluteTests/aRemainderComesFromSessionEndAt()
MdoroCoreTests.TheClockIsAbsoluteTests/aMonotonicReadSurvivesASleep()
"""

# The same run with every test taken out of the suite: the target is still in Package.swift, so
# the build succeeds and `swift test` exits zero, and only this tells anyone the difference.
JUST_THE_BUILD_NOISE = """[1/1] Planning build
Building for debugging...
Build complete! (0.42s)
"""

# `$1 $2` rather than `$1`, because `swift test` and `swift test list` are two different
# questions and the stub has to be able to answer them differently.
SWIFT_STUB = a_stub(
    """
printf '%s\\n' "swift $*" >> "$STUB_LOG"
case "$1 ${2:-}" in
    'test list')
        printf '%s' "${STUB_SWIFT_LIST:-}"
        exit "${STUB_SWIFT_LIST_STATUS:-0}"
        ;;
esac
case "$1" in
    build) exit "${STUB_SWIFT_BUILD:-0}" ;;
    test) exit "${STUB_SWIFT_TEST:-0}" ;;
esac
exit 0
"""
)

# build-for-testing creates the -derivedDataPath the way the real one does, because the script
# writes the summary into that directory and a missing directory would fail the write for a
# reason no real run has.
XCODEBUILD_STUB = a_stub(
    """
printf '%s\\n' "xcodebuild $*" >> "$STUB_LOG"
verb=$1
scheme=
derived=
previous=
for argument in "$@"; do
    case "$previous" in
        -scheme) scheme=$argument ;;
        -derivedDataPath) derived=$argument ;;
    esac
    previous=$argument
done
[ -z "$derived" ] || mkdir -p "$derived"
if [ "$verb" = build-for-testing ]; then
    if [ "$scheme" = MdoroMac ]; then
        exit "${STUB_MAC_BUILD:-0}"
    fi
    exit "${STUB_IOS_BUILD:-0}"
fi
exit "${STUB_MAC_TEST:-0}"
"""
)

XCRUN_STUB = a_stub(
    """
printf '%s\\n' "xcrun $*" >> "$STUB_LOG"
[ -z "${STUB_XCRUN_STDERR:-}" ] || printf '%s\\n' "$STUB_XCRUN_STDERR" >&2
printf '%s' "${STUB_SUMMARY:-}"
exit "${STUB_XCRUN_STATUS:-0}"
"""
)

A_PYTHON3_THAT_WILL_NOT_RUN = a_stub(
    """
printf '%s\\n' "python3 $*" >> "$STUB_LOG"
printf 'dyld: Library not loaded\\n' >&2
exit 1
"""
)


class WithStubbedTools(unittest.TestCase):
    """Each case gets a tree of its own and a PATH of its own; this repository is never read."""

    def setUp(self) -> None:
        missing = [tool for tool in BORROWED if shutil.which(tool) is None]
        if missing or shutil.which("bash") is None:
            self.skipTest(f"not on this machine: {', '.join(missing) or 'bash'}")

        self.root = Path(tempfile.mkdtemp(prefix="mdoro-script-test-"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        (self.root / "Tools").mkdir()
        self.script = self.root / "Tools" / SCRIPT.name
        shutil.copy(SCRIPT, self.script)
        # The MdoroCore stage cd's here; without it the stage fails for a reason of our making.
        (self.root / "Packages" / "MdoroCore").mkdir(parents=True)

        self.bin = self.root / "bin"
        self.bin.mkdir()
        for tool in BORROWED:
            (self.bin / tool).symlink_to(shutil.which(tool))
        self.write_tool("swift", SWIFT_STUB)
        self.write_tool("xcodebuild", XCODEBUILD_STUB)
        self.write_tool("xcrun", XCRUN_STUB)
        # The interpreter running these cases, so CI's version matrix reaches the script's own
        # embedded python as well.
        (self.bin / "python3").symlink_to(sys.executable)

        self.log = self.root / "what-was-called.txt"
        self.derived_was_already_there = DERIVED.exists()
        self.addCleanup(self.leave_the_fixed_derived_path_as_found)

    def write_tool(self, name: str, body: str) -> None:
        tool = self.bin / name
        tool.write_text(body, encoding="utf-8")
        tool.chmod(0o755)

    def remove(self, tool: str) -> None:
        (self.bin / tool).unlink()

    def leave_the_fixed_derived_path_as_found(self) -> None:
        for name in ("summary.json", "reading-the-summary.txt"):
            with_suppressed_absence(DERIVED / name)
        if not self.derived_was_already_there:
            shutil.rmtree(DERIVED, ignore_errors=True)

    def run_script(
        self,
        summary: object = A_PASSING_SUMMARY,
        listing: str | None = A_LISTING,
        **knobs: str,
    ):
        environment = {
            "PATH": str(self.bin),
            "STUB_LOG": str(self.log),
            "HOME": str(self.root),
        }
        if summary is not None:
            environment["STUB_SUMMARY"] = json.dumps(summary)
        if listing is not None:
            environment["STUB_SWIFT_LIST"] = listing
        environment.update(knobs)
        return subprocess.run(
            [shutil.which("bash"), str(self.script)],
            capture_output=True,
            text=True,
            env=environment,
        )

    def what_was_called(self) -> str:
        return self.log.read_text(encoding="utf-8") if self.log.exists() else ""


def with_suppressed_absence(path: Path) -> None:
    try:
        path.unlink()
    except FileNotFoundError:
        pass


class WhenEverythingIsWell(WithStubbedTools):
    def test_it_says_that_something_ran(self) -> None:
        done = self.run_script()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("MdoroMacTests: 58 ran, all passed", done.stdout)
        self.assertIn("every test that can run here ran and passed", done.stdout)

    def test_a_count_that_arrives_as_a_float_is_still_a_count(self) -> None:
        # JSON has one number type: 58 and 58.0 mean the same thing, and reading only the first
        # of them turns a sound run red.
        done = self.run_script(summary={"totalTestCount": 58.0})
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("58 ran, all passed", done.stdout)

    def test_the_core_stage_says_how_many_it_listed(self) -> None:
        done = self.run_script()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("MdoroCoreTests: 3 listed, and swift test passed", done.stdout)

    def test_the_word_for_the_core_count_is_not_the_word_for_the_mac_count(self) -> None:
        # One number comes from a result bundle and counts tests that ran; the other comes from
        # a listing and counts tests that exist. Two facts, two words.
        done = self.run_script()
        self.assertIn("MdoroCoreTests: 3 listed", done.stdout)
        self.assertIn("MdoroMacTests: 58 ran", done.stdout)
        self.assertNotIn("MdoroCoreTests: 3 ran", done.stdout)

    def test_the_build_noise_is_not_counted_as_tests(self) -> None:
        # Planning build has a slash in it, Build complete! ends in a bracket, and a warning can
        # carry both. What tells them from a test line is that every one of them has whitespace.
        done = self.run_script(
            listing=(
                "[1/1] Planning build\n"
                "Building for debugging...\n"
                "warning: something was deprecated (use the other one)\n"
                "Build complete! (0.42s)\n"
                "MdoroCoreTests.OneSuite/oneTest()\n"
                "MdoroCoreTests.OneSuite/anotherTest()\n"
            )
        )
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("MdoroCoreTests: 2 listed, and swift test passed", done.stdout)

    def test_no_xcodebuild_call_omits_a_destination(self) -> None:
        self.run_script()
        calls = [line for line in self.what_was_called().splitlines() if line.startswith("xcodebuild")]
        self.assertEqual(len(calls), 3, self.what_was_called())
        for call in calls:
            self.assertIn("-destination", call)

    def test_the_ios_stage_compiles_and_stops_there(self) -> None:
        self.run_script()
        for line in self.what_was_called().splitlines():
            if "MdoroiOS" in line:
                self.assertIn("build-for-testing", line)


class WhenSomethingDoesNotCompile(WithStubbedTools):
    def test_the_core_stage_names_itself_and_does_not_run_its_tests(self) -> None:
        done = self.run_script(STUB_SWIFT_BUILD="1")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("these did not compile: MdoroCore", done.stdout)
        self.assertNotIn("swift test", self.what_was_called())

    def test_the_mac_stage_names_itself_and_does_not_run_its_tests(self) -> None:
        done = self.run_script(STUB_MAC_BUILD="65")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("these did not compile: MdoroMac", done.stdout)
        self.assertNotIn("test-without-building", self.what_was_called())

    def test_the_ios_stage_names_itself(self) -> None:
        done = self.run_script(STUB_IOS_BUILD="65")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("these did not compile: MdoroiOS", done.stdout)

    def test_one_round_trip_says_everything_that_is_wrong(self) -> None:
        # The stages do not stop at the first failure, so a single run is enough to know.
        done = self.run_script(STUB_SWIFT_BUILD="1", STUB_MAC_BUILD="65", STUB_IOS_BUILD="65")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("these did not compile: MdoroCore MdoroMac MdoroiOS", done.stdout)


class WhenTestsFail(WithStubbedTools):
    def test_a_failing_core_suite_is_not_a_compile_failure(self) -> None:
        done = self.run_script(STUB_SWIFT_TEST="1")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("these compiled, and tests failed: MdoroCoreTests", done.stdout)
        self.assertNotIn("these did not compile:", done.stdout)

    def test_a_failing_mac_suite_carries_the_text_from_the_bundle(self) -> None:
        # xcodebuild says a test failed without saying why; the bundle has the why.
        done = self.run_script(summary=A_FAILING_SUMMARY, STUB_MAC_TEST="65")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("MdoroMacTests: 58 ran, and the failures are above", done.stdout)
        self.assertIn("aSeamHolds()", done.stdout)
        self.assertIn("expected the banner to carry the reason", done.stdout)
        self.assertIn("these compiled, and tests failed: MdoroMacTests", done.stdout)

    def test_a_failing_core_suite_is_not_asked_how_many_it_listed(self) -> None:
        # A suite that failed has already proven that a test ran, which is the whole of what the
        # count is for; asking again would only add a second way for this stage to go wrong.
        done = self.run_script(STUB_SWIFT_TEST="1")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertNotIn("swift test list", self.what_was_called())
        self.assertNotIn("nothing proves a test ran here:", done.stdout)

    def test_both_suites_can_fail_in_one_run(self) -> None:
        done = self.run_script(summary=A_FAILING_SUMMARY, STUB_SWIFT_TEST="1", STUB_MAC_TEST="65")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("these compiled, and tests failed: MdoroCoreTests MdoroMacTests", done.stdout)


class WhenNothingRan(WithStubbedTools):
    """The green that means nothing, in each of the shapes it arrives in."""

    def test_a_count_of_zero_is_red_however_pleased_xcodebuild_sounds(self) -> None:
        done = self.run_script(summary={"totalTestCount": 0})
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("no test ran at all", done.stdout)
        self.assertIn("nothing proves a test ran here: MdoroMacTests", done.stdout)
        self.assertNotIn("all passed", done.stdout)

    def test_a_suite_emptied_out_from_the_inside_is_red(self) -> None:
        # The hole this stage was green through: the test target stays in Package.swift, the
        # tests inside it are gone, the build compiles and `swift test` exits zero.
        done = self.run_script(listing=JUST_THE_BUILD_NOISE)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("no test was listed at all", done.stdout)
        self.assertIn("nothing proves a test ran here: MdoroCoreTests", done.stdout)
        self.assertNotIn("listed, and swift test passed", done.stdout)
        # And what came back is shown, not just judged.
        self.assertIn("--- what the listing said ---", done.stdout)
        self.assertIn("Build complete!", done.stdout)

    def test_a_listing_that_will_not_come_back_is_red(self) -> None:
        # Failing open here would be the same green with an extra step in front of it.
        done = self.run_script(
            listing="error: no test target named MdoroCoreTests",
            STUB_SWIFT_LIST_STATUS="1",
        )
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("swift test list exited 1", done.stdout)
        self.assertIn("nothing proves a test ran here: MdoroCoreTests", done.stdout)
        self.assertIn("--- what the listing said ---", done.stdout)
        self.assertIn("no test target named MdoroCoreTests", done.stdout)

    def test_a_listing_that_fails_with_nothing_to_say_still_shows_its_nothing(self) -> None:
        # The heading is printed either way, so an empty read is told from an unread one.
        done = self.run_script(listing="", STUB_SWIFT_LIST_STATUS="1")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("swift test list exited 1", done.stdout)
        self.assertIn("--- what the listing said ---", done.stdout)
        self.assertIn("nothing proves a test ran here: MdoroCoreTests", done.stdout)

    def test_both_stages_can_have_nothing_to_show_in_one_run(self) -> None:
        done = self.run_script(listing=JUST_THE_BUILD_NOISE, summary={"totalTestCount": 0})
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("nothing proves a test ran here: MdoroCoreTests MdoroMacTests", done.stdout)

    def test_an_unreadable_bundle_shows_both_halves_of_what_happened(self) -> None:
        done = self.run_script(
            summary=None,
            STUB_SUMMARY="xcresulttool: not a bundle",
            STUB_XCRUN_STDERR="Error: unable to open /tmp/mdoro-build-everything/result.xcresult",
            STUB_XCRUN_STATUS="1",
        )
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("the result bundle gave no answer", done.stdout)
        self.assertIn("unable to open", done.stdout)
        self.assertIn("xcresulttool: not a bundle", done.stdout)
        self.assertIn("nothing proves a test ran here: MdoroMacTests", done.stdout)

    def test_a_renamed_count_is_printed_under_the_name_the_bundle_used(self) -> None:
        done = self.run_script(summary={"totalTests": 58, "title": "MdoroMac"})
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("no numeric totalTestCount", done.stdout)
        self.assertIn("totalTests: 58", done.stdout)
        self.assertIn("nothing proves a test ran here: MdoroMacTests", done.stdout)

    def test_a_count_that_is_true_is_not_one_test(self) -> None:
        # bool is a subclass of int in Python, so True reads as 1 unless it is turned away first.
        done = self.run_script(summary={"totalTestCount": True})
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("nothing proves a test ran here: MdoroMacTests", done.stdout)

    def test_a_count_that_is_not_a_number_at_all(self) -> None:
        # Each of these has to say what it saw, not only that it saw nothing countable: the red
        # is the same red every time, and the field as the bundle wrote it is the only thing
        # that tells one of these apart from the next. NaN and infinity survive json.load and
        # then survive neither comparison nor int(), which is why they are here beside a count
        # that is a string and a count that is absent.
        for count, diagnosis in (
            ("NaN", "totalTestCount: nan"),
            ("Infinity", "totalTestCount: inf"),
            ('"58"', "totalTestCount: 58"),
            ("null", "title: MdoroMac"),
        ):
            with self.subTest(count=count):
                done = self.run_script(
                    summary=None,
                    STUB_SUMMARY='{"totalTestCount": %s, "title": "MdoroMac"}' % count,
                )
                self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
                self.assertIn("nothing proves a test ran here: MdoroMacTests", done.stdout)
                self.assertIn("no numeric totalTestCount", done.stdout)
                self.assertIn(diagnosis, done.stdout)

    def test_a_summary_that_is_not_an_object(self) -> None:
        done = self.run_script(summary=None, STUB_SUMMARY="[58]")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("the result bundle gave no answer", done.stdout)


class WhenTheToolsAreNotThere(WithStubbedTools):
    """A missing tool is not a broken tree, and the two must not read alike."""

    def test_each_tool_stops_the_run_before_anything_is_attempted(self) -> None:
        for tool in ("swift", "xcodebuild", "xcrun", "python3"):
            with self.subTest(tool=tool):
                self.remove(tool)
                done = self.run_script()
                self.write_tool_back(tool)
                self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
                self.assertIn(f"{tool} is not here, so nothing was compiled.", done.stdout)
                self.assertNotIn("did not compile:", done.stdout)
                self.assertEqual(self.what_was_called(), "")

    def write_tool_back(self, tool: str) -> None:
        if tool == "swift":
            self.write_tool("swift", SWIFT_STUB)
        elif tool == "xcodebuild":
            self.write_tool("xcodebuild", XCODEBUILD_STUB)
        elif tool == "xcrun":
            self.write_tool("xcrun", XCRUN_STUB)
        else:
            (self.bin / "python3").symlink_to(sys.executable)

    def test_a_python3_that_will_not_start_is_not_a_compile_failure(self) -> None:
        # The half the check at the top cannot catch: present, found, and unable to run.
        self.remove("python3")
        self.write_tool("python3", A_PYTHON3_THAT_WILL_NOT_RUN)
        done = self.run_script()
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("the result bundle gave no answer", done.stdout)
        self.assertIn("nothing proves a test ran here: MdoroMacTests", done.stdout)
        self.assertNotIn("did not compile:", done.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
