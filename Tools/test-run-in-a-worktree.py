#!/usr/bin/env python3
"""What run-in-a-worktree.py must still do when nobody is watching.

CI starting the tool proves it starts. It does not prove the tool still
notices anything: the step runs one command that touches nothing, so every
branch that makes the tool worth having -- a tracked file moved, a write that
escaped the checkout, a dirty tree refused -- is exercised by nobody. POL-201
is the ledger entry for tools nobody ran, and half-running one is the same
shape of gap.

Each case builds a repository of its own in a temp directory and copies the
tool into it, so nothing here depends on this repository's state and nothing
here can touch it.

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
        self.repo = Path(tempfile.mkdtemp(prefix="mdoro-tool-test-"))
        self.addCleanup(shutil.rmtree, self.repo, ignore_errors=True)
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "test")
        (self.repo / "Tools").mkdir()
        shutil.copy(TOOL, self.repo / "Tools" / TOOL.name)
        (self.repo / "tracked.txt").write_text("first\n", encoding="utf-8")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "first")

    def run_tool(self, *args: str) -> subprocess.CompletedProcess[str]:
        done = subprocess.run(
            [sys.executable, f"Tools/{TOOL.name}", *args],
            cwd=self.repo,
            capture_output=True,
            text=True,
        )
        self.addCleanup(self.remove_any_kept_checkout)
        return done

    def remove_any_kept_checkout(self) -> None:
        listing = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            cwd=self.repo,
            capture_output=True,
            text=True,
        ).stdout
        for line in listing.splitlines():
            if line.startswith("worktree ") and "mdoro-role-" in line:
                subprocess.run(
                    ["git", "worktree", "remove", "--force", line.split(" ", 1)[1]],
                    cwd=self.repo,
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
