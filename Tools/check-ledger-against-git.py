#!/usr/bin/env python3
"""Ask git whether a row in progress names work that is still alive.

    python3 Tools/check-ledger-against-git.py
    python3 Tools/check-ledger-against-git.py --no-fetch   # answer from the refs already here

The ledger's status column and its pull-request column are written by hand, so
both record an intention and nothing else. Tools/check-docs.py already asks the
`doing` and `review` rows to *name* their work, and deliberately stops there: it
needs no network and no history, and a check that cannot run everywhere is worse
than one that can (POL-245). So nothing has ever asked whether the name still
points at anything, and on 2026-09-14 one row had carried `doing` across the
merge of the very branch it named (POL-257).

This is the rest of that question, kept in its own file because it is a
different kind of question: it reads git's remote refs, and by default it talks
to origin first. Of every `doing` / `review` row it asks two things of each
branch named:

  - origin has it, and
  - origin/main does not have it yet.

Failing either is the same mistake in one of its two directions -- a row that
says work is under way when the branch is gone, and one that says it when the
work has already landed.

It reads from the ledger outwards, so the other direction POL-257 recorded is
still nobody's: a branch alive on origin that no row names at all goes
unmentioned here. Three of those were found by hand that day. Asking that
question means deciding which branches are meant to be listed, and this tool
does not decide it.

WHAT THIS CANNOT ANSWER, AND SAYS SO. A row may name a pull request (`#118`)
rather than a branch. Whether a pull request is open, merged or closed is a fact
about GitHub, not about git, and no ref in this repository holds it. Those rows
are *counted and reported* -- "N row(s) name a pull request and no branch; git
cannot answer for those" -- rather than skipped in silence, because a number
that appears under the ok line can be read against the ledger, and a silence
cannot be. It is not a problem and does not change the exit status.

A row naming neither is not this tool's business either: check_in_progress_rows
in Tools/check-docs.py is the one that answers for that, and two tools
complaining about one cell only teaches the reader to skip both.

Squash merges are the deliberate soft spot. A branch that reached main under a
new commit is not an ancestor of origin/main, so it reads as unmerged here and
nothing is said. That is the harmless direction: the noisy direction would fire
on sound rows, and a check people learn to ignore has stopped being a check.

Today it costs nothing. This repository merges with a merge commit -- checked on
2026-09-16, `git log origin/main --merges` names pull requests #116, #117 and
#118 -- so the branch a row names is an ancestor of origin/main once it lands,
and a row left at `doing` across its own merge is caught. Change how this
repository merges and the soft spot above is what is left.

Output and exit status follow Tools/check-docs.py: one `ok — ...` line and 0, or
`N problem(s):` and 1.
"""
from __future__ import annotations
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUNCH = ROOT / "docs/PUNCHLIST.md"

# The full ref path, so that a branch called `main` or `HEAD` cannot be resolved as
# something else, and so that `git rev-parse` answers about origin rather than about
# whatever local branch happens to share the name.
ORIGIN = "refs/remotes/origin"
MAIN = f"{ORIGIN}/main"

failures: list[str] = []


def note(check: str, detail: str) -> None:
    failures.append(f"[{check}] {detail}")


# --- reading the ledger -------------------------------------------------------
# The same three column facts check_in_progress_rows reads in Tools/check-docs.py: the
# status cell holds one of these words on its own, the cell after it names the work, a
# branch is `prefix/name` in backticks and a pull request is #nnn. Copied rather than
# imported: that module owns global paths it rebinds for its own self-test, and pulling
# it in here would make this tool's answer depend on that state. The cost is that the
# ledger's shape is now written down twice -- if the columns move, both files move.
IN_PROGRESS = ("doing", "review")
BRANCH = re.compile(r"`([^`\s]*/[^`\s]*)`")
PULL_REQUEST = re.compile(r"#\d+")

