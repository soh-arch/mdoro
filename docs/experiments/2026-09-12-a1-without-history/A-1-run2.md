## A-1 の検証結果

### 作った一覧（版の違う2台の間で実際に流れうるメッセージ）

**通常経路（hello が accept されるまで）**

| # | 方向 | 種別 | 典拠 |
|---|---|---|---|
| 1 | iPhone→Mac | `hello` | Messages.swift:130, MdoroClient.swift:147 |
| 2a | Mac→iPhone | `welcome`（accept） | MdoroServer.swift:270 |
| 2b | Mac→iPhone | `authFailed`（reject、直後に接続クローズ） | MdoroServer.swift:297 (`sendThenClose`) |
| 2c | (accept 待ち) | 何も送られない。60秒 or ユーザー判断まで保留 | MdoroServer.swift:281-286, 311-319 |
| 3 | Mac→iPhone | `stateSnapshot`（accept 直後） | MdoroServer.swift:278 |
| 4 | Mac→iPhone | `taskList`（accept 直後、任意） | MdoroServer.swift:279 |

**接続確立後に反復して流れるもの**

| # | 方向 | 種別 |
|---|---|---|
| 5 | iPhone→Mac | `heartbeat`（5秒毎） |
| 6 | iPhone→Mac | `timeSyncPing`（5秒毎） |
| 7 | Mac→iPhone | `timeSyncPong`（6の返信） |
| 8 | iPhone→Mac | `command` |
| 9 | Mac→iPhone | `stateSnapshot` / `taskList`（コマンド処理後の broadcast） |
| 10 | iPhone→Mac | `requestSnapshot` |
| 11 | Mac→iPhone | `stateSnapshot`（10の返信） |
| 12 | Mac→iPhone | `error` |
| — | Mac→iPhone | `sessionEvent`（型は定義されているが、本番コードに送信箇所が見当たらない。軸外として末尾に記載） |

**「hello が成立する前」に実際に流れる組（今回の焦点）**

| # | 方向 | 種別 | hello の成立要否 |
|---|---|---|---|
| A | iPhone→Mac | `timeSyncPing` | 不要（`Authenticator.authenticate` を一切通らない） |
| B | Mac→iPhone | `timeSyncPong`（Aへの返信） | 不要 |
| C | iPhone→Mac | `heartbeat` | 不要（一方向。`lastHeartbeatAt` を無条件更新） |

---

### 問いへの答え

**「唯一やり取りするのは `hello` とその拒否の2本だけか」→ 事実として成立しない。**

`timeSyncPing`/`timeSyncPong` の往復と、`heartbeat` の片道は、`hello` が成立している（＝プロトコル版が一致し、認証が accept されている）ことを一切要求されずに実際に流れる。

### 根拠

`/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/MdoroServer.swift` の受信ハンドラ:

```
222  private func handle(_ data: Data, from source: NWConnection) {
223      // REQ-ERR-009: a broken message is thrown away and the connection is kept.
224      guard let envelope = try? MessageCoder.decodeClient(data) else { return }
225
226      switch envelope.body {
227      case let .hello(payload):
228          handleHello(payload, from: source)
229
230      case let .timeSyncPing(payload):
231          // REQ-COM-007: t2 is when it arrived, t3 is when the answer was sent.
232          let t2 = Date()
233          send(.timeSyncPong(TimeSyncPayload(t1: payload.t1, t2: t2, t3: Date())), to: source)
234
235      case .heartbeat:
236          // REQ-COM-005: 10.2 has no Server → Client heartbeat, so nothing is sent back.
237          // The client side judges liveness from the WebSocket ping/pong.
238          lastHeartbeatAt = Date()
239
240      case let .command(payload):
241          guard source === connection else { return }
242          ...
246      case .requestSnapshot:
247          guard source === connection, let snapshot = callbacks?.provideSnapshot() else { return }
```

`.command`（241行目）と `.requestSnapshot`（247行目）だけが `guard source === connection else { return }` を持ち、accept 済みの唯一の接続でなければ捨てる。`.timeSyncPing`（230-233行目）と `.heartbeat`（235-238行目）にはこの防御がなく、`handleHello`（=`Authenticator.authenticate`）を一切経由しない。

`Authenticator.authenticate` の版チェックもこの防御の外にある。

