#!/usr/bin/env python3
"""Ask whether the Swift in the working tree moved anything but words.

    python3 Tools/check-only-words-moved.py --comments-only
    python3 Tools/check-only-words-moved.py --words-only --base origin/main
    python3 Tools/check-only-words-moved.py --comments-only Packages/MdoroCore/Sources/A.swift
    python3 Tools/check-only-words-moved.py --words-only --renamed declarationBody=bracedBody

Four sweeps in a row (#127, #131, #132, #133) rested their whole case on one
sentence: *nothing but comments moved; not one byte of code changed.* Each time
the role of the day wrote a throwaway stripper, hashed what came out, and lined
the hashes up. On #132 the stripper raised SyntaxError, fifteen files came back
as the empty string, and fifteen empty strings hash alike -- so the run printed
SAME fifteen times without having read a byte. A screen of SAME is what success
looks like too.

So this asks the question in the repository, once, with cases of its own
(Tools/test-check-only-words-moved.py), and it is built to fail loudly rather
than quietly agree with itself.

WHICH CLAIM IS BEING MADE IS THE CALLER'S TO STATE. There is no default mode:

  --comments-only   comments and blank lines may move. Everything else,
                    string literals included, must match byte for byte.
                    (#127, #131, #132 made this claim.)

  --words-only      comments, blank lines, and the prose inside string
                    literals may move. Identifiers, operators, numbers, the
                    interpolations inside those literals, and the order and
                    number of all of them must not. (#133 made this claim.)

A sweep that rewrites an assertion's message is making the second claim and not
the first, and the difference is the whole point of running this: the two modes
disagree on exactly the change that matters, so the mode named in the pull
request is itself part of the evidence.

AND A RENAME MAKES A THIRD CLAIM, WHICH IS WHY IT NEEDS ITS OWN ARGUMENT:

  --renamed old=new   `old` at --base is read as `new` before the two are
                      compared. Repeat it once per identifier renamed.

Given none, this tool is exactly what it was: nothing in code moved. Given some,
the green line no longer says that and must not be read as if it did. It says
*undoing this table makes it so* -- which is a narrower claim than a reader's eye
over a rename diff, and a wider one than the modes above. #213 (a @Suite's name)
and #217 (declarationBody -> bracedBody, and six names with it) were both of this
shape, and each had a throwaway check written for it on the day, because the
claim this tool prints would have been a lie over either of them.

WHAT A RENAME TABLE DOES NOT BUY. Only the renames are forgiven. A sweep that
renamed an identifier *and* changed a number, an operator, a call's arguments or
-- under --comments-only -- a literal cannot be cleared here at all, and should
not be: that is two changes, and this tool only ever answers one question. The
table is applied to code, never to prose: an identifier that also occurs inside a
string literal is not rewritten there, so under --comments-only such a sweep goes
red, and under --words-only the prose was free to move anyway.

A TABLE ENTRY THAT NEVER FIRED IS A PROBLEM. Not a shrug: the table *is* the
claim, so an entry matching nothing means the claim on the screen names a rename
that is not in the diff -- a typo in the flag, a stale line carried from the last
sweep, or the wrong --base. All three read green today and would print a claim
nobody could check.

HOW IT WORKS. Each file is lexed as Swift into code, comments and string
literals -- nested block comments, multiline strings, raw strings with their #
delimiters, and interpolations lexed recursively, since interpolated code is
code and may hold strings of its own. From those pieces a *skeleton* is built:
comments become a single space; literals are kept whole and exact under
--comments-only, or reduced under --words-only to a marker plus the skeletons of
their interpolations, so that prose vanishes while every interpolation, and the
count and order of the literals themselves, survive. The skeleton of the working
tree is compared with the skeleton of the same path at --base.

WHAT THE SKELETON DOES NOT HOLD, SAID PLAINLY. Whitespace between code tokens is
normalised, so reindenting a line or padding an operator passes either mode.
That is not generosity, it is forced: deleting an inline /* comment */ leaves
whitespace behind it, and a check that called that a code change would fire on
the very sweeps it exists to clear. Bare regex literals (/.../) are not lexed;
one containing a quote would be read as a string and reported as unterminated,
which is the loud direction.

WHY IT WILL NOT PRINT A GREEN LINE WHILE BROKEN. Everything below is a problem
and an exit status of 1, never a silent pass:

  - an empty skeleton, even from an empty file -- that is #132's shape exactly
  - a quote left over in code, or a file with literals read as having none
  - a skeleton far shorter than its source (see SHORT_SKELETON)
  - a string, interpolation or block comment that never closes; a single-line
    string that runs off the end of its line
  - --base naming nothing, git failing, the file missing at --base or in the
    tree
  - no .swift to compare at all: comparing nothing and calling it clean is the
    same mistake wearing a file count of zero
  - being run from outside a git repository at all
  - a --renamed entry that matched nothing anywhere (see above)

WHICH TREE IT READS. The one the caller is standing in -- `git rev-parse
--show-toplevel` from the working directory -- and never the one this script
happens to live in. Running a worktree's sweep through another clone's copy of
this script is a fair thing to want, so it is allowed and announced: when the
two differ, the run opens with a `note:` line naming the tree that was read.

Tools/check-ledger-against-git.py takes the same line about a failed fetch: a
silence is not an answer. And the ok line says how many files were compared, and
every file prints its skeleton size and literal count, so that two runs over the
same input can be held against each other by eye. `ok` on its own cannot be.

WHICH HALF OF THE REPORT IS A SAMPLE. The red half is: a file that differs prints
its first few differing runs of words and no more, because a wall of them helps
nobody. So it says how many it held back -- a list that is cut says it was cut.
#202's pull request read "three non-comment changes" because three is what this
printed, and raising the cut found six. The green half is not a sample: a
skeleton either matched end to end or it did not, and the ok line says so in
those words. Reading a census as a sample costs a re-read; reading a sample as a
census stops the reading altogether, and green is the half nobody goes back to.

Output and exit status follow Tools/check-docs.py: one `ok — ...` line and 0, or
`N problem(s):` and 1.
"""
from __future__ import annotations
import argparse
import collections
import difflib
import re
import subprocess
import sys
import urllib.parse
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve()

