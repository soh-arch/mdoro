# 0002. Live Activity はいつ開始でき、いつ更新できるか

- **調査日**: 2026-08-29
- **対象**: iOS 26 / iPadOS 26
- **依頼の理由**: `SPEC.md` 8.3 冒頭が「**プラットフォーム制約（Apple 公式で確認済み）**」と
  断りながら、リポジトリのどこにも一次情報への参照が無かった（軸 K・POL-060）。
  この一文の上に REQ-NTF-002（MUST）、REQ-UIX-020 / 022 の MUST→SHOULD 格下げの唯一の理由、
  REQ-UIX-024 の禁止、第14章の帰結が乗っている

## 問い

依頼した内容をそのまま残す。**この一文は少なくとも4つの独立した主張を含んでいるので、
それぞれ別に確度を付けること。まとめないこと**と指示した。

調べた対象の原文:

> **プラットフォーム制約（Apple 公式で確認済み）:** Live Activity は **(a) アプリがフォアグラウンドに
> ある間しか開始できない**（例外は APNs による push-to-start のみ）、**(b) 更新もアプリが running で
> ある間しか行えない**。iOS はバックグラウンド移行後まもなくアプリを suspend するため、その時点で
> WebSocket も切断される。したがって**完全ローカル駆動（第14章）を維持する限り、ロック中に Mac 側の
> 状態変化を Live Activity へ反映することはできない。**

1. **開始**: `Activity.request(...)` はフォアグラウンドの間しか成功しないか。
   バックグラウンドでの開始は本当に APNs の push-to-start だけが例外か
2. **更新**: `Activity.update(...)` は running の間しか行えないか。**ローカルからの更新に、
   フォアグラウンドであることが要求されているか**
3. **suspend**: バックグラウンド移行後に suspend することは文書化されているか。「まもなく」に
   相当する記述はあるか。suspend 時に WebSocket はどうなると文書化されているか
4. **帰結**: 1〜3から「ロック中に Mac 側の状態変化を反映できない」が導けるか。
   **これは事実ではなく帰結である**

**前提を疑ってよい**と明示して依頼した。「そもそも (a) と (b) は同じ制約の言い換えではないか」
といった指摘は歓迎する、と。

## 答え

**この一文は、そのままでは事実として置けない。**

主張 (b) と suspend の記述は一次情報で裏が取れた。**しかし主張 (a) の但し書き
「例外は APNs による push-to-start のみ」は誤りである。** APNs を使わずバックグラウンドで
Live Activity を開始する経路が、Apple のドキュメントに**明記で2つ**ある。
帰結 (4) は中核だけ残るが、**書かれている理由付けは成り立たない。**

**REQ-UIX-027（[0001](0001-live-activity-lock-screen-background.md)）と同型の事故が、規模を小さくして起きている。**
前提そのものは壊れていないが、**前提に付けた「〜のみ」という限定が壊れている。**

## 根拠

### 1. 開始 — 前半は文書化。**但し書きは誤り**

**「フォアグラウンドでなければ開始できない」は文書化されている。** ただし Apple 自身が
"In general" と留保を付けている。API レベルでも裏付けがある —
[`ActivityAuthorizationError.visibility`](https://developer.apple.com/documentation/activitykit/activityauthorizationerror/visibility)（iOS 16.1+）の定義は、
バックグラウンドで開始を試みたことを示すエラー、である。

**「例外は APNs による push-to-start のみ」は誤り。文書化された例外が他に2つある。**

**(i) `LiveActivityIntent`（iOS 17.0+）** —
[`Activity.request(attributes:content:pushType:)`](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:))
の Discussion は、バックグラウンドでは不可としたうえで、`AppIntents` を採用し
`LiveActivityIntent` から開始する場合を**明示的に除外している**。
[`LiveActivityIntent`](https://developer.apple.com/documentation/appintents/liveactivityintent) 側はさらに踏み込んでいる:

> "the system launches your app process without opening the app, performs the intent, and starts the Live Activity"

**(ii) スケジュール開始（iOS 26.0+）** —
[`request(attributes:content:pushType:style:alertConfiguration:start:)`](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:))。
Discussion は、指定日時になれば**アプリがバックグラウンドにあってもシステムが開始する**と述べている。
`AlertConfiguration` が必須で、開始までの `ActivityState` は `.pending`。
**これは本プロジェクトの対象バージョンちょうどで入った API である。**

