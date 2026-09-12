# A-1 検証報告

## 1. 作った一覧・表

対象実装: `/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/MdoroServer.swift`（Mac゠サーバー側の受信ディスパッチ）、および `/tmp/stage4-clean/PomodoroMac/PomodoroiOS/Client/MdoroClient.swift`（iPhone゠クライアント側）。

`MdoroServer.handle(_:from:)`（`MdoroServer.swift:222-250`）の実装は、受信した `source: NWConnection` を **`.command` と `.requestSnapshot` の2種類でしか** `source === connection`（＝hello が成立し `welcome` を返した後の、既に認証済みの接続）と照合していない。`.hello` は認証処理そのものなので当然として、**`.timeSyncPing` と `.heartbeat` は `source` の照合が一切無く、`hello` の成立前でも無条件に処理される**。

```swift
// MdoroServer.swift:226-249
switch envelope.body {
case let .hello(payload):
    handleHello(payload, from: source)

case let .timeSyncPing(payload):
    // REQ-COM-007: t2 is when it arrived, t3 is when the answer was sent.
    let t2 = Date()
    send(.timeSyncPong(TimeSyncPayload(t1: payload.t1, t2: t2, t3: Date())), to: source)   // ← source照合なし

case .heartbeat:
    // REQ-COM-005: 10.2 has no Server → Client heartbeat, so nothing is sent back.
    // The client side judges liveness from the WebSocket ping/pong.
    lastHeartbeatAt = Date()                                                                // ← source照合なし

case let .command(payload):
    guard source === connection else { return }                                             // ← ここは照合あり
    ...

case .requestSnapshot:
    guard source === connection, let snapshot = callbacks?.provideSnapshot() else { return } // ← ここは照合あり
    send(.stateSnapshot(snapshot), to: source)
}
```

また `accept(_:)` → `receive(on:)`（`MdoroServer.swift:174-209`）は接続を受け付けた瞬間から `receiveMessage` ループを開始しており、**「最初のメッセージは `hello` でなければならない」という順序制約はコード上どこにも無い**。`MessageCoder.decodeClient`（`Messages.swift:205-218`）も `type` フィールドだけでディスパッチ先を決めており、`hello` が成立していることも `protocolVersion` の一致も見ていない。

これらを根拠に、TCP/WebSocket が開いてから線が閉じるまでに**実際に流れうるメッセージ**を、方向・順序つきで一覧にする。

| # | 方向 | type | 認証状態（`hello`成立可否） | 根拠 |
| :-- | :-- | :-- | :-- | :-- |
| 1 | Mac←iPhone | `timeSyncPing` | **未成立**（`hello` 未送信でも可） | `MdoroServer.swift:230-233` に `source` 照合なし |
| 2 | Mac→iPhone | `timeSyncPong` | **未成立のまま応答が返る** | 同上。`send(..., to: source)` で無条件応答 |
| 3 | Mac←iPhone | `heartbeat` | **未成立**（`hello` 未送信でも可） | `MdoroServer.swift:235-238` に `source` 照合なし |
| 4 | （1〜3 は任意回・任意順に反復可能） | — | 未成立のまま | `receive(on:)` は毎回 `handle` を呼ぶだけで順序を強制しない（`MdoroServer.swift:191-209`） |
| 5 | Mac←iPhone | `hello`（`protocolVersion` 不一致） | 認証試行 | `Pairing.swift:121-125` |
| 6 | Mac→iPhone | `authFailed` | 拒否・直後に接続を閉じる（`sendThenClose`） | `MdoroServer.swift:288-298`, `364-366` |

※ 5→6 の1往復だけが起きる「素直な」経路（参照実装の `MdoroClient.sendHello()` が `.ready` 直後に `hello` を送るケース）も**当然成立する**が、それは受信ハンドラが許す最大集合の中の一例にすぎない。受信ハンドラ自体は 1〜4 の `timeSyncPing`/`timeSyncPong`/`heartbeat` のやり取りを、`hello` の成立可否と無関係に何度でも許す。

## 2. 問いへの答え

**成立しない。** 「版の違う2台が唯一やり取りするのは `hello` とその拒否までである」という条文の一節は、実装のこの受信ハンドラを見る限り事実として成立しない。

