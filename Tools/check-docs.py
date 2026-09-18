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


def swift_files() -> list[Path]:
    """Every Swift file this repository wrote. Build products are somebody else's."""
    return [
        f for f in sorted(ROOT.glob("**/*.swift"))
        if ".build" not in f.parts and "DerivedData" not in f.parts
    ]


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


# --- the punch list stays out of the code -------------------------------------
# CLAUDE.md: コメントの根拠に POL-nnn を使わない. The ledger is an operational document that
# moves -- rows are renumbered, closed and folded into one another -- and the anchors meant to
# last are a requirement id or a record in docs/decisions/. A citation of it inside the product
# sends whoever reads the code next to a document they may not have, and outside contributors
# read AGENTS.md rather than the ledger at all.
#
# Everywhere in a .swift file, not only its comments. The four passes that cleared this out
# ended in the string literals on purpose: a `@Suite` name and an `#expect` message are printed
# by a failing test, so they are read *more* than comments are, and a reader who follows one
# gets a POL number and no document.
#
# The other tools and the workflow still cite the ledger, and are meant to: they are the side
# that writes the discipline down, not the side it binds. Their citations are held to existing
# by check_pols above, which is a different question from this one.
POL_CITATION = re.compile(r"POL-\d+")


def check_pol_free_swift() -> None:
    for f in swift_files():
        text = read(f)
        for m in POL_CITATION.finditer(text):
            line = text[: m.start()].count("\n") + 1
            note(
                "pol in swift",
                f"{f.relative_to(ROOT)}:{line} cites {m.group(0)} — "
                "the anchor has to be a requirement id or a decision record",
            )


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


# --- the 軸 column holds an axis -----------------------------------------------
# The header over the table declares column four as 軸 (A-K). Nobody was asked whether it
# holds one. Measured on 2026-09-17, over 283 eight-column rows: 57 held an axis letter, 206
# held a path or an em dash -- not what the header says, but what the ledger has settled into
# and no one's mistake -- and 20 ran past 120 characters, the longest of them 5,458. What had
# happened is that `▶` progress notes were being appended to whichever cell the writer's eye
# landed on, and column four is narrow on screen, so the note went there instead of into 症状.
# Seven rows were repaired on 2026-09-16; POL-152 and POL-165 were missed, and four pull
# requests then went on appending to the two that were missed.
#
# So this asks the column the question the header already answers for it. Two arms, because
# the twenty-two rows split on which one reaches them:
#
#   marks    `▶` and `⚠` open a note in this ledger. A note is 症状. All twenty-two carried
#            one, including three whose whole cell was `` `.gitignore` **▶ #121 で入った** `` --
#            far too short for any budget to notice.
#
#   budget   what is left after the references are taken out. A row could pile prose here
#            without ever writing a mark, and the length is then the only tell.
#
# THE BUDGET IS MEASURED, NOT CHOSEN. Take out the backticked paths, the records named as
# links, the axis letters and the separators, and count what remains. Across the repaired
# ledger the widest sound cell leaves 32 characters (`10章（REQ-PRT-005）/ 12章（REQ-ERR-009）`,
# three rows). Of the twenty-two that were broken, nineteen left 103 or more; the other three
# are the short ones the marks arm answers for. 48 sits in that gap, near enough to 32 to stay
# useful and clear enough of 103 to have caught every one of them.
#
# The four other declared columns are asked the same question, by check_declared_columns
# below. They were measured on the same day and were not sound either -- POL-077 carried 269
# characters of prose in レーン, POL-106 carried 1,992 in 重大度, and fifteen rows carried a
# ruling in PR -- and were repaired in the same pass. レーン, 重大度 and 状態 hold vocabularies
# because they are vocabularies; 軸 and PR have none worth writing down, since 206 of the one
# holds a path and 180 of the other a branch name.
AXIS_COLUMN = 4
AXIS_NOTE_MARKS = ("▶", "⚠")
AXIS_PROSE_BUDGET = 48
# What a reference looks like in this column, measured from the rows that are sound: a path in
# backticks, a decision record written as a link, an axis letter, and the separators actually in
# use. `ほか` and `および` are here because the punch list writes them; nothing invented.
AXIS_REFERENCE = (
    re.compile(r"`[^`]*`"),
    re.compile(r"\[[^\]]*\]\([^)]*\)"),
    re.compile(r"\b[A-K]\b"),
    re.compile(r"[—/・、\s]|ほか|および"),
)


def axis_prose(axis: str) -> str:
    """What is left of a 軸 cell once every reference and separator is taken out."""
    for pattern in AXIS_REFERENCE:
        axis = pattern.sub("", axis)
    return axis


