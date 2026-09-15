#!/usr/bin/env python3
"""Mechanical checks on the documents.

Every check here corresponds to a mistake that actually reached a pull request.
The point is not completeness: it is that these classes never need a reader
again. Run it before asking anyone — human or model — to read a change.

    python3 Tools/check-docs.py
    python3 Tools/check-docs.py --self-test   # ask the checks themselves

Every check here has cases of its own, because a sound repository gives a broken
check nothing to fire on: see "every check's own test" at the bottom.
"""
from __future__ import annotations
import contextlib
import re
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "docs/SPEC.md"
PUNCH = ROOT / "docs/PUNCHLIST.md"
DECISIONS = ROOT / "docs/decisions"

failures: list[str] = []


def note(check: str, detail: str) -> None:
    failures.append(f"[{check}] {detail}")


# What a role returned, kept exactly as it came back, so every check reading this list skips
# it -- links, inline paths, requirement ids and POL numbers, all four. What they name is the
# role's, not this repository's: a research report cites Chromium's own tree and writes
# relative links from wherever it was standing, and a report frozen today goes on citing a
# POL after the ledger renumbers it. Checking any of that would force an edit, and an edited
# report is no longer the thing it was kept for. docs/experiments/README.md says why.
VERBATIM = "experiments"


def markdown_files() -> list[Path]:
    files = [ROOT / "CLAUDE.md", ROOT / "AGENTS.md", ROOT / "README.md"]
    files += sorted((ROOT / "docs").rglob("*.md"))
    files += sorted((ROOT / ".claude").rglob("*.md"))
    kept = [f for f in files if f.exists()]
    # The index itself is ours, so it is checked; only what it indexes is exempt.
    return [f for f in kept if VERBATIM not in f.parts or f.name == "README.md"]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


# --- links -------------------------------------------------------------------
# A relative link that does not resolve. Bare words with no slash and no dot are
# prose in a code example ("[text](url)"), not a path.
def check_links() -> None:
    for md in markdown_files():
        for m in re.finditer(r"\[[^\]]*\]\(([^)]+)\)", read(md)):
            target = m.group(1).split("#")[0].strip()
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            if "/" not in target and "." not in target:
                continue
            if not (md.parent / target).exists():
                line = read(md)[: m.start()].count("\n") + 1
                note("link", f"{md.relative_to(ROOT)}:{line} -> {target}")


# A path named in inline code is a reference too, and it is the shape that slips
# past a link checker: `docs/reviewer-model-evaluation.md` was cited in CLAUDE.md
# while the file existed only on an unmerged branch.
REPO_DIRS = ("docs/", "Tools/", ".claude/", "Packages/", "PomodoroMac/", "Config/")


def is_ignored(target: str) -> bool:
    """A path git deliberately ignores is meant to be absent from a fresh clone.

    `Config/Signing.local.xcconfig` and `docs/PRIVATE-LINKS.md` are created by
    whoever builds the app, and the documents that name them are telling the
    reader to create one. Only this working tree ever has them.

    The answer is the exit status; git's own output is not read. It is captured
    so that a ROOT which is not a repository -- the throwaway tree the self-test
    builds -- says "not ignored" quietly instead of printing a fatal error over
    the results.
    """
    return subprocess.run(
        ["git", "check-ignore", "-q", target], cwd=ROOT, capture_output=True
    ).returncode == 0


def check_inline_paths() -> None:
    for md in markdown_files():
        text = read(md)
        for m in re.finditer(r"`([^`\s]+\.(?:md|py|swift|json|plist|xcstrings|xcconfig))`", text):
            target = m.group(1)
            if not target.startswith(REPO_DIRS):
                continue
            if "<" in target or "*" in target:  # a placeholder or a glob, not a reference
                continue
            if not (ROOT / target).exists() and not is_ignored(target):
                line = text[: m.start()].count("\n") + 1
                note("path", f"{md.relative_to(ROOT)}:{line} names {target}, which is not in the repository")


