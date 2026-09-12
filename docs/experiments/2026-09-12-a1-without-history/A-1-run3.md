# A-1 検証報告

## 1. 作った一覧（TCP/WebSocket が開いてから線が閉じるまでに、版の違う2台の間を実際に流れうるメッセージ）

`ClientMessage`（iPhone→Mac）・`ServerMessage`（Mac→iPhone）は `Messages.swift` で以下の7種・7種。受信側の実装（`MdoroServer.handle`, `MdoroClient.handle`）を1行ずつ突き合わせ、「`hello` が成立する前でも実際に処理されるか」を判定した結果が次の表。

| # | 方向 | 種別 | `hello` 成立前・非互換時に実際に流れうるか | 根拠 |
|---|---|---|---|---|
| 1 | iPhone→Mac | `timeSyncPing` | **流れる。応答も返る。** ガードなし | `MdoroServer.swift:230-233` |
| 2 | Mac→iPhone | `timeSyncPong` | **流れる。** 上記への直接応答で、認証状態を問わず送信 | `MdoroServer.swift:230-233` |
| 3 | iPhone→Mac | `heartbeat` | **流れる。`lastHeartbeatAt` を実際に更新する。** ガードなし | `MdoroServer.swift:235-238` |
| 4 | iPhone→Mac | `hello`（版不一致） | 流れる（想定どおりの1本目） | `MdoroServer.swift:227-228`, `Pairing.swift:122-125` |
| 5 | Mac→iPhone | `authFailed`（code: `unknownDeviceToken`） | 流れる（想定どおりの拒否） | `MdoroServer.swift:288-289, 295-298`, `Pairing.swift:123-125` |
| 6 | iPhone→Mac | `command` | バイトは受信・デコードされるが `source === connection` ガードで**無応答・無効果**のまま握りつぶされる | `MdoroServer.swift:240-244` |
| 7 | iPhone→Mac | `requestSnapshot` | 同上、無応答・無効果 | `MdoroServer.swift:246-247` |
| 8 | Mac→iPhone | `welcome` / `stateSnapshot` / `taskList` | Mac 側は `.accept`（＝バージョン一致）が確定した後にしか送らないので、**版不一致の相手には流れない** | `MdoroServer.swift:259-279` |
| 9 | Mac→iPhone | `sessionEvent` / `error` | `broadcast()` は認証済みの `self.connection` にしか送らないので、**版不一致の相手には流れない** | `MdoroServer.swift:353-356` |

**時系列の具体例（コードから再現できる1本）**

```
[TCP/WS 接続確立]
iPhone → Mac : timeSyncPing        ← hello はまだ送っていない。ガードが無いので処理される
Mac    → iPhone : timeSyncPong     ← 応答が返る
iPhone → Mac : heartbeat           ← lastHeartbeatAt が更新される（応答はない）
   … (helloTimeout の類が実装に存在しないため、上の2本は無期限に繰り返せる) …
iPhone → Mac : hello (protocolVersion: 不一致)
Mac    → iPhone : authFailed(code: unknownDeviceToken)
[Mac が sendThenClose で切断]
```

## 2. 問いへの答え

**「唯一やり取りするのは `hello` とその拒否の2本だけか」という問いに対しては、成立しない。**

`MdoroServer.handle(_:from:)` の switch 文で、`.command` と `.requestSnapshot` のケースだけが `guard source === connection else { return }` で「`hello` が成立して認証済みの接続か」を確認しているのに対し、`.timeSyncPing` と `.heartbeat` のケースにはこのガードが一切無い。そのため、

- 版の違う相手が `hello` を送る前に（あるいは `hello` を送らないまま）`timeSyncPing` を送れば、Mac は認証状態を問わず `timeSyncPong` を返す。
- 同様に `heartbeat` を送れば、Mac は `lastHeartbeatAt`（サーバー全体で共有される単一のプロパティ）を実際に更新する。