def check_axis_column() -> None:
    rows = [r for r in punch_rows() if len(r[2]) == 10]
    if not rows:
        # A sound ledger gives this check nothing to fire on, so silence has to mean silence
        # and not "the table moved and I read no rows at all".
        note("axis", "no eight-column POL rows found in docs/PUNCHLIST.md — the table changed?")
        return
    for line_no, pol, cells in rows:
        axis = cells[AXIS_COLUMN]
        mark = next((m for m in AXIS_NOTE_MARKS if m in axis), None)
        if mark:
            note(
                "axis",
                f"docs/PUNCHLIST.md:{line_no} POL-{pol} has `{mark}` in its 軸 — "
                f"a note belongs at the end of 症状, not in the column the header declares as 軸",
            )
            continue
        left = axis_prose(axis)
        if len(left) > AXIS_PROSE_BUDGET:
            note(
                "axis",
                f"docs/PUNCHLIST.md:{line_no} POL-{pol} has {len(left)} characters in its 軸 that are "
                f"neither a reference nor a separator (the budget is {AXIS_PROSE_BUDGET}): {left[:60]}…",
            )


# --- the other declared columns hold what they declare ------------------------
# The same question as 軸, asked of レーン, 重大度 and 状態 here and of PR further down, and it
# had the same answer: POL-077 carried 269 characters of a progress note in レーン behind the
# role name, and POL-106 carried 1,992 in 重大度 behind `minor`. Both are repaired; this is
# what keeps them repaired.
#
# The vocabularies are measured off the ledger, not copied off the legend -- the legend was
# behind the practice on every one of them. レーン really holds two roles by name, two
# combined lanes, and an em dash; 重大度 really holds an em dash; 状態 really holds 不要 and
# 現状維持. A check written from the legend alone would have failed on the tree it was added
# to. The legend is being brought up to this list, not the other way round.
#
# A word may carry a parenthetical qualifier -- `human（Xcode）`, and four rows say which Xcode
# work and link the record that says why. So the qualifier is allowed, and then held to the
# same two arms 軸 is held to: no note mark in it, and no more prose in it than the measured
# budget. The widest real qualifier leaves nine characters once its link and its backticked
# path come out.
LANE_COLUMN, SEVERITY_COLUMN, STATE_COLUMN = 5, 6, 7
DECLARED_COLUMNS = (
    ("レーン", LANE_COLUMN, {
        "agent", "human", "agent+human", "human+agent",
        "platform-researcher", "repo-auditor", "—",
    }),
    ("重大度", SEVERITY_COLUMN, {"blocker", "major", "minor", "cosmetic", "—"}),
    ("状態", STATE_COLUMN, {
        "open", "doing", "review", "done", "rejected", "deferred",
        "決定済み", "不要", "現状維持",
    }),
)
# A trailing qualifier, in the ledger's own brackets. The ASCII pair is left out of the class
# on purpose: the qualifiers that exist carry a markdown link, whose own brackets are ASCII.
QUALIFIER = re.compile(r"（[^（）]*）$")

# --- and the PR column says where the work is ---------------------------------
# The fifth declared column, asked the same question. The legend says ブランチ名か PR 番号; it
# held fifteen rows of ruling and implementation note instead, the longest 636 characters. None
# of them were reachable by anything: check_in_progress_rows reads only the `doing` and
# `review` rows, and all fifteen are `done`. Fourteen were repaired on 2026-09-17 by moving the
# cell into 症状 and leaving behind the name that was inside it.
#
# Measured over the repaired ledger, 287 rows: 180 hold a branch name in backticks, 84 an em
# dash, 8 a bare #N, and 15 hold something else that is still only naming where the work went
# -- `SPEC v2.16`, a record named as a link, `PR #38 `3e87a73` → PR #39 `c23d331`（replay 廃止）
# で解消`. Those fifteen are why this is not a vocabulary check the way レーン is: there is no
# vocabulary here, there are 180 branch names. So it is the two arms 軸 is held to.
#
# THE BUDGET IS MEASURED, NOT CHOSEN. Take out the backticked names, the records written as
# links, the #N, the bare word PR, the spec versions and the separators, and count what is
# left. Across the repaired ledger the widest sound cell leaves 47 characters (POL-142,
# `PR #38 で前提が消えた —— …`). Of the fourteen repaired cells the narrowest left 77 (POL-154)
# and the widest 390. 64 sits in that gap, far enough above 47 that a row may still say in a
# clause where its work went, and clear of every one of the fourteen but the one named next.
#
# ONE OF THE FOURTEEN IS BELOW THE FLOOR, and this does not claim it. POL-123 held
# `[0040](…)。PR #39 の失効 UI で解消` and leaves 9 characters -- less prose than POL-143, which
# was looked at and kept. It was repaired by eye, and no budget that lets POL-142 through can
# tell it from the rows that stayed. Thirteen of the fourteen are what this arm answers for.
#
# Own budget, own references, shared marks. The reference vocabulary is this column's (#N, the
# bare PR, SPEC vN.NN) and the number is this column's measurement, so neither is shared with
# 軸 -- loosening one must not loosen the other. Every SHA in this column is already inside
# backticks, so no bare-hex pattern is invented for one that does not exist. The marks are not
# a tuning knob: `▶` and `⚠` open a note anywhere in this ledger, and AXIS_NOTE_MARKS already
# serves the other three columns here. Only one repaired row carried one (POL-156, `⚠`) and its
# prose alone was 390, so no row that existed needed the marks arm -- it is here for the shape
# 軸 actually filled up with, a name with `**▶ 入った**` stacked behind it, which is short
# enough that no budget worth having would see it.
PR_COLUMN = 8
PR_PROSE_BUDGET = 64
PR_REFERENCE = (
    re.compile(r"`[^`]*`"),
    re.compile(r"\[[^\]]*\]\([^)]*\)"),
    re.compile(r"#\d+"),
    re.compile(r"\bPR\b"),
    re.compile(r"SPEC v\d+(\.\d+)?"),
    re.compile(r"[—/・、→\s]"),
)