# --- requirement ids ---------------------------------------------------------
def defined_requirements() -> set[str]:
    return set(re.findall(r"^\| \*\*(REQ-[A-Z]{3}-\d{3})\*\*", read(SPEC), re.M))


def check_requirement_ids() -> None:
    defined = defined_requirements()
    if not defined:
        note("req", "no requirement rows found in docs/SPEC.md — the pattern changed?")
        return
    sources = markdown_files() + sorted(ROOT.glob("**/*.swift"))
    for f in sources:
        if ".build" in f.parts or "DerivedData" in f.parts:
            continue
        # The punch list files defects, and some of those defects *are* ids that
        # do not exist (POL-149 records a comment citing REQ-TIM-018). Naming one
        # there is the point, not a mistake.
        if f == PUNCH:
            continue
        text = read(f)
        # `\d+`, not `\d{3}`. A typo in the digits -- `REQ-ABC-0011` -- used to be read as the
        # first three of them, resolve to the id that really exists, and pass as a sound
        # citation: the check was blind to exactly the mistake it is here to catch (found by the
        # reviewer, 2026-09-15). Read whole, the typo is an id SPEC does not define, and says so.
        #
        # SPEC's own rows are still matched by `\d{3}` above, so a malformed row there defines
        # nothing and every citation of it is reported -- which is the safe direction.
        for m in re.finditer(r"REQ-[A-Z]{3}-\d+", text):
            if m.group(0) not in defined:
                line = text[: m.start()].count("\n") + 1
                note("req", f"{f.relative_to(ROOT)}:{line} cites {m.group(0)}, which SPEC does not define")


# --- punch list --------------------------------------------------------------
def filed_pols() -> set[int]:
    return {int(n) for n in re.findall(r"^\| \*\*POL-(\d+)\*\*", read(PUNCH), re.M)}


def check_pols() -> None:
    filed = filed_pols()
    if not filed:
        note("pol", "no POL rows found in docs/PUNCHLIST.md — the pattern changed?")
        return
    gaps = [n for n in range(min(filed), max(filed) + 1) if n not in filed]
    if gaps:
        note("pol", f"numbering has gaps: {gaps} (the punch list says 欠番を作らない)")
    # The tools cite the ledger too, and a citation in a comment goes stale exactly the way one
    # in a document does -- this file names POL-244 and POL-245 in its own margins. Nothing was
    # watching those. Only this check is widened: the other four reading markdown_files() ask
    # questions about prose, and a Python file is not prose.
    for source in markdown_files() + sorted((ROOT / "Tools").glob("*.py")):
        if source == PUNCH:
            continue
        text = read(source)
        for m in re.finditer(r"POL-(\d+)", text):
            if int(m.group(1)) not in filed:
                line = text[: m.start()].count("\n") + 1
                note("pol", f"{source.relative_to(ROOT)}:{line} cites POL-{m.group(1)}, which is not filed")


# --- a row in progress names its work -----------------------------------------
# A status is written by hand, so it records an intention and nothing else. Four rows
# carried `doing` for fifteen days with nothing started, and the count of what was left
# was read off them and came out wrong (POL-244). Staleness itself is not measurable
# here -- a row holds no date -- but this is: `doing` and `review` say a branch exists,
# so the row has to name it. That turns the column from a declaration into a claim the
# repository can be asked about.
#
# What counts as naming it is a shape, not the absence of a placeholder. Anything that is
# merely not an em dash -- `TODO`, `調整中`, `——`, `?` -- would satisfy a blacklist while
# naming nothing, so the cell has to carry a branch (every branch here is `prefix/name`)
# or a pull request number. That the named branch really exists is deliberately not
# checked: proving it needs the network, or refs a shallow CI checkout does not fetch,
# and a check that cannot run everywhere is worse than one that can (POL-245).
IN_PROGRESS = ("doing", "review")
NAMES_WORK = re.compile(r"`[^`\s]*/[^`\s]*`|#\d+")

# A body cell can hold an escaped pipe (`grep -o \| wc -l`), and splitting on the bare
# character walks the columns out of step. Nothing downstream of here counts columns, but
# the next reader should not have to know that.
CELL = re.compile(r"(?<!\\)\|")