- `hello` とその拒否（`authFailed`）の2本だけではなく、**`timeSyncPing` / `timeSyncPong` / `heartbeat` の3種が、`hello` の成立（＝認証）を経ずに実際にやり取りされうる。**
- 具体的には、Mac側の `MdoroServer.handle(_:from:)` が `.timeSyncPing` と `.heartbeat` を処理する分岐に `source === connection`（＝既に `welcome` を返した相手かどうか）の確認が無い。`.command` と `.requestSnapshot` にはこの確認があるのに、この2種だけ抜けている。
- さらに、受信ループ（`receive(on:)`）は「最初に `hello` を受け取るまで他のメッセージ種別を処理しない」という順序制約を持たない。したがって、版の違う相手（あるいは `hello` を送らない、送るのを遅らせる相手）が接続直後に `timeSyncPing` を送れば、Mac は無条件に `timeSyncPong` を返す。これは REQ-COM-007「接続確立時およびハートビートごとに…オフセットを測定する」の「接続確立」を額面通り読むなら、**まだ接続（＝認証済み接続）が確立していない時点でも時刻同期が成立してしまう**ことを意味する。

したがって、当該一覧は `hello` と拒否の2本だけでは説明できず、条文の「唯一」という言い切りは実装との整合が取れていない。

## 3. 指摘（根拠ファイル・行・引用）

- **`/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/MdoroServer.swift:230-238`**
  ```swift
  case let .timeSyncPing(payload):
      let t2 = Date()
      send(.timeSyncPong(TimeSyncPayload(t1: payload.t1, t2: t2, t3: Date())), to: source)

  case .heartbeat:
      lastHeartbeatAt = Date()
  ```
  → `.command`（241行目 `guard source === connection else { return }`）や `.requestSnapshot`（246行目 同様のguard）と異なり、この2分岐だけ「`source` が現在の認証済み接続と同一か」を確認していない。`hello` を送っていない、あるいは `hello` が拒否された（拒否メッセージ送出前の）相手からの `timeSyncPing`/`heartbeat` も同じ経路で処理される。

- **`/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/MdoroServer.swift:191-209`（`receive(on:)`）**
  受信メッセージの型に応じた順序制約（「最初は `hello` でなければならない」等）が存在しない。`accept()` → `receive(on:)` は接続直後から任意の既知メッセージ型を受理する。

- **`/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/Messages.swift:205-218`（`MessageCoder.decodeClient`）**
  デコードは `type` 文字列のみで分岐し、`hello` の成立や `protocolVersion` の一致をここでも確認していない。

これらより、A-1 で問われている「認証前・接続確定前に応答してしまう種別」が **`timeSyncPing`（応答は `timeSyncPong`）と `heartbeat`** の2種、実在する。

## 4. 実際に打ったコマンドと出力

```
$ find /tmp/stage4-clean -type f -name "*.swift" | xargs grep -l "hello\|handleMessage\|receiveMessage\|case .hello\|decode" 2>/dev/null | head -50
/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/MdoroServer.swift
/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/DeviceTokenStore.swift
/tmp/stage4-clean/PomodoroMac/PomodoroMac/AppModel.swift
/tmp/stage4-clean/PomodoroMac/PomodoroMac/Services/VaultFileAccess.swift
/tmp/stage4-clean/PomodoroMac/PomodoroiOSTests/BrokenMessageWiringTests.swift
/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/ServerRefusalLogTests.swift
/tmp/stage4-clean/PomodoroMac/PomodoroiOS/Client/WebSocketLink.swift
/tmp/stage4-clean/PomodoroMac/PomodoroiOS/Client/MdoroClient.swift
/tmp/stage4-clean/PomodoroMac/PomodoroiOS/ClientModel.swift
/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/IdentityTests.swift
/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/MdoroCoreTests.swift
/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/PersistenceTests.swift
/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/ProtocolTests.swift
/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/PairingTests.swift
/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/FailuresThatReachSomeoneTests.swift
/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/ProtocolTypes.swift
/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/Pairing.swift
/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/Messages.swift
/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/ServerID.swift
/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/PreNotification.swift
/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Persistence/ServerIdentityFile.swift
/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Persistence/PersistedState.swift
/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Persistence/FileStateStore.swift
/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/TimerContext.swift
/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Tasks/TaskParser.swift
```