def pr_prose(pr: str) -> str:
    """What is left of a PR cell once every reference and separator is taken out."""
    for pattern in PR_REFERENCE:
        pr = pattern.sub("", pr)
    return pr


def check_declared_columns() -> None:
    rows = [r for r in punch_rows() if len(r[2]) == 10]
    if not rows:
        note("column", "no eight-column POL rows found in docs/PUNCHLIST.md — the table changed?")
        return
    for line_no, pol, cells in rows:
        for name, index, vocabulary in DECLARED_COLUMNS:
            cell = cells[index]
            mark = next((m for m in AXIS_NOTE_MARKS if m in cell), None)
            if mark:
                note(
                    "column",
                    f"docs/PUNCHLIST.md:{line_no} POL-{pol} has `{mark}` in its {name} — "
                    f"a note belongs at the end of 症状",
                )
                continue
            word = cell
            qualifier = QUALIFIER.search(word)
            if qualifier:
                word = word[: qualifier.start()]
                left = axis_prose(qualifier.group(0))
                if len(left) > AXIS_PROSE_BUDGET:
                    note(
                        "column",
                        f"docs/PUNCHLIST.md:{line_no} POL-{pol} qualifies its {name} with "
                        f"{len(left)} characters of prose (the budget is {AXIS_PROSE_BUDGET})",
                    )
                    continue
            word = word.replace("**", "").replace("`", "").strip()
            if word not in vocabulary:
                note(
                    "column",
                    f"docs/PUNCHLIST.md:{line_no} POL-{pol} has {word[:40]!r} in its {name}, "
                    f"which is not one of {' / '.join(sorted(vocabulary))}",
                )

    for line_no, pol, cells in rows:
        pr = cells[PR_COLUMN]
        mark = next((m for m in AXIS_NOTE_MARKS if m in pr), None)
        if mark:
            note(
                "column",
                f"docs/PUNCHLIST.md:{line_no} POL-{pol} has `{mark}` in its PR — a note belongs "
                f"at the end of 症状, not in the column that says where the work is",
            )
            continue
        left = pr_prose(pr)
        if len(left) > PR_PROSE_BUDGET:
            note(
                "column",
                f"docs/PUNCHLIST.md:{line_no} POL-{pol} has {len(left)} characters in its PR that "
                f"are neither a reference nor a separator (the budget is {PR_PROSE_BUDGET}): "
                f"{left[:60]}…",
            )


# --- a record's 状態 and its replacement agree --------------------------------
# docs/decisions/README.md binds the two together and nothing was watching that they stayed
# bound. `superseded` means 置換先: NNNN is written; a 置換先 with any other 状態 is a record
# that says it was replaced while claiming to be live. `一部置換` is the opposite case and is
# written ON PURPOSE beside `accepted` -- only part of the record was overturned, and marking
# the whole thing superseded would make its living judgements look dead -- so that pair has to
# pass, not fail.
#
# Nothing in this tree fires it: all 43 records are `accepted`, none is `superseded`, and the
# two `一部置換` records (0011, 0022) are exactly the shape README asks for. It is here for the
# first supersession, which is when getting it wrong costs something and when nobody will
# remember the rule.
#
# The third arm answers the hole filed beside POL-268. check_decisions above can only read a
# replacement whose number opens the value -- `0009` or `[0009](...)`. Write it as
# `[README](0009-gone.md)` and the declaration is not read AS a declaration at all: the number
# exists, the link is fine, check_links is happy, and the record silently stops being held to
# naming a replacement that exists. So the shape is required here rather than merely hoped for.
# Asked literally -- "no four-digit number anywhere on the line" -- that form would pass, since
# its number sits in the filename; requiring the value to OPEN on the number catches both it
# and the no-number case, and is what makes check_decisions' own arms reachable.
SUPERSEDED = "superseded"
REPLACEMENT_KEYS = ("置換先", "一部置換")
OPENS_ON_A_NUMBER = re.compile(r"\[?\d{4}")