def punch_rows() -> list[tuple[int, str, list[str]]]:
    rows = []
    for line_no, line in enumerate(read(PUNCH).split("\n"), 1):
        m = re.match(r"\| \*\*POL-(\d+)\*\*", line)
        if m:
            cells = [c.strip().strip("*").strip() for c in CELL.split(line)]
            rows.append((line_no, m.group(1), cells))
    return rows


def check_in_progress_rows() -> None:
    for line_no, pol, cells in punch_rows():
        at = next((i for i, c in enumerate(cells) if c in IN_PROGRESS), None)
        if at is None:
            continue
        named = cells[at + 1] if at + 1 < len(cells) else ""
        if not NAMES_WORK.search(named):
            note(
                "pol",
                f"docs/PUNCHLIST.md:{line_no} POL-{pol} is `{cells[at]}` but names no branch or pull "
                f"request -- a row in progress says where the work is, or it is not in progress",
            )


# --- decision records --------------------------------------------------------
def decision_numbers() -> set[int]:
    return {int(p.name[:4]) for p in DECISIONS.glob("[0-9][0-9][0-9][0-9]-*.md")}


def check_decisions() -> None:
    numbers = decision_numbers()
    if not numbers:
        note("decision", "no decision records found")
        return
    gaps = [n for n in range(1, max(numbers) + 1) if n not in numbers]
    if gaps:
        note("decision", f"numbering has gaps: {[f'{n:04d}' for n in gaps]} (README says 欠番は作らない)")
    for record in sorted(DECISIONS.glob("*.md")):
        text = read(record)
        head = text.split("## ", 1)[0]
        state = re.search(r"^- \*\*状態\*\*: *(\S+)", head, re.M)
        if record.name != "README.md" and not state:
            note("decision", f"{record.name} has no 状態 in its front matter")
        # a record marked as replaced must name a record that exists
        for key in ("一部置換", "置換先"):
            for m in re.finditer(rf"\*\*{key}\*\*: *\[?(\d{{4}})", head):
                if int(m.group(1)) not in numbers:
                    note("decision", f"{record.name} names {key} {m.group(1)}, which does not exist")


# --- spec self-consistency ---------------------------------------------------
def check_spec_header() -> None:
    text = read(SPEC)
    header = re.search(r"^\*\*バージョン:\*\* *([\d.]+)", text, re.M)
    if not header:
        note("spec", "no version in the SPEC header")
        return
    entries = re.findall(r"^### 0\.\d+ v[\d.]+ からの変更点（v([\d.]+)）", text, re.M)
    if not entries:
        note("spec", "no revision entries found — the heading format changed?")
        return
    newest = max(entries, key=lambda v: [int(p) for p in v.split(".")])
    if header.group(1) != newest:
        note("spec", f"header says v{header.group(1)}, newest revision entry says v{newest}")
    # Older entries state the count as it stood then, which is history and correct.
    # Only the newest entry describes the document as it is now.
    actual = len(defined_requirements())
    bodies = re.split(r"^### 0\.\d+ ", text, flags=re.M)
    newest_body = next(
        (b for b in bodies if re.match(rf"v[\d.]+ からの変更点（v{re.escape(newest)}）", b)), None
    )
    if newest_body:
        for m in re.finditer(r"要件数[^\n]*?(\d{3})要件", newest_body):
            if int(m.group(1)) != actual:
                note("spec", f"the v{newest} entry claims {m.group(1)} requirements; {actual} rows are defined")


# --- what runs, and what the ok line may claim -------------------------------
# The success message used to be a fixed string. Deleting a call from main() left it
# still naming the check it no longer ran, and the script stayed green (found by the
# reviewer, 2026-09-14). Named once, the claim cannot outlive the call.
CHECKS = (
    ("links", check_links),
    ("inline paths", check_inline_paths),
    ("requirement ids", check_requirement_ids),
    ("POL numbers", check_pols),
    ("rows in progress", check_in_progress_rows),
    ("decision records", check_decisions),
    ("spec header", check_spec_header),
)