**どちらも APNs もサーバーも要らない。**「完全ローカル駆動と push-to-start は二者択一」という
構図が条文の前提になっているが、**その構図自体が一次情報と合っていない。**

補強（**二次的な位置づけ**）: WWDC26 session 223 "Live Activities essentials" も開始経路を3つ
（フォアグラウンドから直接 / 事前スケジュール / プッシュ）として説明している。
**ただしこのセッションは iOS 27 向けである。** iOS 26 への適用は上記 API の availability 注記
（iOS 17.0 / iOS 26.0）で裏付けた。**セッションは根拠ではなく傍証として扱う。**

### 2. 更新 — 文書化。**ただしフォアグラウンドは要求されていない**

**問いへの直接の答えは「否」。ローカルからの更新にフォアグラウンドは要求されていない。**
[`Activity.update(_:)`](https://developer.apple.com/documentation/activitykit/activity/update(_:))
の Discussion は、フォアグラウンドでもバックグラウンドでも使えるとし、`BackgroundTasks` を例に挙げている。
[Displaying live data with Live Activities](https://developer.apple.com/documentation/ActivityKit/displaying-live-data-with-live-activities)
の本文も同様に、バックグラウンド実行中の更新・終了を認めている。

つまり **(b) の「running である間しか行えない」は正しい。** suspend 前のバックグラウンド実行中は更新できる。

**前提への指摘（1件目）**: 「(a) と (b) は同じ制約の言い換えではないか」— **違う。別の制約であり、
条文が2つに分けているのは正しい。** (a) の門は「フォアグラウンド」、(b) の門は
「running（フォアグラウンド **または** バックグラウンド）」で、**(a) のほうが狭い。**
**ここは条文を弄らないほうがよい。**

### 3. suspend — 文書化。**WebSocket の側は現行の一次情報に無い**

**suspend すること、および「まもなく」に相当する記述は文書化されている。しかも定量的である。**

[Preparing your UI to run in the background](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background)
は、フォアグラウンドを離れたアプリが短時間バックグラウンドに留まったのち UIKit に suspend される、と述べている。
より鋭いのは
[Extending your app's background execution time](https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time):

> "That method has five seconds to perform any tasks and return."

そのメソッドが戻った直後にシステムが suspended 状態へ入れる、と続く。
`beginBackgroundTask(withName:expirationHandler:)` で延長でき、残り時間は `backgroundTimeRemaining` で取れる。
**「まもなく」は既定 5 秒である。**

**suspend 時に WebSocket がどうなるかは、現行の一次情報には見つからなかった。**

[`URLSessionWebSocketTask`](https://developer.apple.com/documentation/foundation/urlsessionwebsockettask)
のページに suspend への言及は**一切ない。** 見つかった唯一の Apple 一次情報は
[Technical Note TN2277 "Networking and Multitasking"](https://developer.apple.com/library/archive/technotes/tn2277/_index.html)
だが、**`library/archive` 配下、最終更新 2011-03-30、iOS 4 世代の文書**である。
そこには、suspend 中はプロセス内のコードが実行されないこと、そしてシステムがソケットの資源を回収して
接続を閉じる**ことがある**（"may choose to"）ことが書かれている。

**「必ず切れる」とは書かれていない。「切れることがある」である。**
これを「切断される」と断定形で置くと、また出典の無い断定を作る。

**前提への指摘（2件目）**: 問いは `URLSessionWebSocketTask` を挙げているが、
**このアプリはそれを使っていない。** `PomodoroMac/PomodoroiOS/Client/MdoroClient.swift` は
Network.framework（`NWConnection` / `NWProtocolWebSocket`）である。
**`URLSessionWebSocketTask` の挙動を確定させても、このコードには適用できない。**

**ただし、この不明点は帰結を揺るがさない。** ソケットが生き残ったとしても、
**suspend 中はコードが走らないので誰も読めない。** 条文が本当に依拠すべきなのはソケットの生死ではなく、そちらである。
なお現行 UIKit ドキュメントは、バックグラウンド移行時に Bonjour サービスの登録解除と
待ち受けソケットの close を**アプリ側の作業として**挙げている。

### 4. 帰結 — **中核は導ける。書かれている理由付けは導けない**

**導けること**: iPhone アプリが suspend されている間、ローカルのコードは走らない。
よって **Mac 側で起きた予定外の状態変化を、その時点で Live Activity へ反映することはできない。**
これは (2)(3) から出る。**APNs の可否とは無関係に成立する。**
**REQ-NTF-002（MUST）の支えは崩れていない。むしろ強くなった** — 事前スケジュールが必要な理由は
「WebSocket が切れるから」ではなく「**suspend 中はコードが走らないから**」で、こちらのほうが文書化が固い。

**導けないこと、3点。**

**(a) 「例外は APNs のみ」から出る全ての推論。** 特に `SPEC.md:835` の格下げ理由と第15章 FUT-013 の位置づけ。
格下げの結論自体は (b) と suspend だけで支えられるので**結論は動かないが、根拠として (a) の但し書きを
引いている部分は差し替えが要る。**

**(b) 「できない」という絶対形。**
[`BGTaskRequest.earliestBeginDate`](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate)
は、指定日時での起動をシステムは保証せず、**それより早く始まらないことだけを保証する**、としている。
`BackgroundTasks` からの Live Activity 更新は**文書化された経路である。**
正確には「不可能」ではなく **「保証できない」** である。
**禁止されていない。当てにできないだけである。**

**(c) 「ロック中」という条件づけ。**
**Apple のどの文書にも、ロック状態を条件にした Live Activity の制約は見つからなかった。**
門は running / suspended であって locked / unlocked ではない。条文はこの2つを同一視している。
実際にはロックが背面移行を引き起こすので結果は多くの場合一致するが、**条件の名前が違う。**

**残り時間の表示そのものは、この帰結の対象外である。** REQ-UIX-021 の `Text(timerInterval:)` は
システムが自律更新するため、反映できないのは**予定外の状態変化**（一時停止・再開・延長・スキップ・中断）に限られる。
**条文の「Mac 側の状態変化」はこの区別をしていない。**

### 循環引用について

**探した。Apple の一次情報は、リポジトリのどこにも無かった。**

`0009` の出典欄は SPEC 8.3 を指し、`0030` の出典欄は `CONTEXT.md` §3 を指し、
**`CONTEXT.md:653`（「Live Activity のボタンは、suspend 中は必ず無反応になる」）も §3 を指したままである** —
**巡回している文書は3つではなく4つだった。** §3 は現在
[0038](../decisions/0038-platform-facts-are-not-the-specs-job.md) により空である。

`0030` については補足がある。**「必ず無反応になる」は、再接続を実装しない限りにおいて正しい。**
`LiveActivityIntent` の一次情報は、システムが**アプリを開かずにアプリのプロセスを起動して**
`perform()` を走らせると明記している。つまり `perform()` の実行時点ではプロセスは起きており、
**そこで再接続を試みること自体は Apple が妨げていない。** これは REQ-UIX-024 が既に条件として
書いていることと一致する。

## 確度

| 主張 | 確度 |
| :---- | :---- |
| 開始は原則フォアグラウンドに限られる（"In general" の留保つき） | **文書化** |
| **例外は APNs だけではない** — `LiveActivityIntent`（iOS 17.0+）とスケジュール開始（iOS 26.0+） | **文書化** |
| 更新にフォアグラウンドは要求されない。門は running / suspended | **文書化** |
| バックグラウンド移行後 5 秒で suspend される。`beginBackgroundTask` で延長できる | **文書化** |
| suspend 中はプロセス内のコードが実行されない | **文書化** |
| suspend 時に WebSocket が切れる | **不明**（TN2277・2011年・iOS 4・archive の "may" のみ） |
| `BackgroundTasks` からの反映は禁止されていない（保証されないだけ） | **文書化** |
| 「ロック中」を条件にした制約 | **不明**（どの文書にも見つからなかった） |
| 予定外の状態変化を suspend 中に反映できない | **帰結**（文書化された事実からの演繹） |
| `perform()` はアプリ本体のプロセスで走る（REQ-UIX-024） | **文書化・正しい** |
| 継続時間の上限 8 時間 / 計 12 時間（REQ-UIX-028） | **文書化・正しい** |

**対象バージョン**: iOS 26 / iPadOS 26。引用した記述の availability は
`visibility` = iOS 16.1、`request(...pushType:)` / `update(_:)` = iOS 16.2、
`LiveActivityIntent` = iOS 17.0、`pushToStartTokenUpdates` = iOS 17.2、
スケジュール開始 = **iOS 26.0**。**すべて iOS 26 で有効。**

**注意を1つ残す。** 記事本文（Displaying live data with Live Activities）は現在
**iOS 27 世代に改訂された版**が配信されている。本文の文言だけでは iOS 26 に当てはまる保証がないため、
**各主張は個別 API の availability 注記で iOS 26 に固定して確認した。**

## 確かめられなかったこと

**推測で埋めない。**

- **suspend 時に `NWConnection` の WebSocket が実際に切れるか。** iOS 26 についての Apple の記述は
  見つからなかった。TN2277（2011年・iOS 4・archive）が "may" と書いているのみ。**実測していない**
- **`ActivityAuthorizationError.visibility` が実際にどの条件で投げられるか。** 定義文以上の記述は無い
- **`LiveActivityIntent` を Live Activity 自身のボタン以外（コントロール等）から起動した場合の、
  iOS 26 での実挙動。** ドキュメントの記述のみ
- **スケジュール開始（iOS 26）の実挙動。** `start:` と `startDate:` の2つのシグネチャが並存し、
  `startDate:` 版には abstract が無い。**どちらが現行かを確定できなかった**
- **Live Activity の更新頻度に予算・スロットリングがあるか。** ローカル更新についての記述は
  見つからなかった（`NSSupportsLiveActivitiesFrequentUpdates` はプッシュ側の設定）

## 影響を受ける記述

**列挙のみ。直し方はこの記録では判断しない。**

| 箇所 | 理由 |
| :---- | :---- |
| `SPEC.md:818` | 「例外は APNs による push-to-start のみ」が誤り。「ロック中」という条件名も一次情報に無い |
| `SPEC.md:835` | 格下げの根拠として (a) を引いている。**結論は (b) と suspend で支えられるが、根拠の記述が誤りに依存** |
| `SPEC.md` 第15章 FUT-013 | push-to-start を唯一の将来手段としているなら、前提が (a) の但し書きと同じ |
| [0009](../decisions/0009-live-activity-should-not-must.md) 出典欄 | 「Apple の一次情報で確認済みと記録されている」— **記録は存在しなかった** |
| [0030](../decisions/0030-live-activity-is-display-only.md) 出典欄 | 「`CONTEXT.md` §3（一次情報で確認済み）」— **§3 は空** |
| `CONTEXT.md:653` | 「§3」への参照が切れている。**巡回の4本目** |
| REQ-NTF-002 | **支えは崩れていない。** ただし根拠は「WebSocket が切れる」ではなく「**suspend 中はコードが走らない**」に置き換わる |
| REQ-UIX-024 | `perform()` がアプリ本体のプロセスで走る点は**一次情報で確認できた。正しい** |
| REQ-UIX-028 | 8時間・計12時間の上限も**確認できた。正しい** |
