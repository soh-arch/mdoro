#!/usr/bin/env python3
'''What check-only-words-moved.py must still notice when nobody is watching.

The sweep it serves is sound by construction: the role only meant to touch
comments, so a run that had stopped reading would print the same ok line as one
that works. That is exactly what happened on #132, where a stripper raised
SyntaxError, every file came back empty, and fifteen empty strings hashed alike
-- fifteen SAMEs, indistinguishable from success, with nothing read.

So the cases here come in three kinds, and the middle one is the one that gets
forgotten:

  - changes the tool must catch,
  - changes it must let through -- a check that fails on sound input gets
    overridden, and an overridden check has stopped being a check,
  - and the tool itself broken, which must end in a problem and never in green.

Each case builds a real repository: a bare one to be origin, a work clone beside
it, a real Swift file committed and pushed, and a working tree that differs from
it by one deliberate edit. Nothing is stubbed and no network is used -- origin is
a path on disk -- so what comes back is the tool's answer to the question it is
asked, not a rehearsal of it. Each case gets its own temp directory and copies
the tool into it, so nothing here reads or touches this repository.

The Swift specimen below is written to hold the shapes Swift actually has and
that the sweeps actually touched: a nested block comment, a multiline string
whose closing delimiter sets its indentation, a raw string carrying bare quotes
and a \\#( ) interpolation, an ordinary interpolation, a numeric literal, a
@Suite name that is prose. Several cases assert the literal count the tool
prints, because that single number is what falls over when any one of those
shapes is misread -- a lexer that ends the block comment at the inner */ finds
one literal too many, and one that stops the raw string at its first inner quote
finds a different number again.

    python3 Tools/test-check-only-words-moved.py
'''
from __future__ import annotations
import importlib.util
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "check-only-words-moved.py"
WHERE = "Packages/MdoroCore/Tests/MdoroCoreTests/ANoticeTests.swift"

# Seven literals: the @Suite name, "Task.md", "/tmp/Task.md", "Task.md is read only",
# "the file \(name) was not read", the multiline sample, and the raw string.
LITERALS = 7

SWIFT = r'''import Testing

// REQ-ABC-001: the reader is told which file went wrong, and told it once.
/* A block comment /* that nests */ and then says "so" before it closes. */
@Suite("A notice names the file it is about (REQ-ABC-001)")
struct ANoticeTests {
    let attempts = 3

    @Test func itNamesTheFile() {
        let name = "Task.md"
        let path = "/tmp/Task.md"
        #expect(describe(name) == "Task.md is read only")
        Issue.record("the file \(name) was not read")
        let sample = """
            heading
              indented body
            """
        let raw = #"a "quoted" word, and \#(path) after it"#
        _ = (sample, raw, attempts)
    }
}
'''


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True, text=True)


class AgainstARealRepository(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="mdoro-words-test-"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)

        self.origin = self.root / "origin.git"
        subprocess.run(
            ["git", "init", "--bare", "-q", "-b", "main", str(self.origin)],
            check=True,
            capture_output=True,
        )

        self.repo = self.root / "work"
        self.repo.mkdir()
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "test")
        git(self.repo, "remote", "add", "origin", str(self.origin))
        (self.repo / "Tools").mkdir()
        shutil.copy(TOOL, self.repo / "Tools" / TOOL.name)
        self.commit(WHERE, SWIFT)

    # --- building a history ---------------------------------------------------
    def commit(self, path: str, text: str) -> None:
        """Put a file on origin/main. This is what --base will be compared against."""
        here = self.repo / path
        here.parent.mkdir(parents=True, exist_ok=True)
        here.write_text(text, encoding="utf-8")
        git(self.repo, "add", path)
        git(self.repo, "commit", "-qm", f"add {path}")
        git(self.repo, "push", "-q", "origin", "main")

    def now_reads(self, text: str, path: str = WHERE) -> None:
        """Change the working tree and nothing else: the state a sweep is checked in."""
        (self.repo / path).write_text(text, encoding="utf-8")

    def instead_of(self, was: str, now: str) -> None:
        """One deliberate edit to the specimen, asserted to have landed somewhere."""
        self.assertIn(was, SWIFT, "the case is editing something the specimen does not contain")
        self.now_reads(SWIFT.replace(was, now))

    def run_tool(self, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(self.repo / "Tools" / TOOL.name), *args],
            cwd=cwd or self.repo,
            capture_output=True,
            text=True,
        )

    # --- what the two answers look like ---------------------------------------
    def caught(self, *args: str) -> str:
        done = self.run_tool(*args)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("problem(s):", done.stdout)
        self.assertNotIn("ok —", done.stdout)
        return done.stdout

    def let_through(self, *args: str) -> str:
        done = self.run_tool(*args)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("ok — 1 file(s) compared against origin/main", done.stdout)
        return done.stdout