def check_record_states() -> None:
    records = [p for p in sorted(DECISIONS.glob("*.md")) if p.name != "README.md"]
    if not records:
        note("state", "no decision records found")
        return
    for record in records:
        head = read(record).split("## ", 1)[0]
        found = re.search(r"^- \*\*状態\*\*: *(\S+)", head, re.M)
        state = found.group(1) if found else None
        declared = {
            key: re.findall(rf"^- \*\*{key}\*\*: *(.*)$", head, re.M)
            for key in REPLACEMENT_KEYS
        }
        for key, values in declared.items():
            for value in values:
                if not OPENS_ON_A_NUMBER.match(value.strip()):
                    note(
                        "state",
                        f"{record.name} declares {key} but does not open it on a four-digit "
                        f"number, so nothing reads it as a replacement: {value.strip()[:60]!r}",
                    )
        if state == SUPERSEDED and not declared["置換先"]:
            note(
                "state",
                f"{record.name} is {SUPERSEDED} and names no 置換先 — "
                "README: 別のレコードに置き換えられた。置換先: NNNN を明記する",
            )
        if declared["置換先"] and state != SUPERSEDED:
            note(
                "state",
                f"{record.name} names a 置換先 but its 状態 is {state} — "
                f"a record that was replaced is {SUPERSEDED}, and one that was only partly "
                "overturned uses 一部置換 and stays accepted",
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
        # A record marked as replaced must name a record that exists -- and, when it writes the
        # number as a link, the link must lead to the record the number names. What rests on the
        # two agreeing is docs/decisions/README.md: `superseded` and `一部置換` are written for a
        # reader who follows the link, so "replaced by 0009" pointing at 0099-*.md sends them to
        # a record nobody named. Checking the number alone passed that, and nothing else looks --
        # check_links only asks whether the target is a file. The two are separate questions, so
        # this asks its own and leaves that one alone.
        for key in ("一部置換", "置換先"):
            for m in re.finditer(rf"\*\*{key}\*\*: *(\[?)(\d{{4}})", head):
                number = m.group(2)
                if int(number) not in numbers:
                    note("decision", f"{record.name} names {key} {number}, which does not exist")
                # README allows the bare number -- `一部置換: NNNN（覆された範囲）` -- so only a
                # number written *as* a link is asked where it leads, and only the link opening
                # on that number counts: a link further along the line belongs to the prose.
                if not m.group(1):
                    continue
                link = re.match(r"[^\]\n]*\]\(([^)\n]*)\)", head[m.end():])
                if link and Path(link.group(1)).name[:4] != number:
                    note(
                        "decision",
                        f"{record.name} names {key} {number} but links to {link.group(1)}",
                    )


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
    ("POL-free Swift", check_pol_free_swift),
    ("rows in progress", check_in_progress_rows),
    ("decision records", check_decisions),
    ("spec header", check_spec_header),
    ("axis column", check_axis_column),
    ("declared columns", check_declared_columns),
    ("record states", check_record_states),
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

# One eight-column row with its 軸 left open, so each case above changes exactly that cell and
# nothing else. It is written in the ledger's own shape -- bold id, eight columns -- because
# that is what punch_rows() reads.
AXIS_ROW = "| **POL-001** | a symptom | REQ-ABC-001 | AXIS | agent | minor | done | #1 |\n"

# The same row with the three columns that hold a vocabulary left open instead.
DECLARED_ROW = "| **POL-001** | a symptom | REQ-ABC-001 | K | LANE | SEV | STATE | #1 |\n"


def a_declared_row(lane="agent", severity="minor", state="done") -> str:
    return DECLARED_ROW.replace("LANE", lane).replace("SEV", severity).replace("STATE", state)

# The same row once more with the PR column left open. WHERE rather than PR, so that replacing
# it cannot touch the word PR anywhere else in the row.
PR_ROW = "| **POL-001** | a symptom | REQ-ABC-001 | K | agent | minor | done | WHERE |\n"

# The fifteen cells that are NOT a bare branch name, an em dash or a bare #N -- copied out of
# the ledger on 2026-09-17, not composed here. Every one of them is sound: each names where the
# work went and stops. Four rows (POL-113 / 125 / 127 / 131) hold the same record link, so
# twelve strings cover the fifteen rows. If the budget is ever lowered to catch one more of the
# repaired cells, this is the case that says what it would cost.
PR_CELLS_THAT_ARE_NOT_A_NAME = (
    "SPEC v2.16",
    "`fix/axis-k-round-two`（SPEC v2.20）",
    "[0040](decisions/0040-identity-is-not-a-name.md)",
    "3本の PR（#37 / #38 / #39）で完了",
    "PR #38 `3e87a73` → PR #39 `c23d331`（replay 廃止）で解消",
    "PR #38 で2穴とも解消（リスナー1本化・ポートリセット）",
    "PR #38 で前提が消えた —— 改名の再広告は本当にリスナーを畳んで立て直すため、"
    "文言は事実と一致するようになった",
    "PR #38 `3e84ab5`（サービス直結ダイヤル）で解消。実機で接続確認済み（2026-09-02）",
    "PR #39（callback 冒頭の1行 + fold 変種）で解消",
    "PR #39 `8206457`（accept 確定後へ移動）で解消。検証役が4経路の遷移表で確認",
    "`docs/the-readme-must-not-teach-the-forbidden-move`（PR #63 で merge）",
    "裁定のみ",
)

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

    (check_pol_free_swift, "a comment in Swift citing the ledger", {
        "Packages/MdoroCore/Sources/A.swift": "// POL-001: why this line is here\n",
    }, True),
    # The half three passes of comment work would have left standing, and the reason this check
    # is not written against comments: a citation here is printed by the failing test.
    (check_pol_free_swift, "a string literal in Swift citing the ledger", {
        "PomodoroMac/PomodoroMacTests/A.swift":
            '@Suite("it folds the first listener (POL-114)")\n'
            '#expect(second !== first, "POL-114: the second start kept the first")\n',
    }, True),
    (check_pol_free_swift, "Swift anchored to a requirement and a record", {
        "Packages/MdoroCore/Sources/A.swift":
            "// REQ-ABC-001 / Decision 0040: why this line is here\n"
            '@Suite("a name with no ledger in it")\n',
    }, False),
    # The boundary, stated: the tools and the documents write the discipline down and go on
    # citing the ledger. Only .swift is bound by it, so a sound tree holding both must pass.
    (check_pol_free_swift, "a tool and a document citing the ledger beside clean Swift", {
        "Tools/a-tool.py": "# POL-001: why this line is here\n",
        "docs/a.md": "as POL-001 found\n",
        "Packages/MdoroCore/Sources/A.swift": "// REQ-ABC-001: why this line is here\n",
    }, False),
    # Checkouts under .build are somebody else's Swift, and this must not speak for them.
    (check_pol_free_swift, "a build product's Swift citing the ledger", {
        "Packages/MdoroCore/.build/checkouts/other/A.swift": "// POL-001: not ours to hold\n",
    }, False),

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
    # The same question of the unlinked form, which now travels a branch of its own. Writing the
    # pattern as `\[(\d{4})\]\(...\)` -- the shape a number-against-link comparison invites -- reads
    # only linked numbers, and a bare one stops being checked for existence at all. Every other
    # case naming a number that is not there writes it as a link.
    (check_decisions, "a bare number naming a replacement that does not exist", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: superseded\n- **置換先**: 0009"),
    }, True),
    (check_decisions, "a record naming a replacement that does exist", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: accepted\n- **一部置換**: [0002](0002-b.md)"),
        "docs/decisions/0002-b.md": SOUND_DECISION.replace("0001", "0002"),
    }, False),
    # Both records exist and the numbering has no gap, so the number-and-link disagreement is
    # the only thing left for the check to fire on. Point the link at a record that is *not*
    # there instead and the existing "does not exist" arm answers, and this case goes green
    # over a judgement that was never made.
    (check_decisions, "a replacement whose link leads somewhere other than the number it names", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: accepted\n- **一部置換**: [0002](0003-c.md)"),
        "docs/decisions/0002-b.md": SOUND_DECISION.replace("0001", "0002"),
        "docs/decisions/0003-c.md": SOUND_DECISION.replace("0001", "0003"),
    }, True),
    # docs/decisions/README.md writes the form as `一部置換: NNNN（覆された範囲）`, with no link at
    # all. A check that required one would contradict the document it is checking for.
    (check_decisions, "a replacement named by its number alone, as README allows", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: accepted\n- **一部置換**: 0002（覆された範囲）"),
        "docs/decisions/0002-b.md": SOUND_DECISION.replace("0001", "0002"),
    }, False),
    # And the bare number keeps its prose, which may itself link. The link that answers for the
    # number is the one that opens on it; reaching along the line for any `](...)` reads this
    # row's README link as the record 0002 supposedly points at, and reports a sound record.
    (check_decisions, "a bare number whose prose carries a link of its own", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted",
            "- **状態**: accepted\n- **一部置換**: 0002（[README](README.md) の範囲）"),
        "docs/decisions/0002-b.md": SOUND_DECISION.replace("0001", "0002"),
        "docs/decisions/README.md": "the index over the records\n",
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

    # 軸. Every case is an eight-column row, because that is the only shape the column count
    # makes the question meaningful for.
    (check_axis_column, "a ▶ progress note stacked in the 軸 column", {
        "docs/PUNCHLIST.md": AXIS_ROW.replace("AXIS", "`a.swift` **▶ 直した（2026-09-17）。**"),
    }, True),
    (check_axis_column, "a ⚠ note stacked in the 軸 column", {
        "docs/PUNCHLIST.md": AXIS_ROW.replace("AXIS", "E ⚠ **境界が立った** —— 別の話が続く"),
    }, True),
    # The arm the marks cannot reach: prose that never writes one. Without it, a note worded
    # plainly would sit in the column forever.
    (check_axis_column, "prose in the 軸 column that carries no mark at all", {
        "docs/PUNCHLIST.md": AXIS_ROW.replace(
            "AXIS", "`a.swift` 直したが、条文が定めていないことを根拠に挙げていたので碇を落として"
                    "制約だけを書かせた。実測はそのまま残した。裁定は済んでいる"),
    }, True),
    # And the arm the budget cannot reach: three real rows held nothing but a path and
    # `**▶ #121 で入った（2026-09-16）。**`, which is 24 characters -- under any budget worth
    # having. Dropping either arm leaves one of these two cases unanswered.
    (check_axis_column, "a note too short for the budget to notice", {
        "docs/PUNCHLIST.md": AXIS_ROW.replace("AXIS", "`.gitignore` **▶ #121 で入った（2026-09-16）。**"),
    }, True),
    (check_axis_column, "an axis letter, which is what the header declares", {
        "docs/PUNCHLIST.md": AXIS_ROW.replace("AXIS", "K"),
    }, False),
    (check_axis_column, "an axis letter in bold, and two of them", {
        "docs/PUNCHLIST.md": AXIS_ROW.replace("AXIS", "**K**") + AXIS_ROW.replace("AXIS", "K / J"),
    }, False),
    (check_axis_column, "an em dash, which 72 rows hold", {
        "docs/PUNCHLIST.md": AXIS_ROW.replace("AXIS", "—"),
    }, False),
    (check_axis_column, "the paths 206 rows actually hold, separators and all", {
        "docs/PUNCHLIST.md": AXIS_ROW.replace(
            "AXIS", "`MdoroiOSTests.swift` / `ListenerFoldingTests.swift` / `StartingTwiceTests.swift`"),
    }, False),
    (check_axis_column, "the short ways of naming a range that are in use", {
        "docs/PUNCHLIST.md": "".join(
            AXIS_ROW.replace("AXIS", a)
            for a in ("全 Swift", "docs 全域", "テスト各所", "全テストターゲット",
                      "9章・10章", "10章（REQ-PRT-005）/ 12章（REQ-ERR-009）")),
    }, False),
    # POL-192's shape: records named as links, beside paths, with a parenthetical qualifying the
    # last of them. 193 characters of cell, 24 of prose -- long, and none of it a note.
    (check_axis_column, "records named as links, with a parenthetical on one of them", {
        "docs/PUNCHLIST.md": AXIS_ROW.replace(
            "AXIS", "`CLAUDE.md` / [0041](decisions/0041-a.md) / [0011](decisions/0011-b.md) / "
                    "`docs/CONTEXT.md`（記録番号の写しを参照に。POL-183 の一部）"),
    }, False),
    # The ledger holds smaller tables with columns of their own, and column four means nothing
    # there. Reading them would report rows nobody declared anything about.
    (check_axis_column, "a row from one of the narrower tables is not this table's row", {
        "docs/PUNCHLIST.md": AXIS_ROW.replace("AXIS", "K")
                             + "| **POL-002** | 条文へ入れた。**▶ 実装した（2026-09-17）** | done |\n",
    }, False),
    (check_axis_column, "a punch list with no eight-column rows at all", {
        "docs/PUNCHLIST.md": "nothing is filed here\n",
    }, True),

    # レーン / 重大度 / 状態. POL-077 and POL-106 are the rows these were written for.
    (check_declared_columns, "a ▶ note stacked behind the role name in レーン", {
        "docs/PUNCHLIST.md": a_declared_row(lane="`platform-researcher` **▶ 調査完了**（…）"),
    }, True),
    (check_declared_columns, "1,992 characters of a note behind `minor` in 重大度", {
        "docs/PUNCHLIST.md": a_declared_row(severity="minor  **実装した（2026-09-14）。前提条件は"
                                                     "満たされていた** —— 数える部品を移した。裁定は済んでいる"),
    }, True),
    (check_declared_columns, "a 状態 nobody declared", {
        "docs/PUNCHLIST.md": a_declared_row(state="完了"),
    }, True),
    # The qualifier is allowed, so it is the obvious way to smuggle a note back in.
    (check_declared_columns, "a qualifier that is really a note", {
        "docs/PUNCHLIST.md": a_declared_row(
            lane="human（Xcode の操作が要るが、いつやるかは決まっていないので、"
                 "順序待ちのまま置いてある。決まったら書き足す）"),
    }, True),
    (check_declared_columns, "a severity that is a lane, and a lane that is a severity", {
        "docs/PUNCHLIST.md": a_declared_row(lane="minor", severity="agent"),
    }, True),
    (check_declared_columns, "the three plain words, as 157 rows write them", {
        "docs/PUNCHLIST.md": a_declared_row(),
    }, False),
    (check_declared_columns, "the same words in bold, as the ledger also writes them", {
        "docs/PUNCHLIST.md": a_declared_row(lane="**human**", severity="**major**", state="**done**"),
    }, False),
    (check_declared_columns, "the lanes that are shared, and the roles named by name", {
        "docs/PUNCHLIST.md": (a_declared_row(lane="agent+human") + a_declared_row(lane="human+agent")
                              + a_declared_row(lane="`platform-researcher`")
                              + a_declared_row(lane="`repo-auditor`")),
    }, False),
    (check_declared_columns, "an em dash, which レーン and 重大度 both hold", {
        "docs/PUNCHLIST.md": a_declared_row(lane="—") + a_declared_row(severity="—"),
    }, False),
    (check_declared_columns, "the four qualified lanes that are really there", {
        "docs/PUNCHLIST.md": (a_declared_row(lane="**human**（Xcode）")
                              + a_declared_row(lane="**human**（何をどう出すか）")
                              + a_declared_row(lane="**human**（Xcode。[0013](decisions/0013-a.md)）")
                              + a_declared_row(lane="**human**（`TEST_HOST` はビルド設定。"
                                                    "[0013](decisions/0013-a.md)）")),
    }, False),
    (check_declared_columns, "the states the legend added after the fact", {
        "docs/PUNCHLIST.md": (a_declared_row(state="**不要**") + a_declared_row(state="**現状維持**")
                              + a_declared_row(state="決定済み") + a_declared_row(state="deferred")),
    }, False),
    (check_declared_columns, "a punch list with no eight-column rows at all", {
        "docs/PUNCHLIST.md": "nothing is filed here\n",
    }, True),

    # PR. The fourteen cells repaired on 2026-09-17 are the rows this was written for. The
    # first case is POL-179's opening, shortened the way the 重大度 case above shortens
    # POL-106's; the second is POL-154 entire, which is the one that decides the budget.
    (check_declared_columns, "a ruling stacked in the column that should name a branch", {
        "docs/PUNCHLIST.md": PR_ROW.replace(
            "WHERE", "裁定（2026-09-02）: A —— 現状を条文にする。** 前方互換の免除は**値には及ばない**。"
                     "ただし**分類ではなく順序で決める** —— 応答を定めた条文があるならそれに従い"
                     "（REQ-TSK-036 / REQ-CFG-018 / 10.2）、定めが無い値だけを破棄する"),
    }, True),
    # POL-154 whole, the narrowest of the fourteen: 77 characters of prose once its date, its
    # arrow and its backticked path come out. The budget has to reach this far down or it
    # answers for the long ones only.
    (check_declared_columns, "the narrowest of the fourteen, which is what 64 has to reach", {
        "docs/PUNCHLIST.md": PR_ROW.replace(
            "WHERE", "決定的テスト実施（2026-09-02）: 許可 OFF + Mac 再起動 → 不可視・無表示。"
                     "**欠陥として POL-164 に引き継ぎ**、プラットフォームの事実は `platform/0009` に記録"),
    }, True),
    # The arm the budget cannot reach. No repaired PR cell had this shape -- it is the shape 軸
    # filled up with, three rows of a path and `**▶ #121 で入った**`, and the PR column is the
    # next place that habit would land.
    (check_declared_columns, "a name with a note stacked behind it, too short for the budget", {
        "docs/PUNCHLIST.md": PR_ROW.replace("WHERE", "`fix/single-instance` **▶ 入った（2026-09-17）**"),
    }, True),
    (check_declared_columns, "a branch name in backticks, as 180 rows write it", {
        "docs/PUNCHLIST.md": PR_ROW.replace("WHERE", "`docs/the-column-that-says-where-the-work-is`"),
    }, False),
    (check_declared_columns, "an em dash and a bare number, which 92 rows hold between them", {
        "docs/PUNCHLIST.md": PR_ROW.replace("WHERE", "—") + PR_ROW.replace("WHERE", "#39"),
    }, False),
    (check_declared_columns, "the fifteen that say where the work went in their own words", {
        "docs/PUNCHLIST.md": "".join(
            PR_ROW.replace("WHERE", cell) for cell in PR_CELLS_THAT_ARE_NOT_A_NAME),
    }, False),

    # 状態 and its replacement. Nothing in the real tree fires any of these; the cases are the
    # whole of what holds the check up.
    (check_record_states, "superseded, naming no replacement", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace("- **状態**: accepted", "- **状態**: superseded"),
    }, True),
    (check_record_states, "a 置換先 on a record that still calls itself accepted", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: accepted\n- **置換先**: [0002](0002-b.md)"),
    }, True),
    (check_record_states, "superseded with the 置換先 README asks for", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: superseded\n- **置換先**: [0002](0002-b.md)"),
    }, False),
    # README writes this pair on purpose: only part of the record was overturned, so it stays
    # accepted. A check that fired here would be arguing with the document it checks for.
    (check_record_states, "一部置換 beside accepted, which is the form README prescribes", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: accepted\n- **一部置換**: [0002](0002-b.md)（覆された範囲）"),
    }, False),
    (check_record_states, "一部置換 written as the bare number README also allows", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: accepted\n- **一部置換**: 0002（覆された範囲）"),
    }, False),
    # The hole filed beside POL-268. The number is on the line -- in the filename -- so asking
    # "is there a four-digit number anywhere" passes it, and check_decisions never reads the
    # declaration at all. Requiring the value to open on the number is what closes it.
    (check_record_states, "a 置換先 whose link text is a word, with the number only in the filename", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: superseded\n- **置換先**: [README](0002-b.md)"),
    }, True),
    (check_record_states, "a 置換先 naming no number at all", {
        "docs/decisions/0001-a.md": SOUND_DECISION.replace(
            "- **状態**: accepted", "- **状態**: superseded\n- **置換先**: 次のレコード"),
    }, True),
    (check_record_states, "a plain accepted record, and a README that declares nothing", {
        "docs/decisions/0001-a.md": SOUND_DECISION,
        "docs/decisions/README.md": "the index over the records\n",
    }, False),
    (check_record_states, "no records at all", {}, True),
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


