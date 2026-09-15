#!/usr/bin/env python3
"""What check-ledger-against-git.py must still notice when nobody is watching.

A sound repository gives this check nothing to fire on: with every `doing` row
naming a live branch, a check that had stopped working would print the same ok
line as one that works. That is the gap Tools/check-docs.py closed for itself
with --self-test, and the rule it left behind -- every check has a case it must
catch and a sound case it must let through (POL-246). A new check arriving
without its own cases would be the one exception, which is how the rule stops
being one.

So each case here builds a real repository: a bare one to be origin, a work
clone beside it, branches actually pushed and actually merged. Nothing is
stubbed and no network is used -- origin is a path on disk -- so what comes back
is git's own answer to the question the tool asks, not a rehearsal of it.

Each case gets its own temp directory and copies the tool into it, so nothing
here reads or touches this repository.

What these cases hold:

  - a `doing` row naming a branch origin does not have is caught
  - a `doing` row naming a branch origin/main already has is caught
  - a `doing` row naming a branch that is on origin and not yet in main passes
  - `review` is asked the same two questions as `doing`
  - `open` and `done` rows are not asked, however stale their names
  - a row naming a pull request is counted and reported, and is not a problem
  - a row naming neither is left to check_in_progress_rows, in silence
  - the fetch is what notices a branch deleted on origin, and --no-fetch is
    honest about answering from what is already here
  - a fetch that fails, and an origin/main that is missing, are problems rather
    than a green line
  - the tool answers for its own repository, not the caller's working directory

What they cannot hold: whether a pull request named in the ledger is open or
merged. That is a fact about GitHub; the tool says it cannot answer, and so can
these cases.

    python3 Tools/test-check-ledger-against-git.py
"""
from __future__ import annotations
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "check-ledger-against-git.py"

LEDGER_HEAD = """# punch list

| ID | 内容 | 根拠 | 場所 | 担当 | 重み | 状態 | PR |
| :---- | :---- | :---- | :---- | :---- | :---- | :---- | :---- |
"""


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True, text=True)


def a_row(
    pol: str,
    status: str,
    named: str,
    body: str = "something was filed",
    grounds: str = "REQ-ABC-001",
) -> str:
    """One ledger row in the shape the real one has: status and PR are the last two cells."""
    return f"| **POL-{pol}** | {body} | {grounds} | `a/file.swift` | agent | minor | {status} | {named} |"


class AgainstARealRepository(unittest.TestCase):
    def setUp(self) -> None:
        self.root = Path(tempfile.mkdtemp(prefix="mdoro-ledger-test-"))
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
        (self.repo / "README.md").write_text("first\n", encoding="utf-8")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "first")
        git(self.repo, "push", "-q", "origin", "main")

        (self.repo / "Tools").mkdir()
        shutil.copy(TOOL, self.repo / "Tools" / TOOL.name)
        (self.repo / "docs").mkdir()

    # --- building a history ---------------------------------------------------
    def a_branch(self, name: str, *, on_origin: bool = True, merged: bool = False) -> None:
        git(self.repo, "checkout", "-q", "-b", name, "main")
        carried = f"{name.replace('/', '-')}.txt"
        (self.repo / carried).write_text("work\n", encoding="utf-8")
        # Only the one file: `add -A` would take the copied tool and the ledger along, and
        # checking main back out would then delete both from the working tree.
        git(self.repo, "add", carried)
        git(self.repo, "commit", "-qm", f"work on {name}")
        if on_origin:
            git(self.repo, "push", "-q", "origin", name)
        git(self.repo, "checkout", "-q", "main")
        if merged:
            git(self.repo, "merge", "-q", "--no-ff", "-m", f"merge {name}", name)
            git(self.repo, "push", "-q", "origin", "main")

    def delete_on_origin_only(self, name: str) -> None:
        """Take the branch off origin without touching this clone's remote-tracking ref.

        `git push --delete` would prune it here as well, and then every run would agree
        whether or not it fetched. This is the state a clone is really in after somebody
        else's pull request merged: a ref pointing at a branch that is gone.
        """
        git(self.origin, "update-ref", "-d", f"refs/heads/{name}")

    def a_ledger(self, *rows: str) -> None:
        (self.repo / "docs" / "PUNCHLIST.md").write_text(
            LEDGER_HEAD + "\n".join(rows) + "\n", encoding="utf-8"
        )

    def run_tool(self, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(self.repo / "Tools" / TOOL.name), *args],
            cwd=cwd or self.repo,
            capture_output=True,
            text=True,
        )


