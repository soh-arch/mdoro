# 0004. Live Activity のデータ上限と、ネットワークへのアクセス

- **調査日**: 2026-08-29
- **対象**: iOS 26 / iPhoneOS26.5.sdk
- **依頼の理由**: REQ-UIX-025（MUST・4KB）は**数値だけの MUST**、REQ-UIX-026（MUST・
  「サンドボックス上不可能」）は**否定的事実の上に立つ MUST** で、どちらも出典が無かった（軸 K・POL-063 / POL-064）

## 問い

依頼した内容をそのまま残す。**それぞれ別に確度を付けること**と指示した。

1. **REQ-UIX-025**「動的データは 4KB 以内」。**この数値の出典はどこか。** 4KB は何に対する上限か
   （`ContentState` のエンコード後か、`ActivityAttributes` を含むか、プッシュ経由だけか、
   ローカル更新にも及ぶか）。**超えたときに何が起きると文書化されているか**
2. **REQ-UIX-026**「Live Activity（ウィジェット拡張）からのネットワークアクセスはサンドボックス上不可能」。
   **これは事実か。** 禁止されているのか、可能だが推奨されないのか、可能だが当てにできないのか。
   entitlement との関係も含めて

**「文書化されていない」と「禁止されている」と「保証されない」をはっきり区別すること**と指示した。
[0002](0002-live-activity-background-start-and-suspend.md) で「不可能」と書かれていたものが実際には
「**禁止されていない。当てにできないだけ**」だったためである。

## 答え

**両方とも一次情報で決着した。0001 / 0002 / 0003 とは違い、「事実そのものが誤り」ではない。**

**REQ-UIX-025（4KB）— 数値は正しい。ただし条文の限定が誤っている（緩すぎる方向に）。**
Apple の上限は**静的（`ActivityAttributes`）＋動的（`ContentState`）の合計**であり、
**条文の言う「動的データが 4KB 以内」を満たしても、上限を満たしたことにならない。**
**プッシュ限定ではなく、ローカル更新にも及ぶ**（Apple が明記）。

**REQ-UIX-026（ネットワーク）— 事実である。しかも Apple 自身が "sandbox" という語を使っている。**
**ただし条文の主語が誤っている。**「Live Activity 拡張（ウィジェット拡張）」からのネットワークは
**可能であり、Apple が専用の記事で手順を書いている。** 不可能なのは **Live Activity のみ**である。
Apple の一文は「**unlike a widget**」と、まさにその対比で書かれている。

## 根拠

### 1. 4KB