# --- every check's own test ---------------------------------------------------
# Once the repository is sound, a check has nothing left to fire on, so breaking it leaves
# this script green and says nothing: with no broken link anywhere in the tree, a broken link
# checker still prints ok. CHECKS made a *deleted* call visible -- the name drops out of the ok
# line -- and says nothing about a call that still runs and no longer works (POL-246).
#
# So each check is run against a repository built to ask it one question. The checks read their
# inputs through ROOT, SPEC, PUNCH and DECISIONS at call time and hold no other path, so
# rebinding those four is the whole of it: no check needed a new argument, and a real run is
# untouched. Run it with --self-test; CI runs it before the checks themselves (POL-245).
#
# Both polarities are required of every check. "Catches what it should" on its own would be
# passed by a check that complains about everything, which is the same silence in a louder form.


@contextlib.contextmanager
def a_repository(files: dict[str, str]):
    """Point this module at a throwaway tree holding exactly `files`, then put it back."""
    global ROOT, SPEC, PUNCH, DECISIONS
    kept = (ROOT, SPEC, PUNCH, DECISIONS)
    with tempfile.TemporaryDirectory() as tmp:
        ROOT = Path(tmp)
        SPEC, PUNCH, DECISIONS = ROOT / "docs/SPEC.md", ROOT / "docs/PUNCHLIST.md", ROOT / "docs/decisions"
        for name, body in files.items():
            path = ROOT / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(body, encoding="utf-8")
        try:
            yield
        finally:
            ROOT, SPEC, PUNCH, DECISIONS = kept


# A spec that agrees with itself: one requirement row, a header, and a revision history whose
# newest entry states the count as it now is. The older entry states a count that was true then
# and is wrong now, which is the case check_spec_header must *not* fire on. Each case below
# changes one thing about this.
SOUND_SPEC = """# spec

**バージョン:** 2.1

## 0. 本書について

### 0.2 v2.0 からの変更点（v2.1）

| **新設** | **REQ-ABC-001** を追加。要件数 0 → 001要件 |

### 0.1 v1.0 からの変更点（v2.0）

| **整理** | 要件数 000要件 |

## 3. 要件

| ID | レベル | 内容 |
| :---- | :---- | :---- |
| **REQ-ABC-001** | MUST | a requirement |
"""

# The front matter is what check_decisions reads; everything from the first `## ` on is body.
SOUND_DECISION = """# 0001. a decision

- **状態**: accepted
- **日付**: 2026-09-15

## 文脈

why.
"""