# What --self-test asks of a_repository, the one piece of machinery every case above runs
# through. It rebinds this module's ROOT, SPEC, PUNCH and DECISIONS, so a tool whose job is to
# answer about *this* tree answers about another one for the length of the self-test. The
# rebinding is put back, but a rebinding that stopped being put back would say nothing: the
# cases would still pass, and the next check in the same process would read a tree that has
# already been deleted. Tools/check-ledger-against-git.py copies this script's column shape
# rather than importing it so as not to inherit that state, which makes the rebinding
# load-bearing for a second tool as well -- so it is asked about here rather than assumed.
#
# Both polarities, as above: the throwaway tree really is what the checks see while inside,
# and the real one really is back once outside. Restoration is asked twice, on the normal
# return and on an exception passing through, because those are separate paths -- dropping the
# `finally` loses the second one alone (POL-293).
#
# ⚠ These are asked before the cases, and a failure stops the run there. a_repository writes the
# files it is handed under ROOT, so a rebinding that did not take makes every case write its
# fixtures over the real SPEC, ledger and records -- which is what happened when this was tried
# by mutation on 2026-09-18. That is also why the rebinding is asked about with no files handed
# in, and the file that was handed in is only asked about once the rebinding has answered.
def _paths() -> tuple[Path, Path, Path, Path]:
    return (ROOT, SPEC, PUNCH, DECISIONS)


