#!/usr/bin/env python3
"""What run-in-a-worktree.py must still do when nobody is watching.

CI starting the tool proves it starts. It does not prove the tool still
notices anything: the step runs one command that touches nothing, so every
branch that makes the tool worth having -- a tracked file moved, a write that
escaped the checkout, a dirty tree refused -- is exercised by nobody. POL-201
is the ledger entry for tools nobody ran, and half-running one is the same
shape of gap.

Each case builds a repository of its own in a temp directory, so nothing here
depends on this repository's state and nothing here can touch it.

COPYING THE TOOL IN IS ITSELF A CHOICE, AND IT HIDES A DEFECT (POL-282). The
class below copies the tool into the repository it then runs from, which puts
the script's own tree and the caller's tree at the same path -- so "answers for
where it lives" and "answers for where it was run" are the same answer, and a
tool doing the first would pass every case here. That is exactly the shape
Tools/test-check-only-words-moved.py had while the tool it tested was reading
the wrong repository: the test could not express the defect, so it locked it in.
WhichTreeTheCheckoutIsAddedTo below therefore does not copy the tool. It stands
in a second repository and borrows the first one's script, which is how a role
running from a worktree reaches it, and it asks both halves: that the caller's
tree is the one answered for, and that the script's tree does not leak into the
answer. Keep both. Half of this pair still lets the defect hide.

    python3 Tools/test-run-in-a-worktree.py
"""
from __future__ import annotations
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parent / "run-in-a-worktree.py"


def git(repo: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)


class OnAThrowawayRepository(unittest.TestCase):
    def setUp(self) -> None:
        # Resolved, because git answers with the physical path and the cases below hold
        # what it printed against what they built.
        self.repo = Path(tempfile.mkdtemp(prefix="mdoro-tool-test-")).resolve()
        self.addCleanup(shutil.rmtree, self.repo, ignore_errors=True)
        self.repos = [self.repo]
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "test")
        (self.repo / "Tools").mkdir()
        shutil.copy(TOOL, self.repo / "Tools" / TOOL.name)
        (self.repo / "tracked.txt").write_text("first\n", encoding="utf-8")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "first")

    @property
    def script(self) -> Path:
        """Where the tool lives. Only ever inside self.repo -- never in the caller's tree."""
        return self.repo / "Tools" / TOOL.name

    def run_tool(self, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
        done = subprocess.run(
            [sys.executable, str(self.script), *args],
            cwd=cwd or self.repo,
            capture_output=True,
            text=True,
        )
        self.addCleanup(self.remove_any_kept_checkout)
        return done

    def remove_any_kept_checkout(self) -> None:
        # Every repository built by the case, because which one the checkout was added to
        # is the very thing under test: asking only one of them would leave the other's
        # worktrees behind on exactly the runs that matter.
        for repo in self.repos:
            listing = subprocess.run(
                ["git", "worktree", "list", "--porcelain"],
                cwd=repo,
                capture_output=True,
                text=True,
            ).stdout
            for line in listing.splitlines():
                if line.startswith("worktree ") and "mdoro-role-" in line:
                    subprocess.run(
                        ["git", "worktree", "remove", "--force", line.split(" ", 1)[1]],
                        cwd=repo,
                        capture_output=True,
                    )

    def test_a_command_that_touches_nothing_passes(self) -> None:
        done = self.run_tool("--", "true")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("no tracked file moved", done.stdout)

    def test_a_tracked_file_moved_in_the_checkout_is_named(self) -> None:
        done = self.run_tool("--", "sh", "-c", "echo second >> tracked.txt")
        self.assertEqual(done.returncode, 3, done.stdout + done.stderr)
        self.assertIn("TRACKED FILES MOVED IN THE CHECKOUT", done.stdout)
        self.assertIn("tracked.txt", done.stdout)
        self.assertIn("keeping", done.stdout)

    def test_a_write_that_escapes_the_checkout_is_named(self) -> None:
        escape = f"echo escaped >> {self.repo / 'tracked.txt'}"
        done = self.run_tool("--", "sh", "-c", escape)
        self.assertEqual(done.returncode, 3, done.stdout + done.stderr)
        self.assertIn("TRACKED FILES MOVED IN THIS REPOSITORY", done.stdout)
        self.assertIn("cannot stop that", done.stdout)

    def test_untracked_output_is_counted_but_is_not_a_change(self) -> None:
        done = self.run_tool("--", "sh", "-c", "echo x > left-behind.txt")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("untracked in the checkout (1)", done.stdout)
        self.assertIn("no tracked file moved", done.stdout)

    def test_a_dirty_tree_is_refused_without_running_the_command(self) -> None:
        (self.repo / "tracked.txt").write_text("uncommitted\n", encoding="utf-8")
        marker = self.repo / "the-command-ran"
        done = self.run_tool("--", "sh", "-c", f"touch {marker}")
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("uncommitted tracked changes", done.stdout)
        self.assertFalse(marker.exists(), "the command ran on a dirty tree")

    def test_allow_dirty_runs_it_anyway(self) -> None:
        (self.repo / "tracked.txt").write_text("uncommitted\n", encoding="utf-8")
        done = self.run_tool("--allow-dirty", "--", "true")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)

    def test_no_command_is_a_usage_error(self) -> None:
        done = self.run_tool()
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("Give the command after --", done.stderr)

    def test_the_command_s_own_status_is_returned(self) -> None:
        done = self.run_tool("--", "sh", "-c", "exit 7")
        self.assertEqual(done.returncode, 7, done.stdout + done.stderr)

    def test_a_script_run_from_its_own_tree_says_nothing_extra(self) -> None:
        # The note below is for a borrowed script. Printed on an ordinary run it would be
        # noise, and noise in every run is how a line stops being read.
        done = self.run_tool("--", "true")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn("note: reading", done.stdout)


