# 0005. ローカルネットワークの許可と、接続に要る設定

- **調査日**: 2026-08-29
- **対象**: macOS 26.5.1（build 25F80）/ iOS 26 / Xcode 26.6（build 17F113、macOS 26.5 SDK・iOS 26.x SDK）
- **依頼の理由**: `SPEC.md` 3.5 の表8行すべてに出典が無いまま、REQ-PLT-001（**MUST**）が
  「**いずれか1つでも欠けると接続が成立しない**」と断定していた。REQ-PLT-008（**MUST**）の
  「許可状態を問い合わせる API は**存在しない**」も**否定的事実の上に立つ MUST** だった（軸 K・POL-062 / POL-063）。
  **誤っていれば、OSS の貢献者に不要な設定を書かせるか、必要な設定を欠いたまま「動かない」と言わせる**

## 問い

依頼した内容をそのまま残す。**それぞれ別に確度を付けること**、
**「文書化されていない」「禁止されている」「必須である」をはっきり区別すること**と指示した。

1. **ATS**: iOS 17 / macOS 14 以降、IP 直結を既定で拒否するか。`NSAllowsLocalNetworking` は**必須**か。
   **DHCP 環境では `NSExceptionDomains` で回避できない**は事実か
2. **`NSBonjourServices`**: 未列挙だと探索が失敗するか。**iOS だけの要求か、macOS にも及ぶか**
3. **`NSLocalNetworkUsageDescription`**: macOS でも 15 以降に必要か。**登録する側にも許可が要る**か
4. **`NSSupportsLiveActivities`**: 必要か
5. **entitlement 3件**: それぞれの理由は正しいか
6. **REQ-PLT-008**: 問い合わせる API は本当に無いか。`-65570` と `.localNetworkDenied` は裏が取れるか。
   **初回取得はフォアグラウンドでなければならない**は事実か
7. **REQ-PLT-001 の断定**は 1〜5 から導けるか

## 答え

**3.5 の表は「制約は本物だが限定が誤り」という同型の事故を、少なくとも2件含んでいる。**

| # | 主張 | 判定 |
| :-- | :-- | :-- |
| 1 | ATS は iOS 17 / macOS 14 以降 IP 直結を拒否 | **事実**（文書化） |
| 1' | `NSAllowsLocalNetworking` は**必須** | **誤り。ATS は Network.framework に適用されない。このアプリには無関係** |
| 1'' | DHCP では `NSExceptionDomains` で回避不可 | **誤り。** Apple は iOS 17+ の対処として **CIDR レンジ**の列挙を明示している |
| 2 | `NSBonjourServices` 未列挙だと探索が失敗 | **事実**。ただし **iOS 限定ではない。macOS 11.0+ にもあり、登録側にも要る** |
| 3 | `NSLocalNetworkUsageDescription` は macOS 15 以降も必要 / 登録側にも許可が要る | **事実。この行が表で唯一、完全に正しい** |
| 4 | `NSSupportsLiveActivities = YES` | **事実**。ただし**接続とは無関係** |
| 5 | entitlement 3件の理由 | server ○ / **client の理由は誤り** / files ○ |
| 6 | 問い合わせる API は存在しない / `-65570` / `.localNetworkDenied` | **事実。Apple 自身がコード例まで載せている** |
| 6' | 初回取得はフォアグラウンドで | **事実。ただし iOS の条項で、macOS には同じ記述が無い** |
| 7 | 「1つでも欠けると接続が成立しない」 | **誤り。8行中3行は接続に無関係、1行は不要** |

**REQ-PLT-008 は正しい。誤っているのは REQ-PLT-001 の断定である。**
POL-063 が「最も検証されにくい形」と疑った2件のうち、**REQ-PLT-008 の側は空振りだった。**

## 根拠

### 1. ATS — 制約は本物、適用先が違う

**1a. 「iOS 17 / macOS 14 以降、IP 直結を既定で拒否」= 事実**

> "In iOS 17, iPadOS 17, and macOS 14, ATS no longer allows connections to IP addresses by default."
> — [NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)

**1b. ATS は Network.framework に適用されない**

> "ATS doesn't apply to calls your app makes to lower-level networking interfaces like
> the Network framework or CFNetwork."
> — [Preventing Insecure Network Connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections)

[NSAppTransportSecurity](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity)
も適用範囲を URL Loading System に限定している。

**REQ-PLT-002 が Network.framework を MUST で指定している以上、ATS はこのアプリの通信経路に一度も掛からない。**
実装も一致している（`--include=*.swift` で `URLSession` の使用は **0件**。通信は `NWListener` /
`NWConnection` / `NWBrowser` / `NWProtocolWebSocket` のみ）。