class WhatMustBeCaught(AgainstARealRepository):
    """Every one of these is asked of --words-only, the looser of the two modes.

    Catching them under --comments-only proves less, since that mode refuses almost
    every edit. The claim worth testing is that the loose mode is still a check.
    """

    def test_an_identifier_renamed(self) -> None:
        self.instead_of("let attempts = 3", "let tries = 3")
        said = self.caught("--words-only", WHERE)
        self.assertIn("attempts", said)
        self.assertIn("tries", said)

    def test_an_assertion_turned_around(self) -> None:
        # The change a reader is least likely to see in a diff of a comment sweep, and the
        # one that quietly deletes a test's meaning while it goes on passing.
        self.instead_of("describe(name) ==", "describe(name) !=")
        self.assertIn("!=", self.caught("--words-only", WHERE))

    def test_what_an_interpolation_interpolates(self) -> None:
        # Inside a literal, so the prose around it is free to move -- the expression is not.
        self.instead_of(r"the file \(name) was not read", r"the file \(path) was not read")
        said = self.caught("--words-only", WHERE)
        self.assertIn("name  ->  path", said)

    def test_an_interpolation_in_a_raw_string(self) -> None:
        # Same again behind # delimiters, where the escape marker is \# and a bare quote is
        # just a quote. A lexer that handles only \( reads this literal's prose as code.
        self.instead_of(r"and \#(path) after it", r"and \#(name) after it")
        self.caught("--words-only", WHERE)

    def test_a_number(self) -> None:
        self.instead_of("let attempts = 3", "let attempts = 4")
        self.assertIn("4", self.caught("--words-only", WHERE))

    def test_one_literal_split_into_two(self) -> None:
        # The prose is unchanged when read aloud, which is exactly why counting literals
        # has to be part of the answer rather than comparing what they say.
        self.instead_of(
            '#expect(describe(name) == "Task.md is read only")',
            '#expect(describe(name) == "Task.md " + "is read only")',
        )
        said = self.caught("--words-only", WHERE)
        self.assertIn(f"{LITERALS + 1} literal(s)", said)

    def test_a_line_of_code_deleted_outright(self) -> None:
        self.instead_of('        let path = "/tmp/Task.md"\n', "")
        self.caught("--words-only", WHERE)


class WhatMustBeLetThrough(AgainstARealRepository):
    def test_words_only_lets_the_prose_of_a_literal_move(self) -> None:
        self.instead_of('"Task.md is read only"', '"Task.md is opened read-only"')
        said = self.let_through("--words-only", WHERE)
        self.assertIn(f"{LITERALS} literal(s)", said)

    def test_words_only_lets_a_suite_name_move(self) -> None:
        # #133's shape: the name is prose to a reader and a string literal to the compiler.
        self.instead_of(
            '@Suite("A notice names the file it is about (REQ-ABC-001)")',
            '@Suite("A notice says which file it is about (REQ-ABC-001)")',
        )
        self.let_through("--words-only", WHERE)

    def test_words_only_lets_a_comment_move(self) -> None:
        self.instead_of("told it once.", "told it once, in English.")
        self.let_through("--words-only", WHERE)

    def test_comments_only_lets_a_comment_move(self) -> None:
        self.instead_of("told it once.", "told it once, in English.")
        self.let_through("--comments-only", WHERE)

    def test_either_mode_lets_a_comment_be_deleted_from_the_middle_of_a_line(self) -> None:
        # Removing an inline comment takes the whitespace around it with it. A check that
        # called that a code change would fire on the sweeps it exists to clear, so code
        # whitespace is normalised -- stated here as a case rather than left to be found.
        self.instead_of("/* A block comment /* that nests */ and then says \"so\" before it closes. */\n", "")
        self.let_through("--comments-only", WHERE)
        self.let_through("--words-only", WHERE)

    def test_reindenting_code_is_not_a_word_that_moved(self) -> None:
        self.instead_of("    let attempts = 3", "        let attempts   =   3")
        self.let_through("--comments-only", WHERE)