# (check, what the tree is asking, the tree, whether the check must complain)
CASES = (
    (check_links, "a relative link whose target is not there", {
        "docs/a.md": "[b](b.md)\n",
    }, True),
    (check_links, "a relative link that resolves, anchor and all", {
        "docs/a.md": "[b](b.md#a-section) and [up](../CLAUDE.md)\n",
        "docs/b.md": "b\n",
        "CLAUDE.md": "c\n",
    }, False),
    # Two links on one line, which is where the two lazy pieces of the pattern earn their keep.
    # Let `[^\]]*` become `.*` and the pair fuses into one match that keeps only the last
    # target: a dead link beside a live one then goes unreported. Let `[^)]+` become `(.+)` and
    # the fusion runs the other way, swallowing the text between, so two sound links read as one
    # nonsense path. Neither shows up when a line holds a single link (found by the reviewer,
    # 2026-09-15 -- the sound case above missed both, because the fused target happened to keep
    # a `#` and split back into a file that exists).
    (check_links, "a dead link sharing a line with a live one", {
        "docs/a.md": "[gone](nowhere.md) and [b](b.md)\n",
        "docs/b.md": "b\n",
    }, True),
    (check_links, "two live links on one line are two links, not one", {
        "docs/a.md": "[b](b.md) and [c](c.md)\n",
        "docs/b.md": "b\n",
        "docs/c.md": "c\n",
    }, False),
    (check_links, "an absolute url is nobody's file", {
        "docs/a.md": "[x](https://example.invalid/none) [m](mailto:nobody@example.invalid)\n",
    }, False),
    (check_links, "a bare word in a code example is prose, not a path", {
        "docs/a.md": "write it as [text](url)\n",
    }, False),
    (check_links, "a report kept verbatim is exempt, however it links", {
        "docs/experiments/a-report.md": "[gone](nowhere.md)\n",
    }, False),
    (check_links, "but the index over those reports is ours", {
        "docs/experiments/README.md": "[gone](nowhere.md)\n",
    }, True),

    (check_inline_paths, "inline code naming a file the repository does not have", {
        "docs/a.md": "see `docs/gone.md`\n",
    }, True),
    (check_inline_paths, "inline code naming a file that is there", {
        "docs/a.md": "see `docs/b.md`\n",
        "docs/b.md": "b\n",
    }, False),
    (check_inline_paths, "a path outside the repository's own directories", {
        "docs/a.md": "see `notes/gone.md`\n",
    }, False),
    # One case per entry in REPO_DIRS, because a case naming several of them survives the
    # deletion of any one: the others keep it complaining. Five of the six were covered by
    # nothing at all (found by the reviewer, 2026-09-15).
    (check_inline_paths, "a missing file under Tools/", {
        "docs/a.md": "see `Tools/gone.py`\n",
    }, True),
    (check_inline_paths, "a missing file under .claude/", {
        "docs/a.md": "see `.claude/gone.md`\n",
    }, True),
    (check_inline_paths, "a missing file under Packages/", {
        "docs/a.md": "see `Packages/gone.swift`\n",
    }, True),
    (check_inline_paths, "a missing file under PomodoroMac/", {
        "docs/a.md": "see `PomodoroMac/gone.plist`\n",
    }, True),
    (check_inline_paths, "a missing file under Config/", {
        "docs/a.md": "see `Config/gone.xcconfig`\n",
    }, True),
    (check_inline_paths, "a placeholder and a glob name no one file", {
        "docs/a.md": "see `docs/<name>.md` and `docs/*.md`\n",
    }, False),

    (check_requirement_ids, "a document citing an id SPEC does not define", {
        "docs/SPEC.md": SOUND_SPEC,
        "docs/a.md": "this rests on REQ-ABC-002\n",
    }, True),
    (check_requirement_ids, "swift citing an id SPEC does not define", {
        "docs/SPEC.md": SOUND_SPEC,
        "Packages/MdoroCore/Sources/A.swift": "// REQ-ABC-002: why this line is here\n",
    }, True),
    (check_requirement_ids, "an id SPEC really defines, cited from both", {
        "docs/SPEC.md": SOUND_SPEC,
        "docs/a.md": "this rests on REQ-ABC-001\n",
        "Packages/MdoroCore/Sources/A.swift": "// REQ-ABC-001: why this line is here\n",
    }, False),
    (check_requirement_ids, "the punch list files bad ids on purpose", {
        "docs/SPEC.md": SOUND_SPEC,
        "docs/PUNCHLIST.md": "| **POL-001** | a comment cites REQ-ABC-002 | open |\n",
    }, False),
    (check_requirement_ids, "a typo in the digits of an id that does exist", {
        "docs/SPEC.md": SOUND_SPEC,
        "docs/a.md": "this rests on REQ-ABC-0011\n",
    }, True),
    (check_requirement_ids, "a SPEC with no requirement rows at all", {
        "docs/SPEC.md": "**バージョン:** 2.1\n",
    }, True),

    (check_pols, "a document citing a POL that was never filed", {
        "docs/PUNCHLIST.md": "| **POL-001** | a |\n",
        "docs/a.md": "as POL-002 found\n",
    }, True),
    (check_pols, "a gap in the numbering", {
        "docs/PUNCHLIST.md": "| **POL-001** | a |\n| **POL-003** | c |\n",
    }, True),
    (check_pols, "a document citing a POL that is filed", {
        "docs/PUNCHLIST.md": "| **POL-001** | a |\n| **POL-002** | b |\n",
        "docs/a.md": "as POL-002 found\n",
    }, False),
    # The two below are the range this check was widened to hold, and they are why the rows in
    # SELF_TEST cite POL numbers that really are filed: check_pols() now reads this file.
    (check_pols, "a tool's comment citing a POL that was never filed", {
        "docs/PUNCHLIST.md": "| **POL-001** | a |\n",
        "Tools/a-tool.py": "# POL-002: why this line is here\n",
    }, True),
    (check_pols, "a tool's comment citing a POL that is filed", {
        "docs/PUNCHLIST.md": "| **POL-001** | a |\n",
        "Tools/a-tool.py": "# POL-001: why this line is here\n",
    }, False),
    (check_pols, "a punch list with no rows at all", {
        "docs/PUNCHLIST.md": "nothing is filed here\n",
    }, True),

    (check_decisions, "a gap in the numbering", {
        "docs/decisions/0001-a.md": SOUND_DECISION,
        "docs/decisions/0003-c.md": SOUND_DECISION.replace("0001", "0003"),
    }, True),
    # The numbering starts at 0001, and a set that starts higher is the only thing that says so:
    # every other fixture here contains 0001, so the lower bound of the range could be anything
    # (found by the reviewer, 2026-09-15). The upper bound needs no case -- max(numbers) is in
    # the set by definition, so moving it produces a check that behaves identically.
    (check_decisions, "a numbering that never starts", {
        "docs/decisions/0002-b.md": SOUND_DECISION.replace("0001", "0002"),
    }, True),
    (check_decisions, "a record with no 状態 in its front matter", {
        "docs/decisions/0001-a.md": "# 0001. a decision\n\n## 文脈\n\nwhy.\n",
    }, True),
    (check_decisions, "a record naming a replacement that does not exist", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: superseded\n- **置換先**: [0009](0009-gone.md)"),
    }, True),
    (check_decisions, "a record naming a replacement that does exist", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: accepted\n- **一部置換**: [0002](0002-b.md)"),
        "docs/decisions/0002-b.md": SOUND_DECISION.replace("0001", "0002"),
    }, False),
    (check_decisions, "a sound record, beside a README that needs no 状態", {
        "docs/decisions/0001-a.md": SOUND_DECISION,
        "docs/decisions/README.md": "the index over the records\n",
    }, False),
    (check_decisions, "no records at all", {}, True),

    (check_spec_header, "the header and the newest revision entry disagree", {
        "docs/SPEC.md": SOUND_SPEC.replace("**バージョン:** 2.1", "**バージョン:** 2.0"),
    }, True),
    (check_spec_header, "the newest entry claims a count the rows do not add up to", {
        "docs/SPEC.md": SOUND_SPEC.replace("0 → 001要件", "0 → 002要件"),
    }, True),
    (check_spec_header, "no version in the header", {
        "docs/SPEC.md": SOUND_SPEC.replace("**バージョン:** 2.1\n", ""),
    }, True),
    (check_spec_header, "no revision entries", {
        "docs/SPEC.md": "**バージョン:** 2.1\n\n| **REQ-ABC-001** | MUST | a |\n",
    }, True),
    (check_spec_header, "a spec that agrees with itself, stale older counts and all", {
        "docs/SPEC.md": SOUND_SPEC,
    }, False),
)