COMMENTS_ONLY = "comments-only"
WORDS_ONLY = "words-only"

# Build products, not source. A sweep never touches them and they would dwarf the count.
# Matched anywhere in the path, since both sit under a package directory as often as not.
EXCLUDED = (".build/", "DerivedData/")

# The floor under "this skeleton is too small to have been read properly", as
# len(skeleton) over the source's non-whitespace characters *outside comments*. The
# comments have to come out of the denominator: measured against the whole file, the most
# heavily documented sources here score 0.15 while being read perfectly, and a floor set
# under those would catch nothing at all.
#
# Measured over the 143 .swift files in this repository on 2026-09-17: the smallest ratio
# was 1.087 under --comments-only and 0.623 under --words-only (WebSocketFrameTests.swift,
# which is mostly prose).
#
# The two floors are set on different reasoning, which is why they are far apart.
# --comments-only drops nothing but comments, and the skeleton spends a character on the
# space between words and percent-encodes each literal, so a sound reading always lands
# above 1.0; the floor sits at 0.80 to leave room for that accounting rather than on the
# boundary itself. --words-only really does throw prose away, so how far it falls depends
# on how much prose a file carries, and its floor sits at roughly a third of the smallest
# reading here.
#
# The tension, stated rather than hidden: a file that was one enormous literal and little
# else would skeletonise to almost nothing under --words-only and trip this honestly. No
# such file exists here today, and that failure is in the loud direction -- it asks for a
# human, it does not hand anyone a green line.
SHORT_SKELETON = {COMMENTS_ONLY: 0.80, WORDS_ONLY: 0.20}

failures: list[str] = []


def note(check: str, detail: str) -> None:
    failures.append(f"[{check}] {detail}")


# --- the pieces a Swift file is made of ---------------------------------------
@dataclass
class Code:
    text: str


@dataclass
class Comment:
    text: str


@dataclass
class Prose:
    text: str


@dataclass
class Interp:
    segments: list


@dataclass
class Literal:
    parts: list
    raw: str


