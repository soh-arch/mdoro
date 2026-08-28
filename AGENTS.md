# AGENTS.md — Mdoro

Instructions for AI coding agents working in this repository.
Humans: `README.md` is the place to start. Contributors' agents: read this file first.

## What Mdoro is

A focus-session timer for macOS and iOS that stays inside your LAN.
The Mac holds the timer state; the iPhone shows it and drives it.
Mdoro reads a Markdown task file **read-only** and appends finished sessions to a log file.
No cloud, no account, no telemetry.

- **Mac**: SwiftUI, macOS 26+. Menu bar item plus a main window. WebSocket server.
- **iPhone**: SwiftUI, iOS 26+. Display and control. Live Activity.
- **Transport**: Network.framework — Bonjour `_mdoro._tcp`, WebSocket, JSON.

## Three rules that are never relaxed

1. **Never write to the task file.** Sessions are appended to the log file only; existing
   lines are never rewritten or deleted. The security-scoped bookmark for the task file is
   created with `securityScopeAllowOnlyReadAccess`, so the OS enforces it too.
2. **The Mac owns the state.** The iPhone may interpolate the countdown for display, but it
   must never decide that a session has ended. Loop counting and log writing happen on the Mac.
3. **Time is absolute.** Remaining seconds are never synced. The Mac broadcasts `sessionEndAt`
   and each device derives the rest — a monotonic clock for the countdown, the wall clock for
   generating `sessionEndAt` and for log timestamps.

Breaking any of these damages either the user's own files or the consistency of the state.

## Build and test

The shared package is where the rules live, and it builds without Xcode. Start there.

```bash
(cd Packages/MdoroCore && swift test)
```

macOS app:

```bash
set -o pipefail && xcodebuild -project ./PomodoroMac/PomodoroMac.xcodeproj -scheme MdoroMac -destination 'platform=macOS' build | xcbeautify
```

iOS app on the simulator:

```bash
set -o pipefail && xcodebuild -project ./PomodoroMac/PomodoroMac.xcodeproj -scheme MdoroiOS -destination 'platform=iOS Simulator,name=iPhone 17' build | xcbeautify
```

Xcode 26.6 / Swift 6.3. Signing uses a personal team, so set your own `DEVELOPMENT_TEAM`
in Xcode before building the apps. Local notifications need no capability, but they do need
a valid signature — an unsigned build will not deliver them.

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

- **Code comments are English**, and short. Do not explain what the code already says.
  No commented-out code, no notes about what used to be there.
- Cite the requirement ID that justifies non-obvious behaviour:
  `// REQ-TIM-035: the only way out of FINISHED is IDLE`.
- Every string the app itself produces is English. Strings read from the user's files and
  strings the user typed are passed through untouched — never translated, never normalised.

## Requirements and decisions

`docs/SPEC.md` is the single source of truth for what Mdoro does: 242 requirements, each with
an ID like `REQ-TIM-035`. `docs/decisions/` records why things were decided the way they were.

**Those documents are written in Japanese.** You do not need to read Japanese to contribute —
**the requirement IDs are the shared language.** Cite the ID your change rests on and a
maintainer can check it. If a requirement seems wrong, say so; do not quietly work around it.

If the spec allows two reasonable readings and the decision records do not settle it, **stop
and ask.** Do not guess. A guess that ships becomes a requirement nobody chose.

## Pull requests

- Branch per change. **One PR does one thing.**
- Conventional Commits, in English, citing the requirement ID.
- `swift test` must pass. CI runs it on every pull request.
- A human merges. Nothing lands on `main` directly.

## Out of scope

These will not be accepted. Please do not open PRs for them.

- Cloud sync, accounts, push notifications
- Ads, in-app purchases, analytics or any usage tracking
- UI languages other than English
- Editing the task file — creating and completing tasks belongs to the user's Markdown editor
- iPad, Apple Watch, multiple simultaneous clients, connections from outside the LAN