→ `NSAllowsLocalNetworking` は**必須ではない。禁止でもない**
（Apple は "consider setting NSAllowsLocalNetworking to YES as a declaration of intent" と述べる）。

**1c. 「DHCP 環境では `NSExceptionDomains` は使えない」= 誤り**

> "Add individual IP addresses and classless inter-domain routing (**CIDR**) ranges in the
> `NSExceptionDomains` dictionary."

**CIDR レンジが書ける**以上、`192.168.1.0/24` のような指定で DHCP 環境は覆える。
条文は「個々の IP を列挙する」形しか想定せず、**Apple が iOS 17 向けに用意した対処そのものを
「使えない」と否定していた。**

### 2. `NSBonjourServices` — iOS 限定という限定が誤り

**必須である。そして iOS だけの要求ではない。**

- 可用性: **iOS 14.0 / iPadOS 14.0 / macOS 11.0 / tvOS 14.0 / visionOS 1.0**
- [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) は
  **プラットフォームを限定せず、登録側も含めて**要求する:
  > "If your app's local network usage involves **registering** or browsing for specific Bonjour services,
  > add a list of service types to the `NSBonjourServices` property in your app's `Info.plist`."
- SDK ヘッダが「required」と明記する（macOS を含む）。
  `MacOSX.sdk/.../Foundation.framework/Headers/NSNetServices.h:54-58`:
  > `/* Missing required configuration for local network access.`
  > `* NSBonjourServices and NSLocalNetworkUsageDescription are required in Info.plist */`
  > `NSNetServicesMissingRequiredConfigurationError API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0)) = -72008`
- 独立した傍証: `Matter.framework/Headers/MTRError.h:89` の `MTRErrorCodeDNSSDUnauthorized`
  （"missing entries … under the `NSBonjourServices` key"、`MTR_AVAILABLE(ios(17.2), macos(14.2), …)`）

**表の「対象」欄が `iOS` になっているのは誤り。Mac 側（登録する側）にも要る。**

### 3. `NSLocalNetworkUsageDescription` — 表で唯一、完全に正しい行

- **macOS も対象**: TN3179 のプラットフォーム表は macOS を "Introduced: **macOS 15**" とする
- **登録する側にも許可が要る**: TN3179 / Bonjour operations の表が決定的である

| Operation | Required |
| :-- | :-- |
| **Registering a service with Bonjour** | **yes** |
| Browsing for Bonjour services | yes |
| Resolving a Bonjour service | yes |

対比として Local network operations の表は
"Listening for and accepting incoming TCP connections | **no**" とする。
**Mac が許可を要する理由は「待ち受けるから」ではなく「Bonjour に登録するから」である。**
条文の括弧内の理由は正しい。

macOS には自動許可の例外がある（`launchd` **デーモン**、root で動くプロセス、
Terminal / SSH から起動したコマンドラインツールとその子プロセス）。
**GUI アプリと `launchd` エージェントは例外に入らない。**

### 4. `NSSupportsLiveActivities` — 必須。ただし接続とは無関係

> "add the Supports Live Activities entry to it, and set its Boolean value to `YES`."
> — [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)

可用性は **iOS 16.1 / iPadOS 16.1 のみ**（macOS には存在しない）。表の「対象: iOS」は正しい。
Apple は**アプリ本体のターゲット**に置けと書いている（widget extension 側ではない）。

**この行が欠けても接続は成立する。REQ-PLT-001 の断定はこの1行だけで崩れる。**

### 5. entitlement 3件

**`com.apple.security.network.server` — 理由は正しい。**
> "A Boolean value indicating whether your app may listen for incoming network connections."

**`com.apple.security.network.client` — 理由が誤り。**
文書上の定義は「外向き接続を開くこと」であって、Bonjour ではない。
そして **OS 側の実際の判定は「client か server の どちらか」である**（**実測**）。

`/System/Library/Sandbox/Profiles/application.sb:759-762`（macOS 26.5.1）:
```
(unless
  (or (entitlement "com.apple.security.network.client")
      (entitlement "com.apple.security.network.server"))
  (deny network-outbound (literal "/private/var/run/mDNSResponder")))
```

**Bonjour（DNS-SD）は `mDNSResponder` への UNIX ソケット接続であり、その門は「client または server」。**
**Mac は `network.server` を持つのだから、Bonjour のために `client` は要らない。**
Apple は TCP について「entitlement が制限するのは接続の**開始**だけで、データの流れではない」とも明記している。