# A body cell can hold an escaped pipe (`grep -o \| wc -l`), and splitting on the bare
# character walks the columns out of step.
CELL = re.compile(r"(?<!\\)\|")


def punch_rows() -> list[tuple[int, str, list[str]]]:
    rows = []
    for line_no, line in enumerate(PUNCH.read_text(encoding="utf-8").split("\n"), 1):
        m = re.match(r"\| \*\*POL-(\d+)\*\*", line)
        if m:
            cells = [c.strip().strip("*").strip() for c in CELL.split(line)]
            rows.append((line_no, m.group(1), cells))
    return rows


# --- asking git ---------------------------------------------------------------
def git(*args: str) -> subprocess.CompletedProcess[str]:
    """Run git where the ledger is, not where the caller happens to be standing."""
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)


def is_here(ref: str) -> bool:
    return git("rev-parse", "--verify", "--quiet", ref).returncode == 0


def is_in_main(ref: str) -> bool:
    return git("merge-base", "--is-ancestor", ref, MAIN).returncode == 0


def fetch() -> bool:
    """Refresh the remote refs. A stale ref answers confidently and wrongly."""
    done = git("fetch", "origin", "--prune")
    if done.returncode == 0:
        return True
    complaint = (done.stderr or done.stdout).strip().split("\n")[-1] if (done.stderr or done.stdout) else ""
    note(
        "remote",
        f"git fetch origin --prune failed, so nothing here would be current: {complaint} "
        f"-- pass --no-fetch to answer from the refs already here",
    )
    return False


# --- the check ----------------------------------------------------------------
def check_rows_in_progress() -> tuple[int, int, int]:
    """Returns (rows in progress, branches that answered well, rows only a PR names)."""
    if not is_here(MAIN):
        # Without it there is no answer to the second question, and half an answer given
        # in full voice is how this class of mistake got here in the first place.
        note(
            "remote",
            f"{MAIN} is not here, so nothing can be said about what has landed "
            f"-- fetch origin, or run without --no-fetch",
        )
        return 0, 0, 0

    rows = branches = pull_requests = 0
    for line_no, pol, cells in punch_rows():
        at = next((i for i, c in enumerate(cells) if c in IN_PROGRESS), None)
        if at is None:
            continue
        named = cells[at + 1] if at + 1 < len(cells) else ""
        found = BRANCH.findall(named)
        if not found:
            if PULL_REQUEST.search(named):
                rows += 1
                pull_requests += 1
            # A row naming neither is check_in_progress_rows' question, not this one.
            continue
        rows += 1
        for branch in found:
            where = f"docs/PUNCHLIST.md:{line_no} POL-{pol} is `{cells[at]}` and names `{branch}`"
            if not is_here(f"{ORIGIN}/{branch}"):
                note(
                    "branch",
                    f"{where}, which origin does not have -- the work landed and the branch "
                    f"was deleted, or it was never pushed",
                )
            elif is_in_main(f"{ORIGIN}/{branch}"):
                note(
                    "branch",
                    f"{where}, which origin/main already has -- the row says the work is under "
                    f"way, and it is in",
                )
            else:
                branches += 1
    return rows, branches, pull_requests


def report(rows: int, branches: int, pull_requests: int) -> int:
    if failures:
        print(f"{len(failures)} problem(s):\n")
        for f in failures:
            print(f"  {f}")
    else:
        print(
            f"ok — {rows} row(s) in progress, "
            f"{branches} branch(es) on origin and not yet in origin/main"
        )
    if pull_requests:
        print(f"     {pull_requests} row(s) name a pull request and no branch; git cannot answer for those")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ask git whether the ledger's rows in progress name work that is still alive.",
    )
    parser.add_argument(
        "--no-fetch",
        action="store_true",
        help="do not talk to origin; answer from the remote refs already in this clone",
    )
    args = parser.parse_args()

    if not args.no_fetch and not fetch():
        return report(0, 0, 0)
    return report(*check_rows_in_progress())


if __name__ == "__main__":
    sys.exit(main())