@dataclass
class Lexer:
    """Cuts a Swift file into code, comments and string literals.

    The cut is a partition: every byte of the source lands in exactly one piece, which is
    what lets the guards below ask whether anything went missing.
    """

    src: str
    path: str
    i: int = 0
    problems: list[str] = field(default_factory=list)
    literals: int = 0

    def complain(self, what: str) -> None:
        line = self.src.count("\n", 0, self.i) + 1
        self.problems.append(f"{self.path}:{line} {what}")

    def scan(self, in_interpolation: bool = False) -> list:
        """Lex forward. Inside an interpolation, stop at the ')' that closes it."""
        src, n = self.src, len(self.src)
        segments: list = []
        code_from = self.i
        depth = 0
        while self.i < n:
            c = src[self.i]
            if in_interpolation and c == "(":
                depth += 1
                self.i += 1
                continue
            if in_interpolation and c == ")":
                if depth == 0:
                    break
                depth -= 1
                self.i += 1
                continue
            if c == "/" and src.startswith("//", self.i):
                segments.append(Code(src[code_from:self.i]))
                segments.append(self.line_comment())
                code_from = self.i
                continue
            if c == "/" and src.startswith("/*", self.i):
                segments.append(Code(src[code_from:self.i]))
                segments.append(self.block_comment())
                code_from = self.i
                continue
            if c == '"' or (c == "#" and self.at_raw_string()):
                segments.append(Code(src[code_from:self.i]))
                segments.append(self.string())
                code_from = self.i
                continue
            self.i += 1
        segments.append(Code(src[code_from:self.i]))
        return segments

    def at_raw_string(self) -> bool:
        # A raw string opens with one or more # and then a quote -- `#"a"#`, or the
        # multiline `#` + three quotes. `#if`, `#available` and `#Preview` open with a
        # letter instead and are code.
        j = self.i
        while j < len(self.src) and self.src[j] == "#":
            j += 1
        return j > self.i and j < len(self.src) and self.src[j] == '"'

    def line_comment(self) -> Comment:
        start = self.i
        end = self.src.find("\n", self.i)
        self.i = len(self.src) if end < 0 else end
        return Comment(self.src[start:self.i])

    def block_comment(self) -> Comment:
        # Swift's block comments nest, so /* /* */ */ closes once, not twice. Counting is
        # the whole difference between reading the rest of the file as comment and not.
        start = self.i
        src, n = self.src, len(self.src)
        self.i += 2
        depth = 1
        while self.i < n:
            if src.startswith("/*", self.i):
                depth += 1
                self.i += 2
                continue
            if src.startswith("*/", self.i):
                depth -= 1
                self.i += 2
                if depth == 0:
                    return Comment(src[start:self.i])
                continue
            self.i += 1
        self.i = n
        self.complain("a block comment never closes; the rest of the file was read as comment")
        return Comment(src[start:self.i])

    def string(self) -> Literal:
        src, n = self.src, len(self.src)
        start = self.i
        pounds = 0
        while src[self.i] == "#":
            pounds += 1
            self.i += 1
        hashes = "#" * pounds
        if src.startswith('"""', self.i):
            opener, multiline = '"""', True
        else:
            opener, multiline = '"', False
        self.i += len(opener)
        closer = opener + hashes
        # In a raw string the escape marker carries the delimiter's hashes: \#n rather
        # than \. A lone backslash there is just a backslash and escapes nothing.
        escape = "\\" + hashes
        parts: list = []
        prose_from = self.i
        while self.i < n:
            if src.startswith(closer, self.i):
                parts.append(Prose(src[prose_from:self.i]))
                self.i += len(closer)
                self.literals += 1
                return Literal(parts, src[start:self.i])
            if src.startswith(escape + "(", self.i):
                parts.append(Prose(src[prose_from:self.i]))
                self.i += len(escape) + 1
                inner = self.scan(in_interpolation=True)
                if self.i < n and src[self.i] == ")":
                    self.i += 1
                else:
                    self.complain("an interpolation never closes")
                parts.append(Interp(inner))
                prose_from = self.i
                continue
            if src.startswith(escape, self.i) and self.i + len(escape) < n:
                self.i += len(escape) + 1
                continue
            if not multiline and src[self.i] == "\n":
                # A single-line string cannot cross a line. Reaching one means the lexer
                # took something that is not a string opener for one, and going on would
                # quietly swallow code as prose.
                self.complain("a single-line string runs off the end of its line")
                break
            self.i += 1
        else:
            self.complain("a string literal never closes; the rest of the file was read as prose")
        parts.append(Prose(src[prose_from:self.i]))
        self.literals += 1
        return Literal(parts, src[start:self.i])


# --- the identifiers the caller says were renamed ------------------------------
# An identifier, because \b only means what it should around one: `[A-Za-z_][A-Za-z0-9_]*`
# has no regex metacharacter in it and no boundary inside it. Anything else -- a phrase, a
# call with its parentheses, a fragment of an operator -- would substitute in places
# nobody could predict from reading the flag, and the flag is the claim.
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


