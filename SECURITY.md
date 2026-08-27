# Security

Mdoro talks to one device on your local network and to nothing else. There is no
server, no account and no telemetry.

## How the two devices trust each other

- The Mac advertises `_mdoro._tcp` over Bonjour and listens on a local port.
- Pairing is deliberate: the Mac shows a six-digit code, valid for three minutes,
  and ends after five wrong attempts.
- On success the iPhone receives a device token and stores it in the Keychain.
  Later connections use that token.
- **One iPhone at a time.** If a second device presents itself while one is
  connected, the Mac asks you before letting it in, and denies it after 60 seconds
  of no answer.
- Nothing is exposed beyond the local network, and the apps make no other outbound
  connections.

## What is stored

| Where | What |
| :---- | :---- |
| Mac, app container | Timer state, settings, presets, and security-scoped bookmarks for the folders you picked |
| Mac, `~/Library/Logs/Mdoro` | The diagnostic log, which contains no task names, file paths or device names |
| iPhone, Keychain | The device token issued at pairing |
| iPhone, app storage | The last state snapshot received, so the app can show something while offline |

Your task file is opened read-only, and the bookmark for it is created with
`securityScopeAllowOnlyReadAccess` - the sandbox enforces it, not just the code.

## Reporting a vulnerability

Open an issue. If you would rather not do that in public, say so in an issue
without the details and we will find another way.