`/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/Pairing.swift`:
```
121  public mutating func authenticate(_ hello: HelloPayload, now: Date) -> Decision {
122
123      guard PomodoroProtocol.isCompatible(hello.protocolVersion) else {
```
この版一致チェックは `hello` 受信時にしか呼ばれず（`MdoroServer.swift:252-255` の `handleHello` からのみ）、`timeSyncPing`/`heartbeat` の経路には現れない。

つまり、iPhone 側の接続直後（WebSocket `.ready` 直後）に、`hello` を送る前に、あるいは版不一致で `hello` が `authFailed` で拒否される前後の窓で、`timeSyncPing` を送れば `timeSyncPong` が返り（往復1本増える）、`heartbeat` を送れば `lastHeartbeatAt` が無条件に更新される（片道1本増える）。参照実装の iOS クライアント自身は `startKeepalive()` を `welcome` 受信後にしか呼ばない（`MdoroClient.swift:184-185, 226-237`）ため、**この2種は「素直な同版クライアント」からは事実上出ない**が、これはクライアント側の自制であって、受信ハンドラ（Mac 側）がそれを強制しているわけではない。条文の "唯一やり取りするのは hello とその拒否まで" は、受信側の実装がそれを保証している、という主張として読める箇所なので、実装はその保証を持っていない。

### 実際に打ったコマンドと出力

```
$ grep -n "protocolVersion\|REQ-PRT-004\|version" .../ProtocolTypes.swift
3:// REQ-PRT-004: the protocol version is exchanged in hello / welcome, and an incompatible one is refused.
11:    public static let version = 2
13:    public static func isCompatible(_ other: Int) -> Bool { other == version }

$ grep -n "isCompatible\|protocolVersion\|struct Authenticator\|func authenticate\|enum Decision" .../Pairing.swift
79:public struct Authenticator: Equatable, Sendable {
114:    public enum Decision: Equatable, Sendable {
121:    public mutating func authenticate(_ hello: HelloPayload, now: Date) -> Decision {
123:        guard PomodoroProtocol.isCompatible(hello.protocolVersion) else {

$ grep -rn "sessionEvent" /tmp/stage4-clean --include=*.swift | grep -v Test
(sessionEventのcase定義・decode/encodeのみ。broadcast呼び出し箇所なし)
```

---

### 割り当て外の気づき（別項・未提案・未起票）

- `sessionEvent`（`Messages.swift:155,165,230,261`）はプロトコル型としては定義・エンコード/デコード可能だが、`/tmp/stage4-clean` 内の本番コード（`AppModel.swift` 含む）に `server.broadcast(.sessionEvent(...))` の呼び出しが見当たらなかった。A-1 の軸（hello 前の処理）とは無関係の観察のため、ここに分離して記載する。
- クライアント側（`MdoroClient.swift` の `handle(_:)`）も、`status == .connected` 等のゲートを持たず、`.timeSyncPong` を含むどの種別も無条件で処理している。Mac 側が現状の実装通りに accept 前は `welcome`/`stateSnapshot`/`taskList` を送らないため実害は生じていないが、対称性としてのみ記録する。

---

### 開いたファイル一覧

- `/tmp/claude-0/-home-user-mdoro/fe6ab0b8-83a6-51e9-a6bc-915163f1f996/scratchpad/diff-B.md`（read）
- `/tmp/claude-0/-home-user-mdoro/fe6ab0b8-83a6-51e9-a6bc-915163f1f996/scratchpad/material-B.md`（wc -l のみ、内容は未読）
- `/tmp/stage4-clean`（find, wc -l）
- `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/Messages.swift`（read）
- `/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/MdoroServer.swift`（read）
- `/tmp/stage4-clean/PomodoroMac/PomodoroiOS/Client/MdoroClient.swift`（read）
- `/tmp/stage4-clean/PomodoroMac/PomodoroiOSTests/BrokenMessageWiringTests.swift`（grep + read 抜粋）
- `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/ProtocolTypes.swift`（grep）
- `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/Pairing.swift`（grep）
- `/tmp/stage4-clean/PomodoroMac/PomodoroMac/AppModel.swift`（grep）
- `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/ServerRefusalLogTests.swift`（grep）
- `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests/RevocationTests.swift`（grep）
- 以下は `grep -l` の対象になっただけでファイル名以外は読んでいない: `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/IdentityTests.swift`, `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/ProtocolTests.swift`, `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/PairingTests.swift`, `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/ServerID.swift`, `/tmp/stage4-clean/PomodoroMac/PomodoroMac/AppModel.swift`（hello/handshake grep 時点）