さらに、この未認証接続を強制的に閉じる「hello タイムアウト」に相当する仕組みはコード中に見当たらない（`helloTimeout` 等のキーワードで検索したが該当なし）。したがって、条文が根拠とする「そこで未知の値を受け取っても**線はそのまま終わる**ので、数えることに実害はない」という前提も、`timeSyncPing`/`timeSyncPong`/`heartbeat` の応酬に関しては成立しない——これらは `hello` の成立・拒否とは独立に、線を閉じることなく継続し得る。

## 3. 指摘（根拠ファイル・行・引用）

**指摘A**: `MdoroServer.swift` の受信ディスパッチで、`timeSyncPing` と `heartbeat` だけ認証済み接続チェックが欠けている。

`/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/MdoroServer.swift:222-249`
```swift
private func handle(_ data: Data, from source: NWConnection) {
    // REQ-ERR-009: a broken message is thrown away and the connection is kept.
    guard let envelope = try? MessageCoder.decodeClient(data) else { return }

    switch envelope.body {
    case let .hello(payload):
        handleHello(payload, from: source)

    case let .timeSyncPing(payload):
        // REQ-COM-007: t2 is when it arrived, t3 is when the answer was sent.
        let t2 = Date()
        send(.timeSyncPong(TimeSyncPayload(t1: payload.t1, t2: t2, t3: Date())), to: source)

    case .heartbeat:
        // REQ-COM-005: 10.2 has no Server → Client heartbeat, so nothing is sent back.
        // The client side judges liveness from the WebSocket ping/pong.
        lastHeartbeatAt = Date()

    case let .command(payload):
        guard source === connection else { return }
        // REQ-PRT-003: a resend carrying the same clientRequestId is ignored.
        guard deduplicator.shouldProcess(payload.clientRequestId) else { return }
        callbacks?.handleCommand(payload)

    case .requestSnapshot:
        guard source === connection, let snapshot = callbacks?.provideSnapshot() else { return }
        send(.stateSnapshot(snapshot), to: source)
    }
}
```
`.command` と `.requestSnapshot` は `guard source === connection`（＝この `NWConnection` が現在認証済みの接続かどうか）を確認しているのに対し、`.timeSyncPing` と `.heartbeat` にはそれが無い。`source` は `hello` が受理される前の未認証接続でもよく、この2種別は `hello` の成立を前提にしていない。

**指摘B**（傍証）: `checkHeartbeat()` は `connection`（認証済み接続）がある場合のみ動くため、未認証接続を強制的に切るタイムアウトにはならない。

`/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/MdoroServer.swift:393-399`
```swift
private func checkHeartbeat() {
    guard let connection else { return }
    if Heartbeat.isStale(lastReceivedAt: lastHeartbeatAt, now: Date()) {
        connection.cancel()
        handleDisconnect(connection)
    }
}
```
未認証の `source`（`connection` とは別物）はこの監視の対象にならないため、`hello` を送らないまま `timeSyncPing`/`heartbeat` だけを送り続ける接続を、実装は自発的に切らない。

**参照した仕様条文**（変更後）：
`/tmp/claude-0/-home-user-mdoro/fe6ab0b8-83a6-51e9-a6bc-915163f1f996/scratchpad/material-B.md:918`
> 版の違う2台が唯一やり取りするのは `hello` とその拒否までであり、そこで未知の値を受け取っても線はそのまま終わるので、数えることに実害はない。

上記2箇所の実装と、この1文は整合しない。

## 4. 実際に打ったコマンドと出力

```
$ find /tmp/stage4-clean -type f -name "*.swift" | sort
(出力は上のツール呼び出しで確認済み。主要ファイルの存在確認に使用。Messages.swift, ProtocolTypes.swift,
 Pairing.swift, MdoroServer.swift, MdoroClient.swift の実在を確認)
```

```
$ grep -n "REQ-PRT-005\|REQ-PRT-004\|REQ-ERR-009" material-B.md
917:| **REQ-PRT-004** | **MUST** | プロトコルバージョン番号を `hello` / `welcome` で交換し、非互換の場合は接続を拒否して両端末に更新を促すこと。...
918:| **REQ-PRT-005** | **MUST** | ...版の違う2台が唯一やり取りするのは `hello` とその拒否までであり...
997:| `protocolVersionMismatch` | プロトコル非互換 | REQ-PRT-004 |
1158:| **REQ-ERR-009** | **SHOULD** | 不正・破損したメッセージを受信 | ...
```