class WhereTheTwoModesPartCompany(AgainstARealRepository):
    """If both modes answered alike, naming one in a pull request would say nothing."""

    def test_comments_only_catches_what_words_only_forgives_in_a_literal(self) -> None:
        self.instead_of('"Task.md is read only"', '"Task.md is opened read-only"')
        self.let_through("--words-only", WHERE)
        self.assertIn("Task.md is", self.caught("--comments-only", WHERE))

    def test_comments_only_catches_a_multiline_literal_reindented(self) -> None:
        # Swift strips from every line of a multiline literal as much indentation as its
        # closing delimiter has, so moving that delimiter changes the value without
        # touching a visible character of it. #133 moved one of these. Under --words-only
        # the whole body is prose and may move; under --comments-only it may not.
        self.instead_of(
            '        let sample = """\n            heading\n              indented body\n            """',
            '        let sample = """\n        heading\n          indented body\n        """',
        )
        self.let_through("--words-only", WHERE)
        self.caught("--comments-only", WHERE)

    def test_neither_mode_has_a_default(self) -> None:
        # Which claim is being made is the caller's to state. Guessing one for them would
        # let a sweep that rewrote prose be reported under the stricter name.
        done = self.run_tool(WHERE)
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("--comments-only", done.stderr)
        self.assertIn("--words-only", done.stderr)

    def test_the_two_modes_cannot_both_be_claimed(self) -> None:
        done = self.run_tool("--comments-only", "--words-only", WHERE)
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)


class WhatTheSwiftActuallyIs(AgainstARealRepository):
    """The lexical shapes, asked through the one number that falls over when one is misread."""

    def test_an_unchanged_file_reads_as_seven_literals_in_both_modes(self) -> None:
        # A block comment ended at its inner */ leaves `"so"` behind as code and counts
        # eight; a raw string ended at its first inner quote counts differently again.
        self.now_reads(SWIFT.replace("told it once.", "told it once, in English."))
        for mode in ("--comments-only", "--words-only"):
            self.assertIn(f"{LITERALS} literal(s)", self.let_through(mode, WHERE))

    def test_a_quote_inside_a_comment_is_not_a_literal(self) -> None:
        self.instead_of('and then says "so" before it closes.', 'and then says "so" and "thus".')
        self.assertIn(f"{LITERALS} literal(s)", self.let_through("--comments-only", WHERE))

    def test_the_same_input_twice_prints_the_same_two_numbers(self) -> None:
        # The reason the per-file line exists. Two runs that read different amounts and
        # both say ok cannot be told apart from an ok line alone.
        self.instead_of("told it once.", "told it once, in English.")
        first = self.let_through("--words-only", WHERE)
        self.assertEqual(first, self.let_through("--words-only", WHERE))
        self.assertRegex(first, r"\d+ skeleton chars, \d+ literal\(s\)")


class WhatItLooksAtWhenNotTold(AgainstARealRepository):
    def test_it_reads_the_swift_the_diff_names(self) -> None:
        self.instead_of("let attempts = 3", "let tries = 3")
        done = self.run_tool("--words-only")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn(WHERE, done.stdout)

    def test_build_products_are_not_swift_anybody_wrote(self) -> None:
        self.commit(".build/Generated.swift", "let generated = 1\n")
        self.now_reads("let generated = 2\n", path=".build/Generated.swift")
        self.instead_of("told it once.", "told it once, in English.")
        said = self.let_through("--words-only")
        self.assertNotIn(".build", said)

    def test_comparing_nothing_is_not_a_clean_bill(self) -> None:
        # The working tree equals origin/main, so the diff names no Swift at all. Printing
        # ok here would be #132's screen of SAME with the file count set to zero.
        done = self.run_tool("--comments-only")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("nothing here to prove", done.stdout)
        self.assertNotIn("ok —", done.stdout)

    def test_being_run_from_outside_a_repository_is_a_problem(self) -> None:
        # self.root holds the bare origin and the work clone, and is not itself a
        # repository. There is no tree to ask about, so there is no answer to give.
        self.instead_of("let attempts = 3", "let tries = 3")
        done = self.run_tool("--words-only", WHERE, cwd=self.root)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("not inside a git repository", done.stdout)
        self.assertNotIn("ok —", done.stdout)