```
$ grep -rn "timeSyncPing\|source === connection\|before.*hello\|unauthenticated" \
    /tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/ProtocolTests.swift \
    /tmp/stage4-clean/PomodoroMac/PomodoroMacTests/*.swift 2>/dev/null | head -60
/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/ProtocolTests.swift:23:            .timeSyncPing(TimeSyncPayload(t1: now)),
```
（`hello` 成立前の `timeSyncPing`/`heartbeat` 拒否を確かめる専用テストは見当たらなかった。）

```
$ ls /tmp/stage4-clean/PomodoroMac/PomodoroMacTests/*.swift
DiagnosticLogTests.swift  IdleSleepTests.swift  KeychainRecordPolicyTests.swift
ListenerFoldingTests.swift  RecordedNotifications.swift  RecordedSleepGuard.swift
RevocationTests.swift  ServerPresenceWiringTests.swift  ServerRefusalLogTests.swift
StayingOffTheAirTests.swift  TestHostDetectionTests.swift  UnsetLogDestinationTests.swift
```

---

## 割り当ての外で気づいたこと（別項・未実装/未起票）

- `docs`側の `error.code` 一覧（10.2, material-B.md:997）は `protocolVersionMismatch` を **`error`** メッセージのコードとして掲げ、REQ-PRT-004 の発生元としている。一方 `authFailed.code` 一覧（material-B.md:1001）にはこのコードが無い。実装（`Pairing.swift:121-125`）は `protocolVersion` 不一致時に `.reject(.unknownDeviceToken)` を返しており、`hello`/`welcome` の拒否（＝`authFailed`）経路でバージョン不一致を報告している。つまり「REQ-PRT-004 由来のコードは `protocolVersionMismatch` である」という条文と、「バージョン不一致は `unknownDeviceToken` として `authFailed` される」という実装・および `authFailed.code` 一覧との間に食い違いがある（提案・裁定はしない。事実の指摘のみ）。

---

## 開いたファイル一覧

- `/tmp/claude-0/-home-user-mdoro/fe6ab0b8-83a6-51e9-a6bc-915163f1f996/scratchpad/diff-B.md`（read）
- `/tmp/claude-0/-home-user-mdoro/fe6ab0b8-83a6-51e9-a6bc-915163f1f996/scratchpad/material-B.md`（read, offset 0/1-435, offset 905-1004）
- `/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/MdoroServer.swift`（read）
- `/tmp/stage4-clean/PomodoroMac/PomodoroiOS/Client/MdoroClient.swift`（read）
- `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/Messages.swift`（read）
- `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/Pairing.swift`（read, offset 90-149）
- `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/ProtocolTypes.swift`（read, offset 130-209）
- `/tmp/stage4-clean`（find, `-name "*.swift"` 全体）
- 以下（grep -l 経由で内容照合、非フルread）:
  `/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/DeviceTokenStore.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMac/AppModel.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMac/Services/VaultFileAccess.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroiOSTests/BrokenMessageWiringTests.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/ServerRefusalLogTests.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroiOS/Client/WebSocketLink.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroiOS/ClientModel.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/IdentityTests.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/MdoroCoreTests.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/PersistenceTests.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/ProtocolTests.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/PairingTests.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/FailuresThatReachSomeoneTests.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/ServerID.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/PreNotification.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Persistence/ServerIdentityFile.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Persistence/PersistedState.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Persistence/FileStateStore.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/TimerContext.swift`
  `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Tasks/TaskParser.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/DiagnosticLogTests.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/IdleSleepTests.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/KeychainRecordPolicyTests.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/ListenerFoldingTests.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/RecordedNotifications.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/RecordedSleepGuard.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/RevocationTests.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/ServerPresenceWiringTests.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/StayingOffTheAirTests.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/TestHostDetectionTests.swift`
  `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/UnsetLogDestinationTests.swift`
- `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests`（ls）