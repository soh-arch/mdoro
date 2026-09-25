#!/usr/bin/env python3
"""The floor of the review axes, read from what the diff touches.

.claude/orchestrator.md keeps the table; this script only applies it, so the
document stays the single copy and the two cannot drift. Every row is there
because something once got through, and the point of a tool is that noticing
is no longer part of the job.

    python3 Tools/axes-for.py [base]        # base defaults to main

WHICH TREE IT READS. The one the caller is standing in -- `git rev-parse
--show-toplevel` from the working directory -- and never the one this script
happens to live in. The base ref comes from the caller, and so does the
question: *what did the work in front of me touch.* Taking the tree from
__file__ instead is what Tools/check-only-words-moved.py did until 2026-09-17,
copied from Tools/check-ledger-against-git.py -- right there, because that tool
reads docs/PUNCHLIST.md out of its own clone and must ask git about the same
one, and exactly wrong here. Run from a worktree through another clone's copy
of this script, the __file__ version listed that clone's diff: axes for work
nobody asked about, and silence about the work in hand (POL-282).

The floor table is read from that same tree, not from this script's. Two
reasons, and the second is the one that decides it. A branch may add a kind of
file and the row that claims it in the same commit, and a table fetched from
somewhere else would drop that row -- a missing axis, which is the whole
failure this table exists for. And a run has to answer about one repository:
reading the diff from one tree and the rule from another mixes two of them into
a single line, which is what Tools/check-ledger-against-git.py refuses from the
other side. A borrowed script whose table no longer parses fails loudly here,
naming the tree and exiting 2; it does not print a shorter list of axes.

Borrowing another clone's copy is fair, so it is allowed and announced: when the
two trees differ, the run opens with a `note:` line naming the one that was read.
"""
from __future__ import annotations
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
RUNBOOK = ".claude/orchestrator.md"
FLOOR_HEADING = "### 床"
CEILING_HEADING = "### 天井"

USAGE_ERROR = 2

# Rows whose subject is not a path. A row that is neither matched by a pattern
# nor named here is reported as unresolved rather than dropped -- a lost row
# would be a silently missing axis, which is the failure this table exists for.
# The same holds from the other side: a changed file that no row claims is named
# too, because a file nobody looks at is a missing axis just as much as a row.
BY_SHAPE = {
    "テスト": lambda p: "Tests" in p,
    "オーケストレーターが一次で書いた文章": lambda p: p.endswith(".md"),
}


# --- which tree is being asked about ------------------------------------------
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


def git(tree: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=tree, capture_output=True, text=True, check=True
    ).stdout


def changed_files(tree: Path, base: str) -> list[str]:
    files = set(git(tree, "diff", "--name-only", f"{base}...HEAD").split())
    for line in git(tree, "status", "--porcelain", "--untracked-files=all").splitlines():
        if line[3:]:
            files.add(line[3:].split(" -> ")[-1])
    return sorted(files)


def floor_rows(runbook: Path) -> list[tuple[str, str]]:
    """The table, or an empty list -- a missing file or heading is the caller's to report."""
    if not runbook.is_file():
        return []
    text = runbook.read_text(encoding="utf-8")
    try:
        start = text.index(FLOOR_HEADING)
        body = text[start : text.index(CEILING_HEADING, start)]
    except ValueError:
        return []
    rows = []
    for line in body.splitlines():
        if not line.startswith("|") or set(line) <= set("| :-"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 2 and cells[0] != "触った場所":
            rows.append((cells[0], cells[1]))
    return rows


def matches(pattern: str, path: str) -> bool:
    if pattern.startswith("/"):
        return path == pattern[1:]
    if pattern.endswith("/"):
        return path.startswith(pattern)
    if "/" in pattern:
        return path == pattern or path.startswith(pattern)
    return path.rsplit("/", 1)[-1] == pattern


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else "main"

    # POL-282: the diff, the base ref and the table all belong to the caller's tree.
    tree = toplevel(Path.cwd())
    if tree is None:
        print(
            f"{Path.cwd()} is not inside a git repository, so there is no diff to read",
            file=sys.stderr,
        )
        return USAGE_ERROR
    say_which_tree(tree)

    files = changed_files(tree, base)
    if not files:
        print(f"no changes against {base}")
        return 0

    rows = floor_rows(tree / RUNBOOK)
    if not rows:
        # Loud, not shorter: a table that cannot be read is a missing axis, and a run that
        # quietly fell back to another tree's copy would be answering about that one.
        print(f"could not read the floor table out of {tree / RUNBOOK}", file=sys.stderr)
        return USAGE_ERROR

    hits: list[tuple[str, str, list[str]]] = []
    unresolved: list[str] = []
    for label, axes in rows:
        patterns = re.findall(r"`([^`]+)`", label)
        if patterns:
            touched = [f for f in files if any(matches(p, f) for p in patterns)]
        else:
            shape = next((v for k, v in BY_SHAPE.items() if k in label), None)
            if shape is None:
                unresolved.append(label)
                continue
            touched = [f for f in files if shape(f)]
        if touched:
            hits.append((label, axes, touched))

    covered = {f for _, _, touched in hits for f in touched}
    uncovered = [f for f in files if f not in covered]

    print(f"{len(files)} file(s) against {base}\n")
    if not hits and not uncovered:
        print("床の表に当たる行は無い。天井だけ判断する。")
    for label, axes, touched in hits:
        print(f"■ {re.sub(r'[*`]', '', label)}")
        for axis in axes.split("／"):
            text = re.sub(r"\s+", " ", re.sub(r"[*`]", "", axis)).strip()
            print(f"    - {text}")
        print(f"      ({', '.join(touched[:6])}{' …' if len(touched) > 6 else ''})\n")

    if uncovered:
        print("■ 表のどの行にも当たらない —— 軸は自分で立てる")
        for f in uncovered:
            print(f"    - {f}")
        print()

    print("── 天井 ──")
    reasons = []
    if any(f == "docs/SPEC.md" for f in files):
        reasons.append("docs/SPEC.md の条文")
    if any(f.endswith(("AppModel.swift", "TimerEngine.swift")) for f in files):
        reasons.append("CONTEXT §2 の6箇所")
    if any(f.endswith(".md") for f in files):
        reasons.append("自分が一次で書いた文章（書いたなら）")
    print("立てる: " + "、".join(reasons) if reasons else "機械では立たない。")
    print('「3原則に触るか」は自分で判断する。渡すのは差分だけ、聞くのは「何を確かめるべきか」だけ。')

    for label in unresolved:
        print(f"\n★ 機械で引けない行がある。自分で判断する: {label}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
