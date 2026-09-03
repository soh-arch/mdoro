#!/usr/bin/env python3
"""The floor of the review axes, read from what the diff touches.

docs/ORCHESTRATION.md keeps the table; this script only applies it, so the
document stays the single copy and the two cannot drift. Every row is there
because something once got through, and the point of a tool is that noticing
is no longer part of the job.

    python3 Tools/axes-for.py [base]        # base defaults to main
"""
from __future__ import annotations
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RUNBOOK = ROOT / "docs/ORCHESTRATION.md"
FLOOR_HEADING = "### 床"
CEILING_HEADING = "### 天井"

# Rows whose subject is not a path. A row that is neither matched by a pattern
# nor named here is reported as unresolved rather than dropped -- a lost row
# would be a silently missing axis, which is the failure this table exists for.
BY_SHAPE = {
    "テスト": lambda p: "Tests" in p,
    "オーケストレーターが一次で書いた文章": lambda p: p.endswith(".md"),
}


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout


def changed_files(base: str) -> list[str]:
    files = set(git("diff", "--name-only", f"{base}...HEAD").split())
    for line in git("status", "--porcelain").splitlines():
        if line[3:]:
            files.add(line[3:].split(" -> ")[-1])
    return sorted(files)


def floor_rows() -> list[tuple[str, str]]:
    text = RUNBOOK.read_text(encoding="utf-8")
    start = text.index(FLOOR_HEADING)
    body = text[start : text.index(CEILING_HEADING, start)]
    rows = []
    for line in body.splitlines():
        if not line.startswith("|") or set(line) <= set("| :-"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 2 and cells[0] != "触った場所":
            rows.append((cells[0], cells[1]))
    return rows


def matches(pattern: str, path: str) -> bool:
    if pattern.endswith("/"):
        return path.startswith(pattern)
    if "/" in pattern:
        return path == pattern or path.startswith(pattern)
    return path.rsplit("/", 1)[-1] == pattern


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else "main"
    files = changed_files(base)
    if not files:
        print(f"no changes against {base}")
        return 0

    rows = floor_rows()
    if not rows:
        print(f"could not read the floor table out of {RUNBOOK.name}", file=sys.stderr)
        return 2

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

    print(f"{len(files)} file(s) against {base}\n")
    if not hits:
        print("床の表に当たる行は無い。天井だけ判断する。")
    for label, axes, touched in hits:
        print(f"■ {re.sub(r'[*`]', '', label)}")
        for axis in axes.split("／"):
            print(f"    - {re.sub(r'\s+', ' ', re.sub(r'[*`]', '', axis)).strip()}")
        print(f"      ({', '.join(touched[:6])}{' …' if len(touched) > 6 else ''})\n")

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