class WhatARowInProgressClaims(AgainstARealRepository):
    def test_a_branch_origin_does_not_have_is_caught(self) -> None:
        self.a_branch("fix/never-pushed", on_origin=False)
        self.a_ledger(a_row("001", "doing", "`fix/never-pushed`"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("1 problem(s):", done.stdout)
        self.assertIn("POL-001", done.stdout)
        self.assertIn("fix/never-pushed", done.stdout)
        self.assertIn("origin does not have", done.stdout)

    def test_a_branch_already_in_main_is_caught(self) -> None:
        self.a_branch("fix/already-in", merged=True)
        self.a_ledger(a_row("002", "doing", "`fix/already-in`"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("origin/main already has", done.stdout)
        self.assertIn("POL-002", done.stdout)

    def test_a_branch_on_origin_and_not_yet_in_main_is_let_through(self) -> None:
        self.a_branch("fix/under-way")
        self.a_ledger(a_row("003", "doing", "`fix/under-way`"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("ok — 1 row(s) in progress, 1 branch(es)", done.stdout)

    def test_review_is_asked_the_same_questions_as_doing(self) -> None:
        # The ledger's other in-progress word. POL-266 was `review` when this was written,
        # naming a branch its own pull request had already merged and deleted.
        self.a_branch("test/merged-and-deleted", merged=True)
        self.delete_on_origin_only("test/merged-and-deleted")
        self.a_ledger(a_row("004", "review", "`test/merged-and-deleted`"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("`review`", done.stdout)
        self.assertIn("origin does not have", done.stdout)

    def test_two_branches_in_one_cell_are_both_asked(self) -> None:
        self.a_branch("fix/one")
        self.a_branch("fix/two", on_origin=False)
        self.a_ledger(a_row("005", "doing", "`fix/one` / `fix/two`"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("1 problem(s):", done.stdout)
        self.assertIn("fix/two", done.stdout)
        self.assertNotIn("names `fix/one`", done.stdout)

    def test_an_escaped_pipe_does_not_turn_prose_into_a_status(self) -> None:
        # The ledger's cells hold shell (`grep -o \| wc -l`) and argue about statuses in
        # prose, and the cell that follows this one holds backticked paths with slashes in
        # them -- POL-257's own row names `docs/PUNCHLIST.md` and `Tools/check-docs.py`
        # there. Cut on the bare character, the prose becomes a status cell and the path
        # after it becomes the branch that status names. This row is `open`; saying anything
        # at all about it is wrong.
        #
        # What it does not show: an escaped pipe in a cell that mentions no status is
        # harmless either way, because nothing here counts columns -- the status is found by
        # its word, and the cell after it is still the cell after it.
        self.a_ledger(a_row("006", "open", "—", grounds=r"REQ-ABC-001, which the row calls \| doing"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("ok — 0 row(s) in progress", done.stdout)


class WhatThisCheckIsNotFor(AgainstARealRepository):
    def test_open_and_done_rows_are_not_asked(self) -> None:
        # Both name work that is long gone. Neither row claims anything is under way, and a
        # check that complained here would be telling the ledger to rewrite its own history.
        self.a_branch("fix/finished", merged=True)
        self.delete_on_origin_only("fix/finished")
        self.a_ledger(
            a_row("007", "open", "`fix/finished`"),
            a_row("008", "done", "`fix/finished`"),
            a_row("009", "決定済み", "`fix/finished`"),
        )
        done = self.run_tool()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("ok — 0 row(s) in progress", done.stdout)

    def test_a_row_naming_a_pull_request_is_counted_and_is_not_a_problem(self) -> None:
        # Whether #118 is open, merged or closed is a fact about GitHub. The tool says how
        # many rows it could not answer for rather than passing over them without a word.
        self.a_ledger(a_row("010", "doing", "`#118`"), a_row("011", "review", "#119"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("ok — 2 row(s) in progress, 0 branch(es)", done.stdout)
        self.assertIn("2 row(s) name a pull request and no branch", done.stdout)

    def test_a_branch_and_a_pull_request_in_one_cell_is_asked_about_the_branch(self) -> None:
        self.a_branch("fix/both")
        self.a_ledger(a_row("012", "doing", "`fix/both` (`#120`)"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("1 branch(es) on origin", done.stdout)
        self.assertNotIn("name a pull request", done.stdout)

    def test_a_row_naming_nothing_is_left_to_check_docs(self) -> None:
        # check_in_progress_rows in Tools/check-docs.py answers for this one. Two tools
        # complaining about one cell teaches the reader to skip both.
        self.a_ledger(a_row("013", "doing", "—"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("ok — 0 row(s) in progress", done.stdout)
        self.assertNotIn("name a pull request", done.stdout)


class WhatTheRefsAreWorth(AgainstARealRepository):
    def test_the_fetch_is_what_notices_a_branch_deleted_on_origin(self) -> None:
        self.a_branch("fix/pruned-away")
        self.delete_on_origin_only("fix/pruned-away")
        self.a_ledger(a_row("014", "doing", "`fix/pruned-away`"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("origin does not have", done.stdout)

    def test_no_fetch_answers_from_the_refs_already_here(self) -> None:
        # The same repository and the same ledger as the case above. Without the fetch the
        # stale ref answers, and the run is green: that is what --no-fetch costs, and a case
        # that did not show the two runs disagreeing would not be showing the cost.
        self.a_branch("fix/pruned-away")
        self.delete_on_origin_only("fix/pruned-away")
        self.a_ledger(a_row("015", "doing", "`fix/pruned-away`"))
        done = self.run_tool("--no-fetch")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("ok — 1 row(s) in progress", done.stdout)

    def test_a_fetch_that_cannot_reach_origin_is_a_problem_not_a_green_line(self) -> None:
        self.a_branch("fix/under-way")
        self.a_ledger(a_row("016", "doing", "`fix/under-way`"))
        git(self.repo, "remote", "set-url", "origin", str(self.root / "no-such-repository.git"))
        done = self.run_tool()
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("git fetch origin --prune failed", done.stdout)
        self.assertIn("--no-fetch", done.stdout)
        self.assertNotIn("ok —", done.stdout)

    def test_a_missing_origin_main_is_a_problem_not_a_green_line(self) -> None:
        # Half an answer -- the branch is here -- said in the same voice as a whole one is
        # how this class of mistake got into the ledger to begin with.
        self.a_branch("fix/under-way")
        self.a_ledger(a_row("017", "doing", "`fix/under-way`"))
        git(self.repo, "update-ref", "-d", "refs/remotes/origin/main")
        done = self.run_tool("--no-fetch")
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("refs/remotes/origin/main is not here", done.stdout)
        self.assertNotIn("ok —", done.stdout)

    def test_it_answers_for_its_own_repository_not_the_callers_directory(self) -> None:
        # CI and a role both start it from somewhere else. Reading the ledger through
        # __file__ while asking git about the current directory would answer about two
        # different repositories and say so in one line.
        self.a_branch("fix/never-pushed", on_origin=False)
        self.a_ledger(a_row("018", "doing", "`fix/never-pushed`"))
        done = self.run_tool(cwd=self.root)
        self.assertEqual(done.returncode, 1, done.stdout + done.stderr)
        self.assertIn("origin does not have", done.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
