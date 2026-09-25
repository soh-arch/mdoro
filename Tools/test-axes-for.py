#!/usr/bin/env python3
"""What axes-for.py must answer for, and which repository it must answer about.

The tool had no cases at all until POL-282, which is how it kept the defect that
ticket is named for: it took its tree from __file__ while its base ref, and the
question, came from the caller. Run from a worktree through another clone's copy
of the script, it listed that clone's diff -- axes for work nobody asked about,
and silence about the work in hand.

A missing axis is exactly what the floor table exists to prevent, so this is the
tool failing at its own subject. The cases below therefore never copy the script
into the repository they run it from: the script lives in self.repo, the caller
stands in self.other, and the two are built to disagree -- different diffs,
different refs, different floor tables. A tool answering for the wrong tree says
so out loud here.

Both directions are kept. That the caller's tree is read does not prove the
script's tree is unread, and a check missing that half lets the defect hide
(learned on Tools/check-only-words-moved.py, 2026-09-17).

    python3 Tools/test-axes-for.py
"""
from __future__ import annotations
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "axes-for.py"
RUNBOOK = ".claude/orchestrator.md"

# The shape the tool parses, reduced to what the parser reads: the two headings, a header
# row it skips, and two-cell rows whose first cell holds the paths in backticks. `rows` is
# written by each case, so that the two repositories can be given tables that disagree.
RUNBOOK_TEMPLATE = """# ORCHESTRATION

### 床

| 触った場所 | 必ず立てる軸 |
| :---- | :---- |
{rows}

### 天井

anything after this heading is not the floor.
"""


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True, text=True)