@dataclass
class Renaming:
    """The table, applied to --base's code so that it reads like the working tree's.

    Applied to --base rather than the other way about for one reason: when it does not
    match, the report should say `declarationBody -> bracedBody` in the direction the
    author renamed, so that a reader holds the diff and the report the same way round.

    Every entry is applied in a single pass, so `a=b` and `b=c` in one table cannot chain
    into `a=c`. Two rules applied in sequence depend on which order they were typed in,
    and nothing in a command line says an order was meant.
    """

    table: dict[str, str]
    fired: collections.Counter = field(default_factory=collections.Counter)
    pattern: re.Pattern | None = None

    def __post_init__(self) -> None:
        # Longest first so that an entry is not shadowed by another that is its prefix --
        # \b would not stop `body` from being tried inside `bodyText` were the shorter one
        # first, and although \b does stop it, the order costs nothing and says so.
        names = sorted(self.table, key=len, reverse=True)
        self.pattern = re.compile(r"\b(?:" + "|".join(re.escape(n) for n in names) + r")\b")

    def apply(self, text: str) -> str:
        def once(m: re.Match) -> str:
            self.fired[m.group(0)] += 1
            return self.table[m.group(0)]

        return self.pattern.sub(once, text)

    def never_fired(self) -> list[str]:
        return [old for old in self.table if not self.fired[old]]

    def as_lines(self) -> list[str]:
        return [
            f"{old} -> {new} ({self.fired[old]} occurrence(s) at base)"
            for old, new in sorted(self.table.items())
        ]


# --- from pieces to a skeleton -------------------------------------------------
# A literal is carried as one word with no whitespace in it, so that normalising the
# whitespace around code cannot reach inside a string and quietly forgive a change there.
def one_word(text: str) -> str:
    return urllib.parse.quote(text, safe="")


def emit(segments: list, mode: str, out: list[str], renaming: Renaming | None = None) -> None:
    for s in segments:
        if isinstance(s, Code):
            # Code only. A rename does not reach into prose, and reaching in here would
            # forgive a rewritten message under --comments-only, which is that mode's
            # entire subject.
            out.append(renaming.apply(s.text) if renaming else s.text)
        elif isinstance(s, Comment):
            # A comment separates the tokens on either side of it: `a/*x*/b` is two
            # tokens, not `ab`. Dropping it to nothing would join them.
            out.append(" ")
        elif isinstance(s, Literal):
            if mode == COMMENTS_ONLY:
                out.append(f" str:{one_word(s.raw)} ")
            else:
                # The markers are what makes splitting one literal into two visible: the
                # prose inside vanishes, the brackets around it do not.
                out.append(" str( ")
                for p in s.parts:
                    if isinstance(p, Interp):
                        out.append(" interp( ")
                        emit(p.segments, mode, out, renaming)
                        out.append(" ) ")
                out.append(" ) ")


def count_literals(segments: list) -> int:
    total = 0
    for s in segments:
        if isinstance(s, Literal):
            total += 1
            for p in s.parts:
                if isinstance(p, Interp):
                    total += count_literals(p.segments)
    return total


def quotes_left_in_code(segments: list) -> int:
    total = 0
    for s in segments:
        if isinstance(s, Code):
            total += s.text.count('"')
        elif isinstance(s, Literal):
            for p in s.parts:
                if isinstance(p, Interp):
                    total += quotes_left_in_code(p.segments)
    return total


def quotes_outside_comments(segments: list) -> int:
    """How many of the file's quotes are not part of a comment.

    Nine sources here carry quotes only in their prose -- "a `"` in a sentence" -- and
    counting the file's quotes flat would accuse every one of them of hiding a literal.
    """
    total = 0
    for s in segments:
        if isinstance(s, Code):
            total += s.text.count('"')
        elif isinstance(s, Literal):
            total += s.raw.count('"')
    return total


def uncommented_size(segments: list) -> int:
    """Non-whitespace characters of everything that is not a comment: the floor's denominator."""
    total = 0
    for s in segments:
        if isinstance(s, Code):
            total += len("".join(s.text.split()))
        elif isinstance(s, Literal):
            total += len("".join(s.raw.split()))
    return total


@dataclass
class Skeleton:
    text: str
    literals: int
    problems: list[str]

    @property
    def chunks(self) -> list[str]:
        return self.text.split(" ") if self.text else []


