#!/usr/bin/env python3
"""Run a role on a checkout it cannot keep, and say afterwards what moved.

The reviewer holds every tool this harness offers: .claude/agents/reviewer.md
carries no `tools:` restriction, so the two sentences telling it not to edit are
the only guard, and they are prose. docs/reviewer-model-evaluation.md records
that prose alone has already failed once here -- an instruction to pass
-destination went unread and a build landed on the attached phone. Stage two
hands the same brief to CLIs from four vendors, and none of them offers the
shape this role needs: their read-only modes are too strict for a reviewer that
runs swift test, and their workspace-write modes are not a restriction at all.

So the containment is ours, and it is deliberately small.

This is not a sandbox. Nothing here stops a command that writes to an absolute
path, and a role determined to edit the repository can still reach it. What
this does is give the role a checkout of its own that dies at the end, and then
say -- of that checkout and of this repository -- which tracked files moved.
CLAUDE.md does not forbid a role from touching the working tree; it requires
the role to declare it. This makes the declaration mechanical, so it no longer
depends on the role remembering.

What a role leaves untracked -- build output, a scratch file -- is counted and
named as untracked, not reported as a change: it dies with the checkout. Files
the tree ignores are not counted at all.

WHICH TREE THE CHECKOUT IS ADDED TO. The caller's -- `git rev-parse
--show-toplevel` from the working directory -- and never the one this script
happens to live in. Everything here comes from the caller: --ref, the command,
and the repository whose work is being handed to a role. Taking the tree from
__file__ instead is what Tools/check-only-words-moved.py did until 2026-09-17,
copied from Tools/check-ledger-against-git.py -- right there, because that tool
reads docs/PUNCHLIST.md out of its own clone and must ask git about the same
one, and exactly wrong here (POL-282). Borrowed from another clone, the
__file__ version would have resolved --ref in that clone, cut the checkout from
it, refused on *its* uncommitted work, and watched *it* for escaping writes --
so a role would have reviewed some other commit, and anything it wrote into the
repository the caller actually asked about would have gone unmentioned. That
last one is this script's whole reason for existing.

Borrowing another clone's copy is fair, so it is allowed and announced: when the
two trees differ, the run opens with a `note:` line naming the one that was read.

    python3 Tools/run-in-a-worktree.py -- swift test
    python3 Tools/run-in-a-worktree.py --ref HEAD~1 -- ./some-reviewer --json
    python3 Tools/run-in-a-worktree.py --keep -- <command...>

Exit status:

    0   the command exited 0 and no tracked file moved in either tree
    2   usage, the caller is not inside a git repository at all, or that
        repository has uncommitted work (see --allow-dirty)
    3   a tracked file moved -- in the checkout, or in this repository
    *   otherwise the command's own exit status

3 wins over the command's own status, because a role that edited is the more
important fact about the run. Do not read 0 as "the review found nothing":
what a review found is in its report, never in an exit code.
"""
from __future__ import annotations
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve()
# "role", not "review": this is for any role that is handed a shell, and the
# checkout it leaves behind when it detects a change should say which tool made
# it rather than read as a stray review directory.
PREFIX = "mdoro-role-"

USAGE_ERROR = 2
TRACKED_FILE_MOVED = 3


# --- which tree is being asked about ------------------------------------------
# POL-282: resolved once, from the working directory, and handed to everything
# that needs it. Nothing below may fall back to HERE.
def toplevel(where: Path) -> Path | None:
    done = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], cwd=where, capture_output=True, text=True
    )
    return Path(done.stdout.strip()) if done.returncode == 0 and done.stdout.strip() else None


def say_which_tree(tree: Path) -> None:
    """Borrowing another clone's copy of this script is fair. Doing it silently is not."""
    own = toplevel(HERE.parent)
    if own != tree:
        print(f"note: reading {tree}, though this script lives in {own or HERE.parent}")