# Rows for check_in_progress_rows, kept in the shape they are read in. Every mutation the
# reviewer found -- dropping `review`, reading the wrong cell, letting a placeholder through --
# fails at least one of them.
#
# The escaped pipe is what CELL exists for, and the two rows that carry one ask different
# things. POL-013 pins the shape it was written for and cannot fail: splitting on a bare `|`
# leaves the backslash attached to one side, so no fragment ever equals `doing`, and a broken
# CELL behaves the same. POL-014 does fail. The escape sits in the cell that is *read* rather
# than in one that is merely counted past, so splitting on a bare `|` cuts `` `a\|fix/b` `` down
# to `` `a\ `` -- no slash left in it, and the row is reported for naming no branch. Until that
# row existed, CELL was pinned and not proved (found by the reviewer, 2026-09-15).
SELF_TEST = (
    ("| **POL-001** | a | b | c | agent | minor | doing | — |", True),
    ("| **POL-002** | a | b | c | agent | minor | doing |  |", True),
    ("| **POL-003** | a | b | c | agent | minor | doing | TODO |", True),
    ("| **POL-004** | a | b | c | agent | minor | doing | —— |", True),
    ("| **POL-005** | a | b | c | agent | minor | doing | 未定 |", True),
    ("| **POL-006** | a | b | c | agent | minor | review | 調整中 |", True),
    ("| **POL-007** | a | b | c | agent | minor | review | - |", True),
    ("| **POL-008** | a | b | c | agent | minor | doing | `fix/a-branch` |", False),
    ("| **POL-009** | a | b | c | agent | minor | review | #82 |", False),
    ("| **POL-010** | a | b | c | agent | minor | open | — |", False),
    ("| **POL-011** | a | b | c | agent | minor | 決定済み | — |", False),
    ("| **POL-012** | a | b | c | agent | minor | done | — |", False),
    ("| **POL-013** | `grep -o \\| wc -l` | b | c | agent | minor | doing | — |", True),
    ("| **POL-014** | a | b | c | agent | minor | doing | `a\\|fix/b` |", False),
)