def skeleton_of(source: str, path: str, mode: str, renaming: Renaming | None = None) -> Skeleton:
    lexer = Lexer(source, path)
    segments = lexer.scan()
    out: list[str] = []
    emit(segments, mode, out, renaming)
    text = " ".join("".join(out).split())
    literals = count_literals(segments)
    return Skeleton(text, literals, lexer.problems + guards(path, mode, text, literals, segments))


def guards(path: str, mode: str, text: str, literals: int, segments: list) -> list[str]:
    """Everything that says the reading itself cannot be trusted.

    Kept apart from the lexer, and given the literal count rather than recomputing it, so
    that the self-test can hand it a count the lexer would never produce and watch it
    refuse. In a sound repository none of these ever fires, and a guard that is never
    exercised is a guard nobody knows is broken.
    """
    said: list[str] = []
    if not text:
        # #132's whole failure in one line. An empty file reaches here too, and is worth a
        # human's glance: nothing was compared, so nothing was proved.
        said.append(f"{path} skeletonises to nothing, so a comparison here would prove nothing")
        return said

    stray = quotes_left_in_code(segments)
    if stray:
        said.append(f"{path} leaves {stray} quote(s) outside any literal; the lexer lost its place")
    elif literals == 0 and quotes_outside_comments(segments):
        said.append(f"{path} holds quotes outside its comments but was read as having no string literals")

    dense = uncommented_size(segments)
    if dense and len(text) < SHORT_SKELETON[mode] * dense:
        said.append(
            f"{path} skeletonises to {len(text)} chars from {dense} outside comments, under the "
            f"{SHORT_SKELETON[mode]:.0%} floor for --{mode}; something was swallowed"
        )
    return said


# --- which tree is being asked about ------------------------------------------
# THE TREE IS THE CALLER'S, NEVER THIS SCRIPT'S. Deriving it from __file__ is what the
# first version of this file did, copying the habit from Tools/check-ledger-against-git.py
# -- where it is right, because that tool reads docs/PUNCHLIST.md out of its own clone and
# must ask git about the same one. Here it is exactly wrong: the paths come from the
# caller. Run from a worktree, it read /home/user/mdoro instead, where the sweep had
# already merged and the claim was true, and printed ok over a renamed identifier
# (found 2026-09-17, by re-running the round trip from a worktree).
#
# That is this tool's own subject matter turned on itself: a green line from a check that
# never looked at the thing it was asked about. So the tree is resolved once, from the
# working directory, and handed to everything that needs it.
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


def git(tree: Path, *args: str) -> subprocess.CompletedProcess[str]:
    """Run git in the tree the caller is standing in."""
    return subprocess.run(["git", *args], cwd=tree, capture_output=True, text=True)


def changed_swift(tree: Path, base: str) -> list[str] | None:
    done = git(tree, "diff", "--name-only", base, "--")
    if done.returncode != 0:
        note("git", f"git diff --name-only {base} failed: {(done.stderr or done.stdout).strip()}")
        return None
    return [p for p in done.stdout.split("\n") if p.endswith(".swift") and not skipped(p)]


def skipped(path: str) -> bool:
    return any(x in path for x in EXCLUDED)


def at_base(tree: Path, base: str, path: str) -> str | None:
    done = git(tree, "show", f"{base}:{path}")
    if done.returncode != 0:
        note("git", f"{path} is not at {base} -- a file that is new is not a word that moved")
        return None
    return done.stdout


def in_tree(tree: Path, path: str) -> str | None:
    here = tree / path
    if not here.is_file():
        note("git", f"{path} is named by the diff but is not in the working tree")
        return None
    return here.read_text(encoding="utf-8")


# --- the check ----------------------------------------------------------------
def readable(chunk: str) -> str:
    """Undo the encoding that kept a literal to one word, so a person can read the report."""
    if chunk.startswith("str:"):
        return "str:" + urllib.parse.unquote(chunk[4:]).replace("\n", "⏎")
    return chunk


def narrow(was: str, now: str, width: int = 90) -> tuple[str, str]:
    """Show where two long words part company.

    A whole multiline literal is one word here. Printed from the front and cut to a
    width, two of them differing near the end come out looking identical -- a report that
    says a file changed and then shows two lines the reader cannot tell apart is barely
    better than not saying which file.
    """
    same = 0
    while same < len(was) and same < len(now) and was[same] == now[same]:
        same += 1
    start = max(0, same - 20)

    def window(s: str) -> str:
        return ("…" if start else "") + s[start:start + width] + ("…" if start + width < len(s) else "")

    return window(was), window(now)