class AgainstTwoRepositories(unittest.TestCase):
    def setUp(self) -> None:
        # Resolved, because git answers with the physical path and the cases hold what it
        # printed against what they built.
        self.sandbox = Path(tempfile.mkdtemp(prefix="mdoro-axes-test-")).resolve()
        self.addCleanup(shutil.rmtree, self.sandbox, ignore_errors=True)

        # Where the script lives. Its table and its diff are the wrong answers, kept
        # deliberately distinguishable from the caller's.
        self.repo = self.make_repo(
            "work",
            rows="| `Sources/` | axis-of-the-script-tree |",
            files={"Sources/OnlyThere.swift": "let there = 1\n"},
        )
        (self.repo / "Tools").mkdir()
        shutil.copy(TOOL, self.repo / "Tools" / TOOL.name)
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "the tool")

        # Where the caller stands. A repository of its own, holding no copy of the script.
        self.other = self.make_repo(
            "elsewhere",
            rows="| `Client/` | axis-of-the-callers-tree |\n| オーケストレーターが一次で書いた文章 | prose-axis |",
            files={"Client/OnlyHere.swift": "let here = 1\n"},
        )
        self.assertFalse((self.other / "Tools").exists(), "the caller must not hold the tool")

        self.outside = self.sandbox / "plain"
        self.outside.mkdir()

    # --- building the two ------------------------------------------------------
    def make_repo(self, name: str, rows: str, files: dict[str, str]) -> Path:
        repo = self.sandbox / name
        repo.mkdir()
        git(repo, "init", "-q", "-b", "main")
        git(repo, "config", "user.email", "test@example.invalid")
        git(repo, "config", "user.name", "test")
        self.write(repo, RUNBOOK, RUNBOOK_TEMPLATE.format(rows=rows))
        for path, text in files.items():
            self.write(repo, path, text)
        git(repo, "add", "-A")
        git(repo, "commit", "-qm", "first")
        return repo

    def write(self, repo: Path, path: str, text: str) -> None:
        here = repo / path
        here.parent.mkdir(parents=True, exist_ok=True)
        here.write_text(text, encoding="utf-8")

    def run_tool(self, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(self.repo / "Tools" / TOOL.name), *args],
            cwd=cwd or self.repo,
            capture_output=True,
            text=True,
        )

    # --- what it answers about the caller --------------------------------------
    def test_it_lists_the_callers_changes(self) -> None:
        self.write(self.other, "Client/OnlyHere.swift", "let here = 2\n")
        done = self.run_tool("main", cwd=self.other)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("Client/OnlyHere.swift", done.stdout)
        self.assertIn("axis-of-the-callers-tree", done.stdout)

    def test_the_floor_table_is_the_callers(self) -> None:
        # The row that claims this path exists only in the caller's runbook. Read from the
        # script's tree instead, the file falls through as claimed by no row -- a missing
        # axis, which is the failure the table exists for.
        self.write(self.other, "Client/OnlyHere.swift", "let here = 2\n")
        done = self.run_tool("main", cwd=self.other)
        self.assertIn("axis-of-the-callers-tree", done.stdout)
        self.assertNotIn("axis-of-the-script-tree", done.stdout)
        self.assertNotIn("軸は自分で立てる", done.stdout)

    def test_a_row_matched_by_shape_still_works_from_the_callers_table(self) -> None:
        self.write(self.other, "docs/NOTES.md", "prose\n")
        done = self.run_tool("main", cwd=self.other)
        self.assertIn("prose-axis", done.stdout)
        self.assertIn("docs/NOTES.md", done.stdout)

    def test_the_base_ref_is_resolved_in_the_callers_tree(self) -> None:
        # A name only the caller has. Asked of the other repository it resolves to nothing.
        git(self.other, "branch", "only-there")
        self.write(self.other, "Client/OnlyHere.swift", "let here = 2\n")
        done = self.run_tool("only-there", cwd=self.other)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("Client/OnlyHere.swift", done.stdout)

    # --- and the script's tree does not leak into the answer --------------------
    def test_the_scripts_own_changes_are_not_reported_to_a_clean_caller(self) -> None:
        # The half without which the defect can still hide. Under it, this printed the
        # script tree's file list to a caller that had changed nothing.
        self.write(self.repo, "Sources/OnlyThere.swift", "let there = 2\n")
        done = self.run_tool("main", cwd=self.other)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("no changes against main", done.stdout)
        self.assertNotIn("OnlyThere.swift", done.stdout)

    def test_a_caller_without_a_runbook_is_loud_not_quietly_borrowed(self) -> None:
        # Falling back to the script's copy would answer with another repository's rule
        # while printing a clean list of axes, which reads exactly like an answer.
        (self.other / RUNBOOK).unlink()
        self.write(self.other, "Client/OnlyHere.swift", "let here = 2\n")
        done = self.run_tool("main", cwd=self.other)
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("could not read the floor table", done.stderr)
        self.assertIn(str(self.other), done.stderr)
        self.assertNotIn("axis-of-the-script-tree", done.stdout)

    def test_a_runbook_without_the_headings_is_loud(self) -> None:
        self.write(self.other, RUNBOOK, "# ORCHESTRATION\n\nno table here.\n")
        self.write(self.other, "Client/OnlyHere.swift", "let here = 2\n")
        done = self.run_tool("main", cwd=self.other)
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("could not read the floor table", done.stderr)

    # --- and it says which tree it read ----------------------------------------
    def test_a_borrowed_script_says_which_tree_it_read(self) -> None:
        self.write(self.other, "Client/OnlyHere.swift", "let here = 2\n")
        done = self.run_tool("main", cwd=self.other)
        self.assertIn("note: reading", done.stdout)
        self.assertIn(str(self.other), done.stdout)
        self.assertIn(str(self.repo), done.stdout)

    def test_a_script_run_from_its_own_tree_says_nothing_extra(self) -> None:
        # The allowed case must stay quiet: a note printed on every ordinary run is noise,
        # and noise in every run is how a line stops being read.
        self.write(self.repo, "Sources/OnlyThere.swift", "let there = 2\n")
        done = self.run_tool("main")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn("note: reading", done.stdout)
        self.assertIn("axis-of-the-script-tree", done.stdout)

    def test_being_run_from_outside_a_repository_is_a_problem(self) -> None:
        done = self.run_tool("main", cwd=self.outside)
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("not inside a git repository", done.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