# What --self-test asks of the case table itself, rather than of any one check. Deleting a
# check's cases is as quiet as deleting the check was before CHECKS existed, so these are the
# claims that keep the table honest -- and, like CHECKS, they are named rather than merely
# written, so that the ok line cannot go on claiming one that is gone.
META = (
    ("every check is in CHECKS", lambda cases: [
        f"  {check.__name__} is not in CHECKS, so a real run never calls it"
        for check in {c for c, _, _, _ in cases} - {c for _, c in CHECKS}
    ]),
    ("every check has a case it must catch", lambda cases: [
        f"  {name} has no case it must catch"
        for name, check in CHECKS if check not in {c for c, _, _, m in cases if m}
    ]),
    ("every check has a sound case it must let through", lambda cases: [
        f"  {name} has no sound case it must let through"
        for name, check in CHECKS if check not in {c for c, _, _, m in cases if not m}
    ]),
)


def self_test() -> int:
    """Ask every check whether it still works, and the case table whether it still asks.

    ⚠ The regress does not close here, and is not meant to. A check needs a test; the test
    needs something over it; that needs one too. Nothing guards the loops below. So the claim
    this makes -- every check has a case it catches and a sound one it lets through -- is true
    only while META and the loops are here. What is closed is the *quiet* failure: both lists
    below are counted as they are walked, so deleting either an entry or the walk itself
    changes what the ok line says. Somebody still has to read it (found by the reviewer,
    2026-09-15).
    """
    cases = [
        (check_in_progress_rows, row, {"docs/PUNCHLIST.md": row + "\n"}, must_complain)
        for row, must_complain in SELF_TEST
    ]
    cases += list(CASES)
    wrong: list[str] = []

    asked = []
    for name, ask in META:
        wrong += ask(cases)
        asked.append(name)

    counts: Counter = Counter()
    for check, asking, files, must_complain in cases:
        counts[check] += 1
        with a_repository(files):
            failures.clear()
            check()
            if bool(failures) != must_complain:
                wanted = "a complaint" if must_complain else "silence"
                wrong.append(f"  {check.__name__}: wanted {wanted}, got {len(failures)}: {asking}")
    failures.clear()

    if wrong:
        print(f"the checks themselves are wrong in {len(wrong)} place(s), over {len(cases)} cases:\n")
        print("\n".join(wrong))
        return 1
    print("ok — " + ", ".join(f"{name} ({counts[check]})" for name, check in CHECKS))
    print("     of the table itself: " + (", ".join(asked) if asked else "nothing was asked"))
    return 0


def main() -> int:
    if "--self-test" in sys.argv:
        return self_test()
    for _, check in CHECKS:
        check()
    if not failures:
        print("ok — " + ", ".join(name for name, _ in CHECKS))
        return 0
    print(f"{len(failures)} problem(s):\n")
    for f in failures:
        print(f"  {f}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
