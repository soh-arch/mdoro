#!/usr/bin/env python3
"""Mechanical checks on the documents.

Every check here corresponds to a mistake that actually reached a pull request.
The point is not completeness: it is that these classes never need a reader
again. Run it before asking anyone — human or model — to read a change.

    python3 Tools/check-docs.py
"""
from __future__ import annotations
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "docs/SPEC.md"
PUNCH = ROOT / "docs/PUNCHLIST.md"
DECISIONS = ROOT / "docs/decisions"

failures: list[str] = []


def note(check: str, detail: str) -> None:
    failures.append(f"[{check}] {detail}")


def markdown_files() -> list[Path]:
    files = [ROOT / "CLAUDE.md", ROOT / "AGENTS.md", ROOT / "README.md"]
    files += sorted((ROOT / "docs").rglob("*.md"))
    files += sorted((ROOT / ".claude").rglob("*.md"))
    return [f for f in files if f.exists()]


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
    """
    return subprocess.run(
        ["git", "check-ignore", "-q", target], cwd=ROOT
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
        for m in re.finditer(r"REQ-[A-Z]{3}-\d{3}", text):
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
    for md in markdown_files():
        if md == PUNCH:
            continue
        text = read(md)
        for m in re.finditer(r"POL-(\d+)", text):
            if int(m.group(1)) not in filed:
                line = text[: m.start()].count("\n") + 1
                note("pol", f"{md.relative_to(ROOT)}:{line} cites POL-{m.group(1)}, which is not filed")


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


def main() -> int:
    check_links()
    check_inline_paths()
    check_requirement_ids()
    check_pols()
    check_decisions()
    check_spec_header()
    if not failures:
        print("ok — links, inline paths, requirement ids, POL numbers, decision records, spec header")
        return 0
    print(f"{len(failures)} problem(s):\n")
    for f in failures:
        print(f"  {f}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
