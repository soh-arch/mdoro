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

## What the local network can see

**The connection between the Mac and the iPhone is not encrypted.** There is no TLS on it
today. On a network where you are not alone - a shared office, a cafe, a flat with other
people's devices on the same Wi-Fi - somebody able to watch the traffic can read:

- **your device token**, which is what proves a paired iPhone is yours;
- **the full path of your task file and of your log folder**;
- **every task in the file**, headings and text, as it is sent to the phone.

The Mac advertises itself over Bonjour under **a name you choose**, which is `Mdoro` until you
change it in Settings. Your Mac's own name is not sent - it used to be, and for most people that
is their own name. It also answers an unauthenticated `GET /info` with the name you chose and
with whether pairing is currently open.

None of this leaves the local network. All of it is visible on it. **Encrypting the link is
planned, and it is not done** - so if you use Mdoro on a network you do not trust, know what
is on the wire.

## What is stored

| Where | What |
| :---- | :---- |
| Mac, app container | Timer state, settings, presets, and security-scoped bookmarks for the folders you picked |
| Mac, `~/Library/Logs/Mdoro` | The diagnostic log, which contains no task names, file paths or device names |
| Mac, app container | A file holding this Mac's id, which is what a paired iPhone recognises it by |
| Mac, Keychain | The tokens this Mac has issued, each with the name of the device and the date |
| iPhone, Keychain | The device token issued at pairing, filed under the Mac's id |
| iPhone, app storage | The last state snapshot received, so the app can show something while offline |

Your task file is opened read-only, and the bookmark for it is created with
`securityScopeAllowOnlyReadAccess`, so nothing can be written **through that bookmark**.

That is not the whole of it, and it would be dishonest to leave it there. If you keep the log
in the same folder as the task file - which is what this README suggests - then Mdoro also holds
a read-write bookmark for that folder, and the read-only one is no longer the only way in. What
keeps the task file untouched is that **no code path writes to it**, and that every write checks
first that its destination is not the task file. That is a rule the code follows, not a wall the
system puts up.

## Reporting a vulnerability

Open an issue. If you would rather not do that in public, say so in an issue
without the details and we will find another way.