class WhichTreeTheCheckoutIsAddedTo(OnAThrowawayRepository):
    """POL-282: the caller's tree, and never the one the script lives in.

    The tool is not copied into the caller's repository here. It stays where setUp put it
    -- in self.repo -- and every case below stands in self.other and runs it from there,
    which is the real shape: a role in a worktree reaching for another clone's copy of the
    script. The two trees then disagree, so an answer given for the wrong one is visible.

    Under the defect (ROOT = Path(__file__).resolve().parent.parent) the checkout would be
    cut from self.repo, --ref resolved there, self.repo's uncommitted work would refuse the
    run, and a write into self.other -- the repository the caller actually asked about --
    would go unmentioned. Both directions are asserted, because a check that only proves
    the caller's tree is read still passes while the script's tree leaks in.
    """

    def setUp(self) -> None:
        super().setUp()
        self.sandbox = Path(tempfile.mkdtemp(prefix="mdoro-tool-test-elsewhere-")).resolve()
        self.addCleanup(shutil.rmtree, self.sandbox, ignore_errors=True)

        # A repository of its own, sharing no history with the one holding the script, so
        # that anything answered about the wrong one names a file that is not there.
        self.other = self.sandbox / "elsewhere"
        self.other.mkdir()
        self.repos.append(self.other)
        git(self.other, "init", "-q", "-b", "main")
        git(self.other, "config", "user.email", "test@example.invalid")
        git(self.other, "config", "user.name", "test")
        (self.other / "only-here.txt").write_text("only in the caller\n", encoding="utf-8")
        git(self.other, "add", "-A")
        git(self.other, "commit", "-qm", "first")
        self.assertFalse((self.other / "Tools").exists(), "the caller must not hold the tool")

        # Not a repository at all: no toplevel to resolve, so there is nothing to answer.
        self.outside = self.sandbox / "plain"
        self.outside.mkdir()

    # --- the caller's tree is the one answered for ----------------------------
    def test_the_checkout_is_cut_from_the_callers_tree(self) -> None:
        done = self.run_tool("--", "sh", "-c", "cat only-here.txt", cwd=self.other)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("only in the caller", done.stdout)
        self.assertIn("no tracked file moved", done.stdout)

    def test_the_ref_is_resolved_in_the_callers_tree(self) -> None:
        git(self.other, "branch", "only-there")
        done = self.run_tool("--ref", "only-there", "--", "true", cwd=self.other)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("checkout of only-there", done.stdout)

    def test_a_tracked_file_moved_in_the_callers_tree_is_named(self) -> None:
        # The silent-green direction: under the defect this run printed "no tracked file
        # moved" while the caller's repository had just been written to.
        escape = f"echo escaped >> {self.other / 'only-here.txt'}"
        done = self.run_tool("--", "sh", "-c", escape, cwd=self.other)
        self.assertEqual(done.returncode, 3, done.stdout + done.stderr)
        self.assertIn("TRACKED FILES MOVED IN THIS REPOSITORY", done.stdout)
        self.assertIn(str(self.other), done.stdout)
        self.assertIn("only-here.txt", done.stdout)

    def test_a_dirty_caller_is_refused_though_the_scripts_tree_is_clean(self) -> None:
        (self.other / "only-here.txt").write_text("uncommitted\n", encoding="utf-8")
        marker = self.other / "the-command-ran"
        done = self.run_tool("--", "sh", "-c", f"touch {marker}", cwd=self.other)
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("uncommitted tracked changes", done.stdout)
        self.assertFalse(marker.exists(), "the command ran on a dirty tree")

    # --- and the script's tree does not leak into the answer -------------------
    def test_a_dirty_script_tree_does_not_refuse_a_clean_caller(self) -> None:
        # The half without which the defect can still hide: proving the caller is read
        # does not prove the other tree is unread. Here it is uncommitted work in the
        # script's clone, which is none of the caller's business.
        (self.repo / "tracked.txt").write_text("uncommitted\n", encoding="utf-8")
        done = self.run_tool("--", "true", cwd=self.other)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn("uncommitted tracked changes", done.stdout)
        self.assertIn("no tracked file moved", done.stdout)

    def test_a_write_into_the_scripts_own_tree_is_not_charged_to_the_caller(self) -> None:
        # Writing outside the checkout is something this script says plainly it cannot
        # stop. What it must not do is report another repository's file as the caller's.
        stray = f"echo stray >> {self.repo / 'tracked.txt'}"
        done = self.run_tool("--", "sh", "-c", stray, cwd=self.other)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertNotIn("TRACKED FILES MOVED IN THIS REPOSITORY", done.stdout)
        self.assertIn("no tracked file moved", done.stdout)

    # --- and it says which tree it read ---------------------------------------
    def test_a_borrowed_script_says_which_tree_it_read(self) -> None:
        done = self.run_tool("--", "true", cwd=self.other)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("note: reading", done.stdout)
        self.assertIn(str(self.other), done.stdout)
        self.assertIn(str(self.repo), done.stdout)

    def test_being_run_from_outside_a_repository_is_a_problem(self) -> None:
        marker = self.outside / "the-command-ran"
        done = self.run_tool("--", "sh", "-c", f"touch {marker}", cwd=self.outside)
        self.assertEqual(done.returncode, 2, done.stdout + done.stderr)
        self.assertIn("not inside a git repository", done.stderr)
        self.assertFalse(marker.exists(), "the command ran outside a repository")


if __name__ == "__main__":
    unittest.main(verbosity=2)