def first_differences(before: list[str], after: list[str], limit: int = 3) -> list[str]:
    """The first few differing runs of words -- and, when there are more, how many more.

    The limit is deliberate: a file whose skeleton was rewritten wholesale would otherwise
    print a wall nobody reads, and three is enough to see what kind of change it was. What
    was wrong is that the list stopped without saying it had stopped, so a sample read
    exactly like a complete list -- #202's pull request said "three non-comment changes"
    because three is what came out here, and raising the limit found six (three places,
    each an inserted guard and a rewritten expression). The count was honest about what it
    had printed and silent about what it had not.

    So the runs are gathered first and counted, and the last line names what is missing.
    The limit itself stays where it is: what was needed was not more output, it was output
    that admits its own edge.
    """
    runs = [
        (i1, i2, j1, j2)
        for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, before, after).get_opcodes()
        if tag != "equal"
    ]
    told = []
    for i1, i2, j1, j2 in runs[:limit]:
        was, now = narrow(
            " ".join(readable(c) for c in before[i1:i2]),
            " ".join(readable(c) for c in after[j1:j2]),
        )
        told.append(f"at word {i1}: {was or '(nothing)'}  ->  {now or '(nothing)'}")
    withheld = len(runs) - len(told)
    if withheld:
        told.append(
            f"... and {withheld} more differing run(s) of words, not shown: "
            f"{len(runs)} in all, of which the {len(told)} above are the first"
        )
    return told


def compare(
    tree: Path, path: str, base: str, mode: str, renaming: Renaming | None = None
) -> tuple[int, int] | None:
    """Returns (skeleton size, literal count) when the file could be read at all."""
    there, here = at_base(tree, base, path), in_tree(tree, path)
    if there is None or here is None:
        return None

    was = skeleton_of(there, f"{base}:{path}", mode, renaming)
    now = skeleton_of(here, path, mode)
    for p in was.problems + now.problems:
        note("unreadable", p)
    if was.problems or now.problems:
        return None

    if was.text != now.text:
        moved = "outside comments and prose" if mode == WORDS_ONLY else "outside comments"
        if renaming:
            # Said on the red line too: a reader looking at a difference here needs to know
            # the left-hand side has already had the table applied to it, or they will go
            # hunting for the rename in it.
            moved += " even with the rename table applied"
        note("moved", f"{path} differs from {base} {moved}:")
        for line in first_differences(was.chunks, now.chunks):
            note("moved", f"    {line}")
    return len(now.text), now.literals


def report(
    read: list[tuple[str, int, int]], base: str, mode: str, renaming: Renaming | None = None
) -> int:
    for path, size, literals in read:
        print(f"  {path}  —  {size} skeleton chars, {literals} literal(s)")
    if read:
        print()
    if failures:
        print(f"{len(failures)} problem(s):\n")
        for f in failures:
            print(f"  {f}")
        return 1
    moved = "only words moved" if mode == WORDS_ONLY else "only comments moved"
    if renaming:
        # A DIFFERENT CLAIM, SO A DIFFERENT SENTENCE. Printing the line below over a rename
        # sweep would be the tool telling the lie it exists to catch: nothing about the
        # identifiers held still, and `only comments moved` says they did. Both #213 and
        # #217 were renames, and both had a throwaway check written for them rather than
        # this one, for exactly that reason.
        print(
            f"ok — {len(read)} file(s) compared against {base}; once the {len(renaming.table)} "
            f"rename(s) below were applied to {base}, {moved} — each skeleton matched end to "
            f"end, all of it and not a sample of it"
        )
        print("\n  the claim is NOT that nothing but words moved. It is that undoing this makes it so:")
        for line in renaming.as_lines():
            print(f"    {line}")
        print(
            "\n  and nothing else was forgiven: a sweep that also moved a number, an operator, an\n"
            "  argument or a literal cannot come out green here, and is two changes rather than one."
        )
        return 0
    # Said out loud because the red half of this report *is* a sample (see first_differences)
    # and the green half is not, and nothing in `ok — 15 file(s) compared` told the two
    # apart. A reader who suspects green of being a sample re-reads the files by hand; the
    # question came up over #202, where the red half had quietly been one.
    print(
        f"ok — {len(read)} file(s) compared against {base}, {moved} — "
        f"each skeleton matched end to end, all of it and not a sample of it"
    )
    return 0