def git(*args: str, cwd: Path, check: bool = True) -> str:
    """Run git in the tree given and return stdout, exiting with git's own message on failure."""
    done = subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, text=True
    )
    if check and done.returncode != 0:
        sys.exit(f"git {' '.join(args)}: {done.stderr.strip() or done.stdout.strip()}")
    return done.stdout


def status(tree: Path) -> tuple[set[str], set[str]]:
    """Return (tracked, untracked) porcelain lines for a working tree.

    Untracked is kept separate rather than dropped: a reviewer that leaves
    build output behind is behaving correctly, and the counts are worth
    printing, but they are not what this script is watching for.
    """
    tracked, untracked = set(), set()
    for line in git("status", "--porcelain", cwd=tree).splitlines():
        (untracked if line.startswith("??") else tracked).add(line)
    return tracked, untracked


def report(title: str, lines: set[str]) -> None:
    print(f"\n{title} ({len(lines)}):")
    for line in sorted(lines):
        print(f"    {line}")


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="run-in-a-worktree.py",
        description="Run a command on a throwaway checkout and report what moved.",
    )
    parser.add_argument(
        "--ref",
        default="HEAD",
        help="what the checkout is made from (default: HEAD)",
    )
    parser.add_argument(
        "--keep",
        action="store_true",
        help="keep the checkout after the run instead of removing it",
    )
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help="run even though this repository has uncommitted tracked changes",
    )
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.print_usage(sys.stderr)
        print("\nGive the command after --, for example:", file=sys.stderr)
        print("    python3 Tools/run-in-a-worktree.py -- swift test", file=sys.stderr)
        return USAGE_ERROR

    tree = toplevel(Path.cwd())
    if tree is None:
        print(
            f"{Path.cwd()} is not inside a git repository, so there is nothing to\n"
            "make a checkout of and nothing to watch for escaping writes.",
            file=sys.stderr,
        )
        return USAGE_ERROR
    say_which_tree(tree)

    before_tracked, _ = status(tree)
    if before_tracked and not args.allow_dirty:
        report(f"This repository has uncommitted tracked changes — {tree}", before_tracked)
        print(
            "\nThe checkout is built from a commit, so uncommitted work would not\n"
            "be in it -- the role would review something other than what you have.\n"
            "Commit first, or pass --allow-dirty if you meant to review the commit.",
            file=sys.stderr,
        )
        return USAGE_ERROR

    before_untracked = status(tree)[1]
    if before_untracked:
        print(
            f"note: {len(before_untracked)} untracked file(s) here are not in the checkout"
        )

    # Resolved and cut in the caller's tree: a worktree and the clone it was made from
    # can hold different refs, and the wrong one answers confidently.
    sha = git("rev-parse", "--short", args.ref, cwd=tree).strip()
    path = Path(tempfile.mkdtemp(prefix=PREFIX))
    git("worktree", "add", "--detach", str(path), args.ref, cwd=tree)
    print(f"checkout of {args.ref} ({sha}) at {path}")
    print(f"running: {' '.join(command)}\n", flush=True)

    try:
        code = subprocess.run(command, cwd=path).returncode
    except FileNotFoundError:
        print(f"\nno such command: {command[0]}", file=sys.stderr)
        code = USAGE_ERROR
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        code = 130

    moved, left_behind = status(path)
    escaped = status(tree)[0] - before_tracked

    print(f"\ncommand exited {code}")
    if left_behind:
        print(f"untracked in the checkout ({len(left_behind)}) -- not a change; discarded with it")
    if moved:
        report("TRACKED FILES MOVED IN THE CHECKOUT", moved)
    if escaped:
        report(f"TRACKED FILES MOVED IN THIS REPOSITORY — {tree}", escaped)
        print("\nThe command wrote outside its checkout. This script cannot stop that.")
    if not moved and not escaped:
        print("no tracked file moved in either tree")

    if args.keep or moved or escaped:
        print(f"\nkeeping {path}")
        print(f"    git worktree remove --force {path}")
    else:
        git("worktree", "remove", "--force", str(path), cwd=tree)

    return TRACKED_FILE_MOVED if (moved or escaped) else code


if __name__ == "__main__":
    sys.exit(main())