```
$ grep -rn "isCompatible|protocolVersionMismatch|PomodoroProtocol.version" /tmp/stage4-clean
(抜粋)
Pairing.swift:123:        guard PomodoroProtocol.isCompatible(hello.protocolVersion) else {
Pairing.swift:124:            return .reject(.unknownDeviceToken)
```
→ 版不一致の拒否コードは `AuthFailureCode.unknownDeviceToken` であり、`ProtocolErrorCode.protocolVersionMismatch`（`error` メッセージ側にのみ存在）とは別物であることを確認（このこと自体はA-1の軸の外なので後述の「軸の外」に記載）。

```
$ grep -rn "helloTimeout|awaitingHello|pendingHello|handshakeTimeout" /tmp/stage4-clean -i
(該当なし)
```
→ 未認証接続を強制的に閉じるタイムアウト機構が実装中に見当たらないことを確認。

```
$ grep -n "timeSyncPing|timeSyncPong|before hello|pre-?hello|unauthenticated" \
    /tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/ProtocolTests.swift -i
23:            .timeSyncPing(TimeSyncPayload(t1: now)),
44:            .timeSyncPong(TimeSyncPayload(t1: now, t2: now, t3: now)),
```
→ エンコード/デコードのラウンドトリップテストのみで、`hello` 成立前の受理可否を検証するテストは見当たらない。

---

## 割り当ての外で気づいたこと（別項・未採用の提案として記載。実装せず、起票もしません）

- `Pairing.swift:123-125` で、プロトコル版不一致の拒否コードが `AuthFailureCode.unknownDeviceToken` になっている。`ProtocolErrorCode` 側には `protocolVersionMismatch`（表示文言「This iPhone and your Mac are running different versions of Mdoro. Update both.」）が別に存在するが、`hello` 拒否の経路（`AuthFailureCode`）からは使われていない。REQ-PRT-004 は「両端末に更新を促すこと」を求めているが、`unknownDeviceToken` の表示文言（`AuthFailureCode` 側、`ProtocolTypes.swift` の外——実際の文言定義は今回確認していない）が「バージョンを更新せよ」という案内になっているかは、この軸の範囲外なので未確認。もし案内文言が版不一致を伝えていないなら、REQ-PRT-004 の「両端末に更新を促す」という要求と実装の対応関係に疑問が残る、という気づきのみ報告する。

---

## 開いたファイル一覧（read / grep / ls・find の別を問わず）

- `/tmp/claude-0/-home-user-mdoro/fe6ab0b8-83a6-51e9-a6bc-915163f1f996/scratchpad/diff-B.md`（Read）
- `/tmp/claude-0/-home-user-mdoro/fe6ab0b8-83a6-51e9-a6bc-915163f1f996/scratchpad/material-B.md`（Grep, 複数パターン）
- `/tmp/stage4-clean`（find, 全体一覧）
- `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/Messages.swift`（Read）
- `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/ProtocolTypes.swift`（Read）
- `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/Pairing.swift`（Read, offset 90-150）
- `/tmp/stage4-clean/PomodoroMac/PomodoroMac/Server/MdoroServer.swift`（Read, 全文）
- `/tmp/stage4-clean/PomodoroMac/PomodoroiOS/Client/MdoroClient.swift`（Read, 全文）
- `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/FailuresThatReachSomeoneTests.swift`（Grep マッチ）
- `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/IdentityTests.swift`（Grep マッチ）
- `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/PairingTests.swift`（Grep マッチ）
- `/tmp/stage4-clean/Packages/MdoroCore/Tests/MdoroCoreTests/ProtocolTests.swift`（Grep マッチ・内容表示）
- `/tmp/stage4-clean/Packages/MdoroCore/Sources/MdoroCore/Protocol/BonjourService.swift`（Grep マッチ）
- `/tmp/stage4-clean/PomodoroMac/PomodoroMacTests`（Grep, ディレクトリ検索・該当なし）