def rename_table(parser: argparse.ArgumentParser, given: list[str]) -> Renaming | None:
    """Turn the repeated --renamed flags into one table, or refuse them.

    Refused rather than noted, because these are the caller's words and not the
    repository's: a misspelt flag is a usage error, and answering it with a red run about
    the Swift would put the blame in the wrong place.
    """
    table: dict[str, str] = {}
    for entry in given:
        old, sep, new = entry.partition("=")
        if not sep:
            parser.error(f"--renamed {entry} is not old=new")
        if not IDENTIFIER.match(old) or not IDENTIFIER.match(new):
            parser.error(f"--renamed {entry}: both sides must be Swift identifiers")
        if old == new:
            parser.error(f"--renamed {entry} renames nothing")
        if old in table:
            parser.error(f"--renamed names {old} twice, as {table[old]} and as {new}")
        table[old] = new
    return Renaming(table) if table else None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Ask whether the Swift in the working tree moved anything but words.",
    )
    claim = parser.add_mutually_exclusive_group(required=True)
    claim.add_argument(
        "--comments-only",
        dest="mode",
        action="store_const",
        const=COMMENTS_ONLY,
        help="comments and blank lines may move; everything else, string literals included, may not",
    )
    claim.add_argument(
        "--words-only",
        dest="mode",
        action="store_const",
        const=WORDS_ONLY,
        help="comments, blank lines and the prose inside string literals may move; nothing else",
    )
    parser.add_argument("--base", default="origin/main", help="the ref to compare against (default: origin/main)")
    parser.add_argument(
        "--renamed",
        metavar="OLD=NEW",
        action="append",
        default=[],
        help=(
            "read the identifier OLD at --base as NEW before comparing; repeat once per rename. "
            "Given any, the green line claims only that undoing this table makes the mode's claim "
            "true -- nothing else is forgiven, so a sweep that renamed and also changed a number, "
            "an operator or a literal cannot be cleared here. An entry that matches nothing is a "
            "problem, not a shrug"
        ),
    )
    parser.add_argument("paths", nargs="*", help="files to compare (default: the .swift the diff names)")
    args = parser.parse_args()
    renaming = rename_table(parser, args.renamed)

    tree = toplevel(Path.cwd())
    if tree is None:
        note("git", f"{Path.cwd()} is not inside a git repository, so there is nothing to compare against")
        return report([], args.base, args.mode)
    say_which_tree(tree)

    # Asked of that tree, not of this script's: a worktree and the clone it was made from
    # can hold different refs, and the wrong one answers confidently.
    if git(tree, "rev-parse", "--verify", "--quiet", f"{args.base}^{{commit}}").returncode != 0:
        # Nothing can be compared against a ref that is not here, and saying so in the
        # same voice as an answer is how #132 read.
        note("git", f"--base {args.base} names no commit in {tree} -- fetch it, or name another")
        return report([], args.base, args.mode)

    if args.paths:
        paths = []
        for given in args.paths:
            # Relative to where the caller is standing, which is how they typed it.
            try:
                paths.append(str(Path(given).resolve().relative_to(tree)))
            except ValueError:
                note("scope", f"{given} is not inside {tree}, the repository this was run from")
                continue
        paths = [p for p in paths if not skipped(p)]
    else:
        found = changed_swift(tree, args.base)
        if found is None:
            return report([], args.base, args.mode)
        paths = found

    if not paths:
        # Comparing nothing and calling it clean is the same mistake in another shape.
        note("scope", f"no .swift files to compare against {args.base}; there is nothing here to prove")
        return report([], args.base, args.mode)

    read = []
    for path in paths:
        got = compare(tree, path, args.base, args.mode, renaming)
        if got is not None:
            read.append((path, *got))

    # Asked after every file, since a rename may live in one file of many. The table is the
    # claim, so an entry that matched nothing means the claim names a rename that is not
    # there -- a typo in the flag, a line left over from the last sweep, or the wrong --base.
    if renaming:
        for old in renaming.never_fired():
            note(
                "renamed",
                f"--renamed {old}={renaming.table[old]} matched nothing at {args.base} in the "
                f"{len(read)} file(s) read, so the green line would claim a rename that is not here",
            )
    return report(read, args.base, args.mode, renaming)


if __name__ == "__main__":
    sys.exit(main())
