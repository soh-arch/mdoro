# AGENTS.md — Mdoro

Instructions for AI coding agents working in this repository.
Humans: `README.md` is the place to start. Contributors' agents: read this file first.

## What Mdoro is

A focus-session timer for macOS and iOS that stays inside your LAN.
The Mac holds the timer state; the iPhone shows it and drives it.
Mdoro reads a Markdown task file **read-only** and records finished sessions in a log file,
inserting lines and never rewriting the ones already there.
No cloud, no account, no telemetry.

- **Mac**: SwiftUI, macOS 26+. Menu bar item plus a main window. WebSocket server.
- **iPhone**: SwiftUI, iOS 26+. Display and control. Live Activity.
- **Transport**: Network.framework — Bonjour `_mdoro._tcp`, WebSocket, JSON.

## Three rules that are never relaxed

1. **Never write to the task file.** Sessions go into the log file by insertion only —
   existing lines are never rewritten or deleted, and the insertion point is not always
   the end of the file, because entries belong under the heading for their logical day. The bookmark for the task file is created with
   `securityScopeAllowOnlyReadAccess`, which stops writes **through that bookmark** - but the log
   folder is bookmarked read-write, and it is often the same folder. What actually holds is that
   no code path writes to the task file, and `LogWriter.validate` refuses a destination equal to
   it. Treat it as a rule to keep, not a wall that will catch you.
2. **The Mac owns the state.** The iPhone may interpolate the countdown for display, but it
   must never decide that a session has ended. Loop counting and log writing happen on the Mac.
3. **Time is absolute.** Remaining seconds are never synced. The Mac broadcasts `sessionEndAt`
   and each device derives the rest — a monotonic clock for the countdown, the wall clock for
   generating `sessionEndAt` and for log timestamps.

Breaking any of these damages either the user's own files or the consistency of the state.

## Build and test

The shared package is where the rules live, and it builds without Xcode. Start there.
**It targets macOS 26 / iOS 26**, so `swift test` needs macOS 26 or later even though it
needs no Xcode project.

```bash
(cd Packages/MdoroCore && swift test)
```

**`xcbeautify` is optional.** It only makes the log readable; the build is the same without
it. Install it with `brew install xcbeautify`, or drop the `| xcbeautify` from these
commands — a fresh machine does not have it, and leaving the pipe in gives
`command not found`, which is the exit status of the whole command because xcbeautify is
its last stage. (`set -o pipefail` is there for the other direction: a failing
`xcodebuild` behind a formatter that exits cleanly.)

macOS app:

```bash
set -o pipefail && xcodebuild -project ./PomodoroMac/PomodoroMac.xcodeproj -scheme MdoroMac -destination 'platform=macOS' build | xcbeautify
```

iOS app on the simulator:

```bash
set -o pipefail && xcodebuild -project ./PomodoroMac/PomodoroMac.xcodeproj -scheme MdoroiOS -destination 'platform=iOS Simulator,name=iPhone 17' build | xcbeautify
```

**Always pass `-destination`.** Without it, `xcodebuild` picks a generic iOS device, builds for
`Debug-iphoneos`, and installs onto whatever iPhone is plugged in — replacing the app on someone's
own phone. Nothing in the command says that is what happened.

**The Simulator cannot exercise the connection.** It does not implement local network privacy
at all, so the permission prompt this app depends on never appears and never denies — Apple's
own guidance is to test that behaviour on a real device (`docs/PLATFORM.md`). The Simulator
builds and runs the UI; **pairing a Mac and an iPhone has to happen on hardware.**

Xcode 26.6 / Swift 6.3. To build the apps, put your signing team in
`Config/Signing.local.xcconfig`, which git ignores:

```
DEVELOPMENT_TEAM = ABCDE12345
```

Nothing else is needed, and nothing you do there shows up in a diff. Without a team the apps
still build and run locally — macOS signs them ad-hoc, which is enough to launch and not enough
to notify.

**Set a team before you touch anything to do with notifications.** Local notifications need no
capability, but they do need a real signature, and an ad-hoc build fails in a way that looks
like nothing at all: `requestAuthorization` never resolves the permission, which stays
`notDetermined`; `add()` reports success and delivers nothing; and the app never appears in
System Settings, so there is no setting to go and check. If you are staring at a silent build,
run `codesign -dv` on the bundle — `Signature=adhoc` with an `Identifier` that does not match
the bundle ID is this and nothing else.

## Where code goes

- **Anything shared goes in `MdoroCore`.** The state machine, the wire protocol and the data
  models must not exist twice, once for the Mac and once for iOS (REQ-PRT-001).
- **Never edit `.xcodeproj` by hand.** The targets use buildable folders: dropping a `.swift`
  file on disk is enough. Changes that a folder cannot express — capabilities, build settings,
  signing, linking a target — are a human's job in Xcode. Stop and say so.
- **No colour literals in views.** Refer to roles: `sessionFocus`, `warning`, `danger`,
  `textPrimary`. The palette is generated and contrast-tested.
- Folder names still say `Pomodoro`; target names say `Mdoro`. That is known, not a mistake
  to fix in passing.

## Style

- **Everything this project ships is written in English**: identifiers, code comments, and
  every string the app itself produces. Strings read from the user's files and strings the
  user typed are passed through untouched — never translated, never normalised.
- **The language you write your commits and pull requests in is your own.** Cite the
  requirement ID; the words around it are yours.
- Keep comments short. Do not explain what the code already says. No commented-out code,
  no notes about what used to be there.
- Cite the requirement ID that justifies non-obvious behaviour:
  `// REQ-TIM-035: the only way out of FINISHED is IDLE`.
- **A comment says what the clause requires, not what the OS does.** Platform facts live in
  `docs/PLATFORM.md`, with the research behind them in `docs/platform/`. State one in a comment
  only where leaving it out would mislead — an API whose name suggests a wider effect than it
  has — and point at `docs/PLATFORM.md` when you do. An unsourced assertion about the OS is
  what goes stale without anyone noticing.

## Requirements and decisions

`docs/SPEC.md` is the single source of truth for what Mdoro does: 243 requirements, each with
an ID like `REQ-TIM-035`. `docs/decisions/` records why things were decided the way they were.

**Those documents are written in Japanese.** You do not need to read Japanese to contribute —
**the requirement IDs are the shared language.** Cite the ID your change rests on and a
maintainer can check it. If a requirement seems wrong, say so; do not quietly work around it.

If the spec allows two reasonable readings and the decision records do not settle it, **stop
and ask.** Do not guess. A guess that ships becomes a requirement nobody chose.

## Pull requests

- Branch per change. **One PR does one thing.**
- **Conventional Commits.** Subject line is `type: summary`. The types in use are `feat`,
  `fix`, `docs`, `refactor`, `test`, `chore`, `build`. **No scope** — this repo has never
  used one. Write the summary as a statement, not a label.
- **Name the requirement ID your change rests on**, in the commit body. A `Refs REQ-TIM-035`
  trailer at the end keeps the history greppable. This is the part that matters: it is how a
  maintainer checks a change against `docs/SPEC.md` without reconstructing your reasoning,
  and `docs/` is in Japanese, so the ID may be the only thing you and the maintainer both read.
- `swift test` must pass. CI runs it on every pull request.
- A human merges. Nothing lands on `main` directly.

## Out of scope

These will not be accepted. Please do not open PRs for them.

- Cloud sync, accounts, push notifications
- Ads, in-app purchases, analytics or any usage tracking
- UI languages other than English
- Editing the task file — creating and completing tasks belongs to the user's Markdown editor
- iPad, Apple Watch, multiple simultaneous clients, connections from outside the LAN