class WhichTreeItReads(AgainstARealRepository):
    '''The defect this whole ledger row exists to prevent, found in the tool itself.

    The first version took its tree from __file__, copying the habit from
    Tools/check-ledger-against-git.py -- right there, because that tool reads the ledger
    out of its own clone, and exactly wrong here, because the paths come from the caller.
    Run from a worktree through /home/user/mdoro's copy of the script, it read
    /home/user/mdoro, where the sweep had already merged and the claim was true, and
    printed ok over a renamed identifier.

    A green line from a check that never looked at what it was asked about: this tool's
    own subject matter, in the tool. The case below is that run, reduced -- the script
    lives in one checkout, the caller stands in another, and the two disagree.
    '''

    def setUp(self) -> None:
        super().setUp()
        # A second checkout of the same origin. The clone carries the committed Swift and
        # not the tool, which is only ever copied into self.repo -- so running it from
        # here is the real shape: somebody else's script, this tree's question.
        self.other = self.root / "elsewhere"
        subprocess.run(
            ["git", "clone", "-q", str(self.origin), str(self.other)],
            check=True,
            capture_output=True,
        )
        self.assertFalse((self.other / "Tools").exists(), "the second checkout must not hold the tool")

    def elsewhere_now_reads(self, text: str) -> None:
        (self.other / WHERE).write_text(text, encoding="utf-8")

    def test_it_reads_the_tree_the_caller_stands_in(self) -> None:
        self.elsewhere_now_reads(SWIFT.replace("let attempts = 3", "let tries = 3"))
        done = self.run_tool("--words-only", WHERE, cwd=self.other)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("tries", done.stdout)

    def test_the_script_s_own_tree_being_sound_does_not_make_the_callers_sound(self) -> None:
        # The reproduction exactly: true where the script lives, false where it was run.
        # The first version answered for the wrong one and said ok.
        self.now_reads(SWIFT.replace("told it once.", "told it once, in English."))
        self.elsewhere_now_reads(SWIFT.replace("let attempts = 3", "let tries = 3"))
        done = self.run_tool("--words-only", WHERE, cwd=self.other)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("tries", done.stdout)

    def test_the_callers_tree_being_sound_is_not_spoiled_by_the_scripts(self) -> None:
        # And the other way about, which is the half that would hide the bug: a rename
        # sitting in the script's own tree must not be reported against a clean caller.
        self.now_reads(SWIFT.replace("let attempts = 3", "let tries = 3"))
        done = self.run_tool("--words-only", WHERE, cwd=self.other)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn("tries", done.stdout)

    def test_a_borrowed_script_says_which_tree_it_read(self) -> None:
        # Borrowing another clone's copy is fair. Doing it in silence is what was wrong.
        self.elsewhere_now_reads(SWIFT.replace("told it once.", "told it once, in English."))
        done = self.run_tool("--words-only", WHERE, cwd=self.other)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("note: reading", done.stdout)
        self.assertIn(str(self.other), done.stdout)

    def test_a_script_read_from_its_own_tree_says_nothing_extra(self) -> None:
        self.instead_of("told it once.", "told it once, in English.")
        self.assertNotIn("note: reading", self.let_through("--words-only", WHERE))

    def test_a_clean_second_checkout_with_no_arguments_is_not_a_clean_bill(self) -> None:
        # The default file list comes from that tree's diff, so on a clean checkout it is
        # empty -- and an empty comparison is not a pass.
        done = self.run_tool("--words-only", cwd=self.other)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("nothing here to prove", done.stdout)
        self.assertNotIn("ok —", done.stdout)

    def test_the_default_file_list_comes_from_the_callers_tree(self) -> None:
        self.elsewhere_now_reads(SWIFT.replace("let attempts = 3", "let tries = 3"))
        done = self.run_tool("--words-only", cwd=self.other)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn(WHERE, done.stdout)
        self.assertIn("tries", done.stdout)

    def test_a_path_outside_the_callers_tree_is_not_quietly_read(self) -> None:
        # Naming the script's own copy of the file from the other checkout. Reading it
        # would be answering about a repository the caller never asked about.
        done = self.run_tool("--words-only", str(self.repo / WHERE), cwd=self.other)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("is not inside", done.stdout)