**(a) 上限の本体** — [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
の **"Understand constraints" 節**:

> "Static and dynamic data for a Live Activity, including data for ActivityKit updates and
> ActivityKit push notifications, can't exceed a combined size of 4 KB."

**これが4つの問い全部に答えている。** **combined**（`ActivityAttributes` を含む）、
**ActivityKit updates を明示的に含む**（＝プッシュ限定ではない。ローカル更新にも及ぶ）。

**(b) 超えたときに起きること — `request` の場合のみ文書化されている**

`ActivityAuthorizationError.attributesTooLarge`:

> "The provided Live Activity attributes exceeded the maximum size of 4KB."

`Activity.request(...)` は SDK 上 `throws` である（`iPhoneOS26.5.sdk` の
`arm64e-apple-ios.swiftinterface` 46・52・59・66・73行目、**5つのオーバーロード全部**）。
**例外で弾かれ、Live Activity は開始しない。**

**(c) `update` / `end` の場合 — 上限は書かれているが、破ったときの挙動は書かれていない**

`Activity.update(_:)`:

> "The updated dynamic content for the Live Activity. The size of its `state` property
> can't exceed 4KB in size."

`update(using:alertConfiguration:)` / `end(...)`:

> "The size of the encoded content can't exceed 4KB in size."

**`update` と `end` は `throws` ではない。** swiftinterface 147〜189行目、すべて `async` のみ。
**エラーを返す経路が存在しない。** 例外・無視・切り詰めのいずれになるかは、**どの文書にも書かれていない。**

**(d) SDK 内での確認（対象バージョンに固定できる根拠）**

`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS26.5.sdk/System/Library/Frameworks/ActivityKit.framework/Modules/ActivityKit.swiftmodule/arm64e-apple-ios.swiftdoc`
に上記の文言がそのまま入っている。**web の記述に依存せず、iOS 26.5 SDK 単体で 4KB を確認できる。**

**(e) Apple の文書内に食い違いがある（そのまま報告する）**

| 出典 | 何に対する 4KB か |
| :---- | :---- |
| 概説記事「Understand constraints」 | **静的＋動的の合計** |
| `update` / `end` のリファレンス | **`state`（＝`ContentState`）単体** |

**この2つは同じ規則ではない。** どちらも現行の一次情報であり、**どちらかが古いという証拠は見つからなかった。**
**安全側は合計 4KB** である。

**(f)** `update` / `end` の記述は "the **encoded** content" と言う。
**Swift のメモリ上の大きさではなく、シリアライズ後の大きさ**が対象である。
**ただしローカル経路でどのエンコーダが使われるかは書かれていない**
（プッシュ経路については "the system always decodes JSON payloads for Live Activity updates
using its default encoding strategies" と別途明記がある）。

### 2. ネットワーク

**(a) Live Activity は不可能 — Apple が断定している**

同じ記事の "Understand constraints" 節、**4KB の一文の直前**:

> "Each Live Activity runs in its own sandbox, and — unlike a widget — it can't access the network
> or receive location updates."

**「文書化されていない」でも「保証されない」でもなく、「できない」と書かれている。**
しかも機構として sandbox を名指ししている。
**REQ-UIX-026 の断定と括弧内の理由は、Apple の原文とほぼ一語一句一致する。**

**(b) しかしウィジェットは可能である — Apple が専用記事で手順を書いている**

[Making network requests in a widget extension](https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension):

> "Network requests are possible while the widget extension is active, such as when it provides
> a snapshot, or a new timeline."

> "In general, making a network request from a widget extension is similar to making a network request
> in your app: you can initiate inline or background requests. However, widgets can only access
> limited resources and a request may not have enough time to complete before the system halts
> the widget extension."

バックグラウンド `URLSession` まで正式に用意されている
（`WidgetConfiguration` の `onBackgroundURLSessionEvents(matching:_:)` 修飾子）。

**求められた3区分に当てはめると:**

| 対象 | 区分 |
| :---- | :---- |
| **Live Activity の表示コード** | **禁止（不可能）。** sandbox によると明記 |
| **同じ拡張のウィジェット（timeline）コード** | **可能。ただし保証されない**（"limited resources"・完了前に halt されうる）— [0002](0002-live-activity-background-start-and-suspend.md) と同型の「不可能ではなく当てにできない」 |
| **`LiveActivityIntent.perform()`** | **拡張ではなくアプリ本体のプロセス。この制約の対象外** |

`LiveActivityIntent` のリファレンスが3つ目を裏づける:

> "the system launches your app process without opening the app, performs the intent"

**REQ-UIX-024（`perform()` から Mac へ再接続する）と REQ-UIX-026 は矛盾しない。**
**境界は「表示面」ではなく「プロセス」である。**

**(c) entitlement との関係 — 前提が空振りしている**

**`com.apple.security.network.client` は macOS 専用である。**
[その entitlement の文書](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.network.client)
のメタデータは対応プラットフォームを **macOS 10.7 のみ**と示し、本文も App Sandbox capability の話に終始する。

**iOS には対応する entitlement が存在しない。** iOS のアプリ・拡張はネットワークを既定で使える。
したがって **Live Activity の制約は entitlement で開けられるものではない**（開けるための鍵がそもそも無い）。

補強として、`iPhoneOS26.5.sdk` の swiftinterface では `Activity` / `ActivityContent` /
`ActivityAuthorizationError` すべてに `@available(macOS, unavailable)` が付く。

## 確度

| 主張 | 確度 |
| :---- | :---- |
| 上限は 4KB。静的＋動的の**合計**。ActivityKit の**ローカル更新にも及ぶ** | **文書化** |
| `request` 超過時は `ActivityAuthorizationError.attributesTooLarge` を throw し、開始しない | **文書化**（+ SDK シグネチャで確認） |
| `update` / `end` のリファレンスは「`state` 単体 4KB」と書き、概説記事の「合計 4KB」と**食い違う**。両方が現行 | **文書化**（矛盾あり。**安全側は合計**） |
| 上限は **encoded**（シリアライズ後）の大きさ | **文書化** |
| **`update` / `end` 超過時に何が起きるか** | **不明。** API は非 throws でエラー経路が無く、どの文書にも記述が無い |
| Live Activity はネットワークにアクセス**できない**。sandbox による | **文書化** |
| **ウィジェット拡張のネットワークは可能。** ただし完了は保証されない | **文書化** |
| `LiveActivityIntent.perform()` はアプリ本体のプロセス。制約の対象外 | **文書化** |
| `com.apple.security.network.client` は **macOS 専用**。iOS に相当物なし | **文書化** |

**バージョンの但し書き**: 4KB は **`iPhoneOS26.5.sdk` の swiftdoc 内に実在する**ため、iOS 26 に固定して言える。
**ネットワーク / sandbox の一文は散文記事のみに存在し、SDK には無い。**
developer.apple.com は 2026-08-29 時点で iOS 27 のサイクルに入っているため、
**この一文について「iOS 26 の文書がそう書いていた」ことまでは確認できていない。**

## 確かめられなかったこと

**推測で埋めない。**

- **`update` / `end` が 4KB を超えたときの挙動。** 例外・無視・切り詰めのどれでもあるとは書かれていない。
  `update` に文書化された「無視」は**終了済み Live Activity への更新**という別条件のみ
  （"The system ignores attempts to update a Live Activity that ended."）
- **4KB が 4096 バイトか 4000 バイトか。** Apple は "4 KB" と "4KB" を混用し、**バイト数を一度も示さない**
- **ローカル経路で size を測るときのエンコーダ。** プッシュ経路の JSON 既定戦略の記述はあるが、ローカルには無い
- **sandbox が実行時にネットワークを実際に遮断するか。** 読むだけの調査であり、**実測なし**
- **WWDC の裏づけは見つからなかった。** WWDC26 セッション 223「Live Activities essentials」の
  トランスクリプトを全文取得して `4KB` / `network` / `sandbox` / `budget` を検索したが **0 件**。
  **なおこのセッションは iOS 27 を扱っており、対象 iOS 26 の資料ではない**
- **プッシュ記事に 4KB の記述は無い**（`KB` / `kilobyte` / `size limit` / `too large` で 0 件）。
  APNs 一般のペイロード上限は**本調査の範囲外で未確認**（APNs はスコープ外のため実害なし）
- **HIG「Live Activities」には 4KB もネットワークも記述が無い**（検索して 0 件）

## 影響を受ける記述

**列挙のみ。直し方はこの記録では判断しない。**

| 箇所 | 理由 |
| :---- | :---- |
| REQ-UIX-025（`SPEC.md:828`） | 「**動的データ**が 4KB」と書くが、**上限は静的との合計**である。動的だけを収めても制約を満たしたことにならない |
| REQ-UIX-026（`SPEC.md:829`） | 「不可能」「サンドボックス上」は**Apple の原文どおりで正しい。誤っているのは主語である** — 不可能なのは **Live Activity** であって、**ウィジェット拡張ではない**。将来ウィジェットを足したとき、**文書化された正規の手段を誤って禁じる** |
| REQ-UIX-024 | [0002](0002-live-activity-background-start-and-suspend.md) に続き、ここでも**矛盾しないことが確認された**（境界はプロセス） |
| 実装 | `ActivityAttributes` と `ContentState` の**合計**が 4KB に収まっているかは、**この調査では確認していない** |