**`com.apple.security.files.user-selected.read-write` — 理由は正しい。表に不足は無い。**
`com.apple.security.files.bookmarks.app-scope` は**現行の entitlements 索引にも
[Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
にも登場しない**。かつ `application.sb:295-300` は、`files.user-selected.read-write` を持っていれば
scoped bookmark エージェント（`com.apple.scopedbookmarksagent.xpc`）へのアクセスを許している（**実測**）。
**REQ-PLT-003 のブックマークに追加の entitlement は要らない。**

REQ-PLT-003 の裏も取れた:
> "If your app doesn't need to write to the file on subsequent access, include the
> `securityScopeAllowOnlyReadAccess` option."

### 6. REQ-PLT-008 — 正しい。しかも Apple がそのまま書いている

TN3179 の "Check for local network access" 節に、条文の3要素がすべて揃っている。

> "There's **no general API** that returns whether the current process has local network access (FB8711182)."

> "If you're using Bonjour, check whether your operation is waiting with the
> `kDNSServiceErr_PolicyDenied` (**-65570**) error."

> "If your program doesn't have local network access, the connection enters the `waiting(_:)` state
> and the current path lists an unsatisfied reason of `localNetworkDenied`."

Apple のコード例は `if case .localNetworkDenied? = connection.currentPath?.unsatisfiedReason` であり、
**条文の記述と一字一句近い。**

SDK 側の裏:
- `usr/include/dns_sd.h:801` — `kDNSServiceErr_PolicyDenied = -65570`
  （**ヘッダにコメントは無い。「-65570 ＝ ローカルネットワーク拒否」という意味づけの根拠は TN3179 のみ**）
- `Network.framework/Headers/path.h:91-92` —
  `/*! @const nw_path_unsatisfied_reason_local_network_denied The user has disabled local network access */`
- `Network.swiftmodule/arm64e-apple-macos.swiftinterface` — `UnsatisfiedReason` は
  `@available(macOS 11.0, iOS 14.2, …)`。**iOS 26 / macOS 26 で新設・変更・非推奨のいずれも無い**

**否定的事実の検証手順**（3方向から確認した）:
(a) TN3179 が明文で否定している（2026-02-17 改訂）。
(b) macOS 26.5 SDK / iOS 26 SDK の全 framework ヘッダと swiftinterface を
`localnetwork` / `local_network` で全文検索し、公開 API は `NWPath.UnsatisfiedReason.localNetworkDenied` と
`AppIntentError.PermissionRequired.localNetwork`（iOS 18.0+、**照会ではなくエラー表明**）以外に無いことを確認した。
(c) [Requesting access to protected resources](https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources)
が "In cases without a dedicated API, prepare your app to gracefully handle access failures" と、
照会 API の無い資源の存在を一般則として認めている。

**一点だけ注記**: `Network.tbd` の書き出し記号に
`_network_config_local_network_blocked_observer_create` が存在する。
**どの公開ヘッダにも宣言が無い＝公開 API ではない。**
条文を変える理由にはならないが、**「存在しない」の正確な意味は「公開 API としては存在しない」である。**

**6' 初回取得はフォアグラウンドで（REQ-PLT-007）— iOS については文書化。macOS には記述が無い。**

> "If an iOS app is in the background and performs a local network operation while its Local Network
> privilege is undetermined, the system denies that operation without presenting the local network alert.
> **The system doesn't record that decision.** If, later on, the app performs a local network operation
> while in the foreground, the system presents the alert to the user as if this were the first
> local network operation."

**条文が書いていない重要な事実が1つある: この拒否は記録されない。**
恒久的な取り逃しではなく、フォアグラウンドで再試行すればダイアログは出る。
**条文の「黙って拒否される」は正しいが、取り返しがつかないかのように読める。**

macOS 側には対応する条項が無く、代わりに別の落とし穴が書かれている
（`FB16131937`: ローカルネットワーク操作の直後に終了する短命プロセスにはアラートが出ない）。

**REQ-PLT-009 も裏が取れた**（依頼外だが同じ節にある）:
"To ensure that local network privacy reliably tracks the identity of your macOS program,
sign it with an Apple-issued code-signing identity." /
"On macOS there's **no way** to reset your program's Local Network privilege to the undetermined state (FB14944392)."

**テストに効く事実**: "The simulator doesn't support local network privacy.
**Test your local network privacy behavior on a real device.**"

### 7. 「1つでも欠けると接続が成立しない」は導けない

| 行 | 接続に必須か | 根拠 |
| :-- | :-- | :-- |
| `NSAllowsLocalNetworking` | **不要** | ATS は Network.framework に適用されない |
| `NSBonjourServices`（iOS・**macOS 両方**） | **必須** | TN3179 / `NSNetServices.h` |
| `NSLocalNetworkUsageDescription`（iOS・macOS 15+） | **必須に近い** | 許可自体は必須。文言欠落時の挙動は文書上 "should" |
| `NSSupportsLiveActivities` | **接続とは無関係**（Live Activity には必須） | ActivityKit |
| `network.server` | **必須** | 待ち受け＋`mDNSResponder` の門 |
| `network.client` | **理由が誤り。要否は不明** | 門は client **または** server |
| `files.user-selected.read-write` | **接続とは無関係**（ログ追記には必須） | Sandbox |

**8行中、接続の成立に効くのは4行。** 1行は不要、2行は別の機能のための設定、1行は理由が誤り。

## 確度

| 主張 | 確度 |
| :---- | :---- |
| ATS は Network.framework に適用されない | **文書化** |
| iOS 17 / macOS 14 以降 ATS が IP 直結を拒否する。対処は個別 IP と **CIDR レンジ**の列挙 | **文書化** |
| **Bonjour の「登録」も許可を要する。TCP の待ち受けと accept は要さない** | **文書化** |
| `NSBonjourServices` は iOS 限定ではない（macOS 11.0+、登録側にも要る） | **文書化**（+ SDK ヘッダ） |
| ローカルネットワークプライバシーは macOS 15 で導入。`launchd` デーモン・root・Terminal 起動のツールは自動許可 | **文書化** |
| **許可状態を問い合わせる公開 API は存在しない**。検出は `-65570` と `.localNetworkDenied` | **文書化** |
| バックグラウンドでの拒否は**記録されない**（iOS）。macOS に同じ条項は無い | **文書化** |
| **Bonjour の門は `network.client` または `network.server` のどちらか** | **実測**（`application.sb:759-762`、macOS 26.5.1） |
| security-scoped bookmark に追加の entitlement は要らない | **実測**（`application.sb:295-300`） |
| **シミュレータはローカルネットワークプライバシーを実装していない。実機でしか検証できない** | **文書化** |
| `network.client` を外して macOS 版が動くか | **不明**（未実測） |
| 設定漏れと許可拒否が同じエラーコードで返るか | **不明** |

## 確かめられなかったこと

**推測で埋めない。**

1. **`network.client` を外した macOS 版が実際に Bonjour 登録・接続受理を完遂できるか**（未実測）。
   **「不要と断定できる」ではなく「挙げられている理由は誤り」までが確実**
2. `NSBonjourServices` / `NSLocalNetworkUsageDescription` 欠落時に `NWBrowser` / `NWListener` が返す
   具体的なエラー。**設定漏れと許可拒否が同じ `-65570` で返るのかは不明**
   （REQ-ERR-008 / REQ-ERR-014 の出し分けに影響しうる）
3. `NSAllowsLocalNetworking = YES` が iOS 17+ の URL Loading System で IP 直結を復活させるか
   （**文書が不整合。ただしこのアプリには影響しない**）
4. macOS で「初回取得はフォアグラウンド」に相当する制約があるか
   （TN3179 に記述が無い＝**無いとは書かれていない**）
5. `_network_config_local_network_blocked_observer_create` の実体（非公開のため追跡していない）

## 影響を受ける記述

**列挙のみ。直し方はこの記録では判断しない。**

| 箇所 | 理由 |
| :---- | :---- |
| REQ-PLT-001（**MUST**） | 「いずれか1つでも欠けると接続が成立しない」は**導けない**。8行中4行のみ |
| 3.5 の表 `NSAllowsLocalNetworking` の行 | **不要**。ATS はこのアプリの経路に掛からない |
| 3.5 の表 `NSExceptionDomains` の注記 | 「DHCP では回避できない」は**誤り**（CIDR） |
| 3.5 の表 `NSBonjourServices` の「対象」欄 | `iOS` は**誤り**。macOS 11.0+ にもあり、**登録側にも要る** |
| 3.5 の表 `network.client` の理由欄 | Bonjour のためではない。**門は client または server** |
| REQ-PLT-007 | 「黙って拒否される」は正しいが、**この拒否が記録されないことが書かれていない。** また **iOS の条項である** |
| REQ-PLT-008 | **正しい。** 精確を期すなら「**公開 API としては**存在しない」 |
| REQ-PLT-009 | **裏が取れた**（Apple 発行の署名、macOS では未決定へ戻せない） |
| REQ-PLT-003 | `securityScopeAllowOnlyReadAccess` の記述は**文書化で裏が取れた** |
| `AGENTS.md` / `DEVELOPMENT.md` | **シミュレータではローカルネットワークプライバシーを検証できない**ことが、どちらにも書かれていない |