def _not_put_back(before: tuple[Path, ...], when: str) -> list[str]:
    return [
        f"  a_repository left {name} on the throwaway tree {when}: {now} (was {was})"
        for name, was, now in zip(("ROOT", "SPEC", "PUNCH", "DECISIONS"), before, _paths())
        if now != was
    ]


class _DeliberateError(Exception):
    """Raised inside a_repository by the claim below, and caught by it. Nothing else throws it."""


def _asks_the_throwaway_tree_is_in_force() -> list[str]:
    real = _paths()
    wrong: list[str] = []
    with a_repository({}):
        if ROOT == real[0]:
            wrong.append("  a_repository left ROOT on the real tree, which every case would write into")
        for name, path in (("SPEC", SPEC), ("PUNCH", PUNCH), ("DECISIONS", DECISIONS)):
            if ROOT not in path.parents:
                wrong.append(f"  a_repository left {name} outside the throwaway tree: {path}")
    if wrong:
        # Handing a file in now would write it into the real tree. Say what is wrong instead.
        return wrong
    ledger = "a throwaway ledger\n"
    with a_repository({"docs/PUNCHLIST.md": ledger}):
        try:
            written = PUNCH.read_text(encoding="utf-8")
        except OSError as exc:
            written = f"<unreadable: {exc}>"
        if written != ledger:
            wrong.append("  a_repository did not put the files it was handed where PUNCH points")
    return wrong


def _asks_the_real_tree_is_back_on_return() -> list[str]:
    real = _paths()
    with a_repository({}):
        pass
    return _not_put_back(real, "after it returned")


def _asks_the_real_tree_is_back_after_a_raise() -> list[str]:
    real = _paths()
    try:
        with a_repository({}):
            raise _DeliberateError
    except _DeliberateError:
        pass
    return _not_put_back(real, "after an exception passed through it")


HARNESS = (
    ("the throwaway tree is what the checks see", _asks_the_throwaway_tree_is_in_force),
    ("the real tree is back on return", _asks_the_real_tree_is_back_on_return),
    ("the real tree is back after a raise", _asks_the_real_tree_is_back_after_a_raise),
)


def self_test() -> int:
    """Ask every check whether it still works, and the case table whether it still asks.

    ⚠ The regress does not close here, and is not meant to. A check needs a test; the test
    needs something over it; that needs one too. Nothing guards the loops below. So the claims
    this makes -- every check has a case it catches and a sound one it lets through, and
    a_repository hands the cases a throwaway tree and hands the real one back -- are true only
    while META, HARNESS and the loops are here. What is closed is the *quiet* failure: every
    list below is counted or named as it is walked, so deleting either an entry or the walk
    itself changes what the ok line says. Somebody still has to read it (found by the
    reviewer, 2026-09-15).
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

    # Asked before the cases run, because every one of them goes through a_repository, and
    # asked by name for the same reason META is: a deleted claim must leave the ok line (POL-293).
    asked_of_the_harness = []
    harness_wrong: list[str] = []
    for name, ask_harness in HARNESS:
        harness_wrong += ask_harness()
        asked_of_the_harness.append(name)
    wrong += harness_wrong
    if harness_wrong:
        # The cases are not run: they write their fixtures under ROOT and read through SPEC,
        # PUNCH and DECISIONS, so with those wrong they would damage the real tree or raise
        # rather than report, and this list would never be printed at all.
        print(f"a_repository is wrong in {len(harness_wrong)} place(s); the cases were not run:\n")
        print("\n".join(wrong))
        return 1

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
    print("     of a_repository: "
          + (", ".join(asked_of_the_harness) if asked_of_the_harness else "nothing was asked"))
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