class WhenTheToolCannotRead(AgainstARealRepository):
    """Broken input and broken surroundings. Every one of these is a problem, never green."""

    def test_an_empty_file_is_a_problem_not_a_green_line(self) -> None:
        # #132 exactly: both sides skeletonise to the empty string, and two empty strings
        # match. The match is real and proves nothing.
        self.commit("Packages/Empty.swift", "")
        self.now_reads("\n", path="Packages/Empty.swift")
        said = self.caught("--comments-only", "Packages/Empty.swift")
        self.assertIn("skeletonises to nothing", said)

    def test_a_string_that_never_closes_is_a_problem(self) -> None:
        self.instead_of('let name = "Task.md"', 'let name = "Task.md')
        said = self.caught("--words-only", WHERE)
        self.assertIn("runs off the end of its line", said)

    def test_a_block_comment_that_never_closes_is_a_problem(self) -> None:
        self.instead_of("and then says \"so\" before it closes. */", "and then says \"so\" before it closes.")
        self.assertIn("never closes", self.caught("--comments-only", WHERE))

    def test_a_base_that_names_no_commit_is_a_problem_not_a_green_line(self) -> None:
        # Tools/check-ledger-against-git.py takes the same line about a fetch it could not
        # do: half an answer said in the voice of a whole one is how #132 read.
        self.instead_of("told it once.", "told it once, in English.")
        said = self.caught("--words-only", "--base", "origin/no-such-branch", WHERE)
        # The tree is named, because which tree was asked is the thing that went wrong here.
        self.assertIn("names no commit in", said)
        self.assertIn(str(self.repo), said)

    def test_a_file_that_is_not_at_base_is_a_problem(self) -> None:
        self.now_reads("let x = 1\n", path="Packages/Added.swift")
        said = self.caught("--comments-only", "Packages/Added.swift")
        self.assertIn("not a word that moved", said)

    def test_a_file_named_but_missing_from_the_tree_is_a_problem(self) -> None:
        (self.repo / WHERE).unlink()
        self.assertIn("not in the working tree", self.caught("--comments-only", WHERE))


class WhenTheToolItselfIsBroken(unittest.TestCase):
    """The guards, asked directly.

    They are unreachable through the command line on purpose -- the lexer is written so
    that none of them can fire -- and a guard that is never exercised is a guard nobody
    knows is broken. So these load the module and hand the guards the readings a broken
    lexer would produce.
    """

    def setUp(self) -> None:
        spec = importlib.util.spec_from_file_location("check_only_words_moved", TOOL)
        self.tool = importlib.util.module_from_spec(spec)
        # Registered before execution: dataclasses resolve their annotations through
        # sys.modules, and a module missing from it fails to build its own classes.
        sys.modules[spec.name] = self.tool
        self.addCleanup(sys.modules.pop, spec.name, None)
        spec.loader.exec_module(self.tool)
        self.segments = self.tool.Lexer(SWIFT, WHERE).scan()

    def test_an_empty_skeleton_is_a_problem_even_from_an_empty_file(self) -> None:
        said = self.tool.skeleton_of("", "Empty.swift", self.tool.COMMENTS_ONLY)
        self.assertTrue(said.problems)
        self.assertIn("would prove nothing", said.problems[0])

    def test_counting_no_literals_in_a_file_that_has_them_is_a_problem(self) -> None:
        said = self.tool.guards(WHERE, self.tool.WORDS_ONLY, "a plausible looking skeleton", 0, self.segments)
        self.assertTrue(any("no string literals" in s for s in said), said)

    def test_counting_no_literals_in_a_file_that_has_none_is_fine(self) -> None:
        # Nine sources in this repository carry quotes only in their prose. Accusing them
        # would teach the reader to pass over this whole class of complaint.
        segments = self.tool.Lexer('// a quote, "so", in a comment\nlet a = 1\n', "A.swift").scan()
        said = self.tool.guards("A.swift", self.tool.WORDS_ONLY, "let a = 1", 0, segments)
        self.assertEqual(said, [])

    def test_a_skeleton_far_shorter_than_its_source_is_a_problem(self) -> None:
        said = self.tool.guards(WHERE, self.tool.COMMENTS_ONLY, "let", LITERALS, self.segments)
        self.assertTrue(any("was swallowed" in s for s in said), said)

    def test_words_only_keeps_the_shape_of_a_literal_and_drops_what_it_says(self) -> None:
        # What the mode is, in one assertion: the prose is gone from the skeleton, and the
        # brackets that record how many literals there were, and what each interpolates,
        # are not. Both halves matter -- keeping the prose makes the mode --comments-only,
        # dropping the brackets makes it blind to a literal being split in two.
        got = self.tool.skeleton_of(SWIFT, WHERE, self.tool.WORDS_ONLY)
        self.assertIn("interp( name )", got.text)
        self.assertEqual(got.text.count("str("), LITERALS)
        self.assertNotIn("read only", got.text)

    def test_the_specimen_itself_clears_every_guard_in_both_modes(self) -> None:
        # Without this the case above could be passing because the floor rejects
        # everything, and the floors would be catching sound files in the sweeps too.
        for mode in (self.tool.COMMENTS_ONLY, self.tool.WORDS_ONLY):
            got = self.tool.skeleton_of(SWIFT, WHERE, mode)
            self.assertEqual(got.problems, [], mode)
            self.assertEqual(got.literals, LITERALS, mode)


if __name__ == "__main__":
    unittest.main(verbosity=2)
