# CONTEXT — 現在有効な方針と状態

このファイルは**今の状態だけ**を書く。経緯は書かない。経緯が必要なら `docs/decisions/` を参照する。

- 要件の正本: `SPEC.md`（v2.7、234要件）
- 運用の正本: `CLAUDE.md`
- 判断と意図の正本: `docs/decisions/`
- ビルド手順・環境: `docs/DEVELOPMENT.md`

---

## 1. 動かしてはいけない原則

| 原則 | 根拠 |
| :---- | :---- |
| **`Task.md` へは一切書き込まない。** 実績は `PomodoroLog.md` へ挿入のみ（既存行の書き換え・削除は禁止）。ブックマークは `securityScopeAllowOnlyReadAccess` で読み取り専用として生成し、OS レベルでも担保する | [0002](decisions/0002-task-md-read-only.md) |
| **状態の正本は Mac。** iPhone は表示上のカウントダウン補間はしてよいが、**セッションの終了を確定してはならない。** 周回数の加算・ログ記録の判断は Mac だけが行う | [0001](decisions/0001-mac-as-single-source-of-truth.md) |
| **時間は絶対時刻基準。** 残り秒数を同期しない。`sessionEndAt` を配って各端末が算出する。残り時間の算出には単調時計、`sessionEndAt` の生成とログ表記には壁時計を使う | [0001](decisions/0001-mac-as-single-source-of-truth.md) |
| **色リテラルをビューに書かない。** 役割名（`sessionFocus`, `warning`, `danger`, `textPrimary`）で参照する | [0007](decisions/0007-oklch-color-system.md) |
| **共有できるコードは必ず `PomodoroCore` に置く。** 状態機械・通信プロトコル・データモデルを Mac 版と iPhone 版で二重に実装しない | REQ-PRT-001 |

### 設計方針（GitHub で OSS として公開する）

想定利用者は **Markdown でタスクを管理するエンジニア・パワーユーザー**。
公開を前提とするため、次の3点は機能の追加より優先する。

| 方針 | 具体化 |
| :---- | :---- |
| **弁える。** 利用者の私生活が外に出る動作をしない | 診断ログに利用者由来の文字列を書かない（[0018](decisions/0018-diagnostic-log-policy.md)）。テレメトリ・アカウント・クラウド同期を持たない |
| **透明である。** 起きたことと、起きなかった理由を明示する | 外の世界に触れる操作の失敗は必ず画面か通知に出す（下の「失敗を黙らせない」）。記録しないと決めたことは設定画面に明記する |
| **簡潔で直感的な意匠に統一する** | 役割名で色を参照する（[0007](decisions/0007-oklch-color-system.md)）。標準的な設定項目は満たす（[0016](decisions/0016-standard-settings-and-hotkeys.md)）。似た機能に似た見た目を与える |

**公開の前提**（[0021](decisions/0021-published-as-oss-named-mdoro.md) / [0022](decisions/0022-english-only-ui.md) / [0023](decisions/0023-markdown-first-not-obsidian-first.md)）

| 項目 | 決定 |
| :---- | :---- |
| 名称 | **Mdoro**。名前に "Pomodoro" を含めない |
| 対象 | **Markdown でタスクを管理する人。** Obsidian か Logseq かは問わない |
| 立ち位置 | **特定ツール専用ではない。** Obsidian を標準であるかのように書かない。Obsidian 固有の記法（ブロック ID・内部リンク）は任意の互換機能として維持する |
| 言語 | **アプリが生成する文字列は英語のみ。** 外部ファイル由来の文字列と利用者の入力はそのまま扱う。コードコメントと `docs/` は日本語のまま |
| 収益 | **広告・課金・計測なし**（REQ-NFR-008）。支援リンクは設定の About に1つだけ、テキストで、URL を示して置く。集中を切る場所には出さない |
| ライセンス | **MIT** |
| 改名 | **全範囲**（表示名・bundle ID・ターゲット名・モジュール名・Bonjour サービス型まで。[0024](decisions/0024-rename-everything-to-mdoro.md)） |
| 読む記法 | **標準のチェックボックス記法のみ**（[0025](decisions/0025-standard-checkbox-syntax-only.md)）。Obsidian のブロック ID は維持 |

### スコープ外（やらない。提案もしない）

- クラウド同期、アカウント、APNs（完全ローカル駆動の原則）
- タスクファイルの編集機能（タスクの作成・完了は利用者の Markdown エディタ側の操作）
- iPad / Apple Watch、複数クライアント同時接続、LAN 外からの接続
- **英語以外の UI 言語**（[0022](decisions/0022-english-only-ui.md)）
- **広告・アプリ内課金・利用計測**（[0021](decisions/0021-published-as-oss-named-mdoro.md)）

---

## 2. 実装で壊しやすい6箇所

**すべて、実際に一度壊れた箇所である。** レビューで検出して修正済み。再発させないこと。

1. **`committedAt` を見て確定処理を冪等に行う。**
   これが無いと、休憩セッションが `FINISHED` に留まる間の `abort` / `startWork` / `resetLoopCount` で
   **ログが二重に書かれる**（4経路）。復帰時の記録漏れも起きる（3経路）。
   一度「フィールドはあるが一度も代入されない」状態で実装され、冪等性が偶然に依存していた。

2. **`nextSessionType` は「現在のセッションが完了したと仮定したときの次」。**
   「直前のセッション」基準にすると、開始時に事前スケジュールする通知へ誤った種別が載る。
   倍数判定は `loopCount + 1` に対して行う（`loopCount = 0` はあらゆる `longBreakInterval` の倍数なので、
   0 のまま判定するとリセット直後に長い休憩が提案される）。

3. **状態遷移マトリクス（仕様書 4.6）は受理可否のみ。**
   `canAccept(action, state) -> Bool` と `apply(action) -> Effects` を分離する。
   副作用をマトリクスに書くと、設定の適用範囲（9.5 の A/B/C 群）や周回数の規定と衝突する。
   実際に v2.4 でマトリクスを新設した際、既存要件と9箇所衝突した。

4. **`FINISHED` からの脱出先は常に `IDLE`。** 確定と同時に遷移する。

5. **ログのタスク名はセッション開始時点のスナップショット**（`selectedTaskSnapshot`）。
   `FINISHED` 中に選び直しても反映しない。作業していないタスクが記録されてしまう。

6. **設定変更で実行中の `sessionEndAt` を変えない。**
   長さの変更は「延長」操作に一本化。事前スケジュール済みのローカル通知との整合が崩れるため。

### ビューに Timer を置くと表示が止まる

`MainWindowView` / メニューバーのラベルに `Timer.publish(...).autoconnect()` を `.onReceive` で
張ったところ**発火せず、残り時間の表示が固まった**（実機で確認）。
時計は `AppModel.displayNow` が進める。**ビュー側で時間を持たない。**
状態の正本が Mac にある以上（3原則の2つ目）、表示用の現在時刻もモデルが配る。

### サンドボックスの許可はファイル単位では足りない

ログの原子的書き込み（REQ-LOG-004 / REQ-PLT-004）は、ログ本体と**同じフォルダに一時ファイルを作る**。
ファイル単位のセキュリティスコープ付きブックマークではこれができない
（`You don't have permission to save the file ".PomodoroLog.md.<uuid>.tmp" in the folder`）。
**出力先はフォルダを選ばせ、フォルダのブックマークを持つ**（[0015](decisions/0015-log-folder-scoped-access.md)）。
`Task.md` 側は読むだけなので、ファイル単位のままでよい。

### 拡張の最低 iOS バージョンを本体と揃える

Widget 拡張の `IPHONEOS_DEPLOYMENT_TARGET` が端末の iOS より新しいと、
**iOS は拡張の登録を黙って拒否する。** アプリ本体は普通に動くため、
「アプリは動くのに拡張だけ存在しない」という切り分けにくい状態になる。

実機で踏んだ（拡張 26.5 / 端末 26.4.2）。ウィジェットギャラリーにも出ず、
`Activity.request` は成功するのに Live Activity が描画されなかった。
**シミュレータ（26.5）では条件を満たすため再現しない。**
ターゲットを増やしたら、最低 iOS バージョンが本体と揃っているか必ず確認する。

### 失敗を黙らせない

このリポジトリで同じ失敗を3回した。**`try?` で握り潰した結果、
「動かないが理由が分からない」状態を作った。**

- ログ書き込み（工程4）: 書けなくても通知も表示も痕跡もなかった
- Live Activity（工程8）: `Activity.request` の失敗理由を捨てていた
- 同上: 状態を持つ型を `@Observable` にせず、画面が理由を読み直さなかった

**外の世界に触れる操作の失敗は、必ず画面か通知に出す。** 正常時は黙ってよい。

### 検証ビルドで、ユーザーのビルド成果物を上書きしない

`xcodebuild ... CODE_SIGNING_ALLOWED=NO` は既定の DerivedData へ書くため、
**Xcode で署名して作った成果物を、署名の無いビルドで置き換える。**
利用者がそのまま起動すると ad-hoc 署名のアプリが動き、次の節の理由で通知が一切届かない。
原因究明に往復を要した（2026-08-27）。

**検証ビルドは `-derivedDataPath` を作業用ディレクトリへ向けること。**

### 通知には正しい署名が要る

`UNUserNotificationCenter.requestAuthorization` は、**ad-hoc 署名（linker-signed）の
アプリバンドルでは失敗する。** 権限は `notDetermined` のまま動かず、
`add()` は成功したように見えて何も配信されない。設定にもアプリが現れない。

`codesign -dv` で `Signature=adhoc` かつ `Identifier` がバンドル ID と食い違っていたら、これ。
Xcode から実行して署名し直せば直る。**再調査しない。**

### 前面にいるあいだ、通知は出ない

macOS も iOS も、**アプリが最前面のあいだは `UNUserNotificationCenterDelegate.willPresent` が
無ければ通知を出さない。** バナーも音も出ない。設定も権限も正しいので、原因が見えない。

iPhone 側には工程7で置いたが **Mac 側に無く**、「Focus が終わっても Mac だけ鳴らない」
になっていた（2026-08-27、実機で報告）。**片方のプラットフォームで踏んだ穴は、
もう片方も見に行くこと。**

音が鳴らない原因は OS 設定側にもありうる（通知そのものの不許可・バナー切り・通知音切り）。
`UNUserNotificationCenter.notificationSettings()` で読めるので、**読んで画面に出す。**

### 未接続のまま、手元の状態を外へ出さない

iPhone は起動時に**最後に受け取ったスナップショットを復元する**（REQ-PER-010）。
これは画面に「最後に確認した状態」として出すためのもので、**何時間前のものか分からない。**

これを Live Activity へ流していた。結果、**とうに終わったセッションが、
正しい顔で、動かないままロック画面に居座った**（2026-08-27、実機で報告）。
`staleDate` を今から90秒後に置いていたので、古い情報が「新鮮」として提示されていた。

**外へ出してよいのは、接続中に受け取った状態だけ。** 状態の正本は Mac である（3原則の2つ目）。
手元にある値は、繋がっていない間は「最後に見た値」でしかない。

同じ理由で、`ContentState.isConnected` に**スナップショットの中の接続状態を入れない。**
あれは Mac が自分について語った値で、受け取れなくなった後も真のまま残る。

### プロセスが落ちても Live Activity は残る

アプリが終了しても、Live Activity はロック画面に残る。起動し直したときに
`Activity.activities` から**拾い直さないと、凍ったままの古い1件の横に新しい1件が並ぶ。**
`end()` は自分が握っている1件だけでなく、**OS 上にあるものを全部畳む。**

### staleDate は「経過時間」ではなく「保証の期限」

`staleDate` は**次に状態を確認できる保証がない時刻**であって、
最後に状態が変わってからの経過時間ではない。
状態同期は変化時のみ（REQ-COM-006）なので、押し出す処理を別に回さないと、
**前面で接続も生きている正常な走行中に 90 秒で「情報が古い可能性があります」が出る**（2026-08-27、実機）。
アプリが suspend されれば押し出しごと止まり、そこで初めて陳腐化する — それが本来の意図。

### ネットワークのコールバックから MainActor を読まない

`NWListener` / `NWConnection` のハンドラは自前のキューで走る。
そこから `MainActor.assumeIsolated` を呼ぶと**トラップして落ちる**（実際に落とした）。
`/info` の応答のようにネットワーク側で組み立てる値は、
**MainActor 側から押し込んでおき、ハンドラはロック越しに読むだけ**にする。

### SF Symbol 名は実在を検証する

存在しない名前を `Image(systemName:)` に渡しても**エラーにならず、何も描かれない。**
`timer.slash`（実在しない）を指定してメニューバー項目が消えた。
`PomodoroCore` の `SymbolNameTests` が全名称の実在を検証している。名前を増やしたらそこに足す。

### 似た名前の2つのタスク名スナップショット

- `TaskContext.selectedTaskSnapshot` — **再読み込みのたびに最新へ更新される**（現在選ばれているものの表示名）
- `TimerContext.sessionTaskSnapshot` — **セッション開始時に凍結される**（ログに記録するもの）

ログ行を組むときに前者を読むと、上の6箇所の5番目が破れる。
`LogEntry` を組み立てるのは `TimerEngine` 側だけにし、**UI 層が `TaskContext` から直接ログ行を作らないこと。**

### 色の役の取り違え

各色相は `subtle` / `line` / `graphic` / `solid` / `text` の5役を持つ。**役を取り違えるとコントラスト保証が消える。**
進行リングなど意味を持つ図形は `-graphic`、文字が乗る塗りは `-solid`、背景上のテキストは `-text`。
セッション3色（藍 / 青磁 / 黄土）は**絶対輝度に段差がある。**
同一明度に揃えると色覚多様性下で識別できなくなる。定義は仕様書 8.5 節、意図は [0007](decisions/0007-oklch-color-system.md)。

### 仕様書を変更するとき

**必ず影響する他章を確認してから**変更する。過去に2回、1章だけ編集して矛盾を作っている
（v2.1 のプリセット追加、v2.4 の状態遷移マトリクス新設）。
特に**第4章・第5章・第7章・第9章・第10章・第11章は互いに強く結合している。**

---

## 3. Apple プラットフォームの確定事項

**一次情報で確認済み。回避策を探し直さないこと。** ここを再調査する提案は不要である。

- **Live Activity はアプリがフォアグラウンドの間しか開始できず、更新もアプリが running の間だけ。**
  iOS はバックグラウンド移行後まもなく suspend する。完全ローカル構成でロック中の反映は**不可能**。
  `staleDate` / `isStale` で陳腐化を示す設計にしてある。**ここを MUST 要件に戻さないこと**（[0009](decisions/0009-live-activity-should-not-must.md)）。
- **iPhone の通知を WebSocket に依存させない。** `sessionEndAt` に対する絶対時刻のローカル通知
  （`UNCalendarNotificationTrigger`）として事前スケジュールする。
  バックグラウンドでは WebSocket が切れるため、これ以外に手段がない。
- **ATS は IP アドレス直接接続を既定で拒否する**（iOS 17 / macOS 14 以降）。`NSAllowsLocalNetworking = YES` が必須。
  残りの Info.plist キーと entitlements は**仕様書 3.5 節**。
  **1つ欠けると「繋がらない」が起き、原因の切り分けに時間を取られる。コードより先に設定を通す。**
- **ローカルネットワーク許可の状態を問い合わせる API はない。** `NWBrowser` の `-65570` と
  `NWConnection` の `.localNetworkDenied` で検出する。
  初回許可取得は必ずフォアグラウンドで行う（バックグラウンドだとダイアログなしで黙って拒否される）。
- **サンドボックス下の原子的書き込みは同一ディレクトリ内**で `FileManager.replaceItemAt` を使う。
  `/tmp` を跨ぐ rename は失敗する。
- **ファイル監視は記述子ではなく親ディレクトリに張る。**
  Obsidian は一時ファイル経由で保存するため、記述子に張った監視は inode 差し替えで無効化される。
- **Xcode 26.3 以降には MCP サーバーがある**（`xcrun mcpbridge`）。
  ビルド・テスト・SwiftUI プレビュー取得が可能（要: Xcode でプロジェクトを開いた状態）。
- **`MenuBarExtra` のラベルを毎秒更新しても安定する。** 実測（2026-08-26、Debug ビルド、
  3時間のセッションを進行させた状態）で CPU 0.1〜0.4%、RSS は約2.5分間で増加なし（むしろ 13MB 減）。
  `NSStatusItem` へ移す必要はない。**再測定しない。**
- 署名は無償の Personal Team。**iPhone 実機のアプリは7日で失効する。**
  Push 通知と iCloud は使えないが、本仕様は使わない（ローカル通知に capability は不要）。

---

## 4. リポジトリ外の成果物

Git に入っていないため、失われると復元できない。

- **カラーシステムのリファレンス**（トークン一覧・コントラスト実測・色覚シミュレーション付き）
  https://claude.ai/code/artifact/ff49365a-63a3-4942-b4cc-4c1a10ac7383
- **Xcode セットアップ手順書**
  https://claude.ai/code/artifact/79598e4c-33c6-49c6-aaeb-aa64e2cc6f3b

---

### 標準的な設定項目は満たす

仕様書は**このアプリに固有の要件**を定めるものであり、UI の網羅リストではない。
「ログイン時に起動する」のような、どのアプリにもある設定は**記載がなくても用意する**
（[0016](decisions/0016-standard-settings-and-hotkeys.md)）。
見送るときは理由を残す。

## 5. 未決事項

`CLAUDE.md`「未決事項の扱い」により、**これらに触れる実装は止めて報告する。** 推測で埋めない。

| ID | 内容 | いつ決める |
| :-- | :---- | :-- |
| OPEN-002 | **アプリ全体のタイポグラフィ・スケール**（数字書体・等幅の可否・ウェイト・段階）。集中表示ビュー（REQ-UIX-010）を含む | 工程11の着手前 |
| OPEN-020 | 支援リンク（Buy Me a Coffee）の URL | 工程12 |
| OPEN-021 | 配布形態。ソースからのビルドのみか、有償の Developer Program を取って署名済み成果物を配るか | 工程12 |
| OPEN-004 | 無制限モード（REQ-TIM-045）実装時の Live Activity 再開方法 | 該当機能の実装時 |
| OPEN-011 | `--border-strong` が WCAG 1.4.11 の 3.0 を満たすのは `--bg` 上のみ（ライト 3.10 / ダーク 3.30）。`--surface-raised` 上では 2.91 / 2.68 に落ちる。仕様書は `-strong` の保証面を規定していない。**工程4では顕在化しなかった**（設定画面の入力欄はシステム標準のコントロールを使い、`-strong` を自前で描いていない）。枠を自前で描く場面が来たら判断が要る | 工程11（8.6 で枠を規定するとき） |

---

## 6. 現在の作業状態

**最終更新: 2026-08-27**

### 完了

- `PomodoroCore` の状態機械（仕様書 第4章・9.5・10.3 相当）
  - `TimerEngine` / `TimerContext` / `PresetContext` / `Preset` / `Effect` / `TimerAction` /
    `SessionType` / `StateTransitionMatrix` / `PreNotification`
  - ファイル I/O・ネットワーク・UI は含まない。ログ確定は `Effect.commitLog` として呼び出し側へ渡す
- **v2.6 への追従完了。** REQ-TIM-043（猶予1分）/ REQ-TIM-046（延長受付ウィンドウ）/
  `extendWindowClosed` / `Preset.preNotifications`（REQ-NTF-020〜023 の発火時刻決定を含む）
- **`swift test` 45テスト全通過**（9スイート、2026-08-26 実行）
- 開発体制の移行（[0011](decisions/0011-claude-code-as-orchestrator.md)）
- 予告通知の数値の刻みを確定（[0012](decisions/0012-prenotification-value-grid.md)）
- **工程1 完了**: 色トークン（8.5.3 全トークン・ライト/ダーク）、役割マッピング（8.5.4）、
  コントラストと ΔE の自動検証（REQ-COL-020）、絶対輝度の段差の検証（REQ-COL-021）
  — `Sources/PomodoroCore/Color/`。SwiftUI への橋渡しは `#if canImport(SwiftUI)` で同居
- **工程2 完了**: 復元判定（REQ-PER-003 (a)〜(d)）、日跨ぎの自動確定（REQ-PER-004）、
  PENDING_DECISION 遷移時の通知取り消しと Live Activity 終了（REQ-PER-008 / 009）、
  状態の永続化（REQ-PER-001 / 002）— `Sources/PomodoroCore/Persistence/`
- **工程3（ドメイン層）完了**: タスクのパースと ID（REQ-TSK-010〜015, 020〜023）、
  選択状態と追従（REQ-TSK-030〜036）、ファイル監視（REQ-TSK-002 / REQ-PLT-006）、
  ログの整形と挿入（REQ-LOG-001〜004, 010〜013, 016〜019, 022, 023）、
  再試行キュー（REQ-LOG-005 / REQ-ERR-004）、読み込みの頑健性（REQ-ERR-001〜003）
- 通知音をシステムサウンドに確定（[0017](decisions/0017-system-notification-sounds.md)）、
  グローバルショートカット2種（一時停止/再開・ウィンドウ前面）、ログイン時起動
  （[0016](decisions/0016-standard-settings-and-hotkeys.md)）
- **工程8 完了（Live Activity）**: ロック画面・ダイナミックアイランド（REQ-UIX-020〜029）、
  `Text(timerInterval:pauseTime:countsDown:)` による自律更新（REQ-UIX-021）、
  `staleDate` / `isStale` の陳腐化表示（REQ-UIX-023）、`LiveActivityIntent`（REQ-UIX-024）、
  タスク名の打ち切り（REQ-UIX-025）、`PENDING_DECISION` での終了（REQ-PER-009）
  — `Sources/PomodoroCore/LiveActivityAttributes.swift`,
  `PomodoroiOS/Client/LiveActivityController.swift`, `PomodoroWidget/PomodoroWidgetLiveActivity.swift`
  - **実機で確認**: ロック画面で Live Activity が 0:00 まで自律カウントダウンし、
    **同時に終了通知（第5章）が届く**。Decision 0009 の「両者を独立させる」がそのとおり成立している
- **工程7 完了（iPhone の通知）**: 絶対時刻のローカル通知として事前スケジュール（REQ-NTF-002）、
  発火時刻・内容の変化での再スケジュール（REQ-NTF-003）、通知内容（REQ-NTF-004）、
  予告通知（REQ-NTF-007 / 020〜023）、`DateComponents.timeZone` の明示（REQ-COM-014）、
  PENDING_DECISION での取り消し（REQ-PER-008）、通知タップ後の「同期中」表示（REQ-NTF-011）
  — `PomodoroiOS/Client/NotificationScheduler.swift`
  - **実機で確認したのはセッション終了通知のみ**。予告通知は発火時刻の算出（`PreNotificationSchedule`）が
    単体テスト済みで、スケジュール経路は終了通知と同じだが、通しでは未確認
- **工程6 完了（iOS アプリ）**: Bonjour 探索と接続（REQ-COM-003 / 004）、
  時刻同期の適用（REQ-COM-009）、切断中の表示と操作無効化（REQ-COM-011〜013）、
  ペアリング入力（REQ-SEC-001）、Keychain でのトークン保持、
  通常画面（8.1）、集中表示ビュー（8.2 / REQ-UIX-010〜014）、
  最後の状態の永続化と取得時刻の併記（REQ-PER-010 / 011）
  — `PomodoroMac/PomodoroiOS/`
  - UI 文字列は **String Catalog**（`Localizable.xcstrings`）経由。英語一本化は工程10
- **工程5 完了（通信層・Mac 側）**: プロトコル（第10章）、時刻同期（REQ-COM-007〜009）、
  再接続バックオフとハートビート（REQ-COM-004 / 005）、Bonjour 広告と `GET /info`（REQ-COM-002 / 003）、
  WebSocket サーバー、ペアリングと認証（REQ-SEC-001〜004）
  — `Sources/PomodoroCore/Protocol/`, `PomodoroMac/Server/`
- **工程4 完了（Mac UI）**: メニューバー常駐と表示密度（REQ-UIX-030〜032, 035）、
  メインウィンドウ（REQ-UIX-001〜009, 036）、設定画面とプリセット編集（9.2 / 9.3 / REQ-PRS）、
  Mac 側通知（REQ-NTF-001, 004〜007, 020〜023）、アイドルスリープ抑止（REQ-PER-006）、
  読み取り専用ブックマーク（REQ-PLT-003 / 005）、工程3から持ち越した
  REQ-TSK-004 / 005 / 016 / 024・REQ-LOG-020 / 021 — `PomodoroMac/PomodoroMac/`
  — `Sources/PomodoroCore/Tasks/`, `Sources/PomodoroCore/Log/`
  - **工程3で完了していない第6章・第7章の要件**（いずれも UI・通信・アプリ層に属する）
    | 要件ID | 内容 | 実装する工程 |
    | :-- | :---- | :-- |
    | REQ-PLT-003 / 005 | 読み取り専用ブックマークとスコープの対呼び出し。ファイル選択 UI が要る | 工程4 |
    | REQ-TSK-004 / 005 / 016 / 024 | 一覧の閲覧・選択、パス選択、0件時の案内、ブロックIDの案内 | 工程4 |
    | REQ-LOG-014 / 020 / 021 | 日次サマリ、同時編集の注意書き、パスのバリデーション UI | 工程4 |
    | REQ-TSK-037 | `taskList` メッセージへの打ち切り情報の同梱（値は `TaskParseResult` にある） | 工程5 |
    | REQ-LOG-015 | Dataview 形式での出力（MAY） | 見送り |

### 開発工程（2026-08-26 承認）

**Mac 単独で完結して使えるものを先に作り、iPhone を後から足す。**
状態の正本が Mac にあるため（[0001](decisions/0001-mac-as-single-source-of-truth.md)）、
Mac 側だけで実用になる。ファイル安全性とログ形式という最も壊すと痛い部分を、
通信の複雑さが乗る前に実地で検証できる。

**M1: Mac 単独で実用になる**

| 工程 | 内容 | 前提 |
| :-- | :---- | :---- |
| 1 | 色トークンの定義 + ΔE / コントラストの自動検証（8.5・REQ-COL-020） | — |
| 2 | 永続化・復元（第11章） | — |
| 3 | Obsidian 連携（第6章 タスクパース・ファイル監視、第7章 ログ書き込み） | entitlements |
| 4 | Mac UI（メニューバー + メインウィンドウ、8.4）+ Mac 側通知（第5章の一部） | 工程1・2・3 |

工程1が先頭なのは、`CLAUDE.md` が色リテラルを禁じているため、トークンが無いと UI に着手できないから。

**M2: iPhone が繋がる**

| 工程 | 内容 | 前提 |
| :-- | :---- | :---- |
| 5 | 通信層（第3章・第10章）+ ペアリングと認証（第12章） | entitlements、M1 |
| 6 | iOS アプリ（表示・操作、集中表示ビュー 8.1・8.2） | 工程5、**OPEN-002** |
| 7 | iPhone のローカル通知（第5章、予告通知の実配線） | 工程5 |
| 8 | Live Activity（8.3） | 工程6・7、Widget への `PomodoroCore` リンク |

**M3: 公開できる状態にする**（2026-08-27 決定）

アプリとしての機能は工程8で揃った。ここから先は**機能を足さない。**
名前・言葉・見た目・公開の体裁を整える工程である。

| 工程 | 内容 | 前提 |
| :-- | :---- | :-- |
| 9 | **名前と立ち位置**（`Mdoro` への改名、Obsidian 前提の文言の掃除） | [0024](decisions/0024-rename-everything-to-mdoro.md) / [0025](decisions/0025-standard-checkbox-syntax-only.md)、Xcode 操作 |
| 10 | **英語一本化**（アプリが生成する文字列をすべて英語へ） | 工程9 |
| 11 | **デザイン定義の補完と両端末の統一**（8.6 の新設、Live Activity の是正） | 工程10、OPEN-002 |
| 12 | **公開の体裁**（README・ライセンス・issue テンプレート・支援リンク・配布） | 工程11、OPEN-020 / 021 |

**この順序である理由。** 名前と立ち位置が決まらないと文言が書けず、文言が決まらないと
レイアウトの寸法が決まらない。逆順にやると同じ画面を3回書き直すことになる。

#### 工程9 — 名前と立ち位置

1. **改名は全範囲**（[0024](decisions/0024-rename-everything-to-mdoro.md)）。**Xcode 操作は1回にまとめて人間へ依頼する**
   （bundle ID 3つ・ターゲット名・スキーム・フォルダ名・モジュール名。[0013](decisions/0013-pbxproj-is-owned-by-xcode.md)）。
   **bundle ID が変わるので、通知の許可は取り直しになる**（§3「通知には正しい署名が要る」）
2. コード側で機械的に追随するもの: **Bonjour サービス型**（`_pomodoro._tcp`）、Keychain のサービス名、
   状態ファイルの置き場所、診断ログの出力先（`~/Library/Logs/Pomodoro`）、ログファイルの既定名（`PomodoroLog.md`）。
   **どれも「両端で一致していないと繋がらない・読めない」もの。片方だけ変えない**
3. **移行コードは書かない。** 未リリースであり、利用者（＝作者）は再ペアリングと設定のやり直しで足りる。
   これを工程9の完了条件に含める
4. 仕様書の Obsidian 前提の文言を掃除する（第2章・第6章・第7章）。
   REQ-PLT-006 の「Obsidian は一時ファイル経由で保存する」は**技術的事実として残す**（[0023](decisions/0023-markdown-first-not-obsidian-first.md)）
5. UI 側の Obsidian 断定を外す（REQ-TSK-024 の案内、REQ-LOG-020 の注意書き）
6. **読む記法は標準のチェックボックスのみ**（[0025](decisions/0025-standard-checkbox-syntax-only.md)）。第6章 6.2 をツール名ではなく記法基準の書き方へ

**検証**: `swift test` / 両ターゲットのビルド / **iPhone と再ペアリングして接続できること**（サービス型を変えたため）

#### 工程10 — 英語一本化

1. **先に置き換え表を作り、通してから流す。** 日本語の文字列リテラルは約290箇所
   （Mac 183 / iOS 69 / Widget 7 / Core 27。2026-08-27 実測）
2. **`PomodoroCore` から着手する。** 既定プリセット名（「標準」）・接続状態・ログ整形・
   `TaskParser.uncategorizedSection`（「（未分類）」）は**両端末に出る**
3. Mac の文字列を String Catalog へ集約する（iOS は既に経由済み）。**開発言語を英語にし、カタログは残す**
   （[0022](decisions/0022-english-only-ui.md)）
4. ログ出力の英語化（`(Mon)` / `Skipped` / `Aborted` / `Loop n/m` / `(+Nm extended)`）。
   **過去の行は書き換えない**（第14章）。既存の見出しは日付で一致するので壊れない（[0014](decisions/0014-log-day-heading-matching.md)）
5. 診断ログのヘッダとイベント名を英語へ。[0018](decisions/0018-diagnostic-log-policy.md) の
   「公開の issue にそのまま貼れる」前提はここで完成する
6. **エラー文言は理由を残したまま訳す。** 短くするために理由を落とさない（§2「失敗を黙らせない」）

**検証**: `swift test`（`LogFormatter` と診断ログのテストは期待値を持つので同時に更新）、実機でログ1行と通知1件を目視

#### 工程11 — デザイン定義の補完と両端末の統一

**8.5 は色しか定めていない。** 統一に着手する前に、足りない定義を埋める。

| 不足しているもの | 現状 | 決め方 |
| :---- | :---- | :---- |
| タイポグラフィ | 定義なし。集中表示ビューの相対規定（REQ-UIX-010）だけがある | **相談する**（OPEN-002） |
| コントロールの状態 | `-subtle-hover` / `-solid-hover` / `--focus-ring` / `--text-disabled` はあるが、押下・選択・無効の**組み合わせ方**が未定義 | 裁量で決めて事後報告 |
| 余白・角丸・階層 | 定義なし | 裁量で決めて事後報告 |
| コンポーネントの目録 | 定義なし（ボタン種別・チップ・行・バナー・空状態・シート） | 裁量で決めて事後報告 |
| 「統一」の定義 | なし | 下記を提案として採る |

**状態はトークンを増やさず、既存トークンの組み合わせで表す。** トークンを増やすと
8.5.3 の全コントラスト表と REQ-COL-020 の自動テストに波及する。色の保証を触らずに状態を足せる形にする。

**統一とは「同じ役割に同じ色・同じ言葉・同じ情報の並びを与えること」であって、
Mac を iPhone に似せることではない。** 器（コントロール）は各 OS の作法に従う。
iPhone はリスト、Mac は Form のまま、意味だけを揃える。

成果は仕様書 **8.6「コンポーネントと状態」**として新設し、要件 ID を採番する。

**Live Activity の是正**（同工程。症状は2つあり、性質が違う）

- **(a) 誤った時間が表示され、経過しない** — これは不具合。**工程11 を待たずに単独で直してよい**
- **(b) テキスト・アイコン・ボタンが隠れる、余白が半端** — これは設計。デザイン統一と一緒に見る

(a) の切り分け順:

1. **拡張のバイナリが最新か。** 古い拡張が残ると古い描画のまま動く（§2「拡張の最低 iOS バージョン」と同じ落とし穴）
2. `ContentState` に渡している `sessionStartedAt` / `sessionEndAt` / `pauseTime` の実値を診断ログへ出す
3. **表示が止まるのは `pauseTime` が入っているときだけ。** `runState` の取り違えを疑う
4. `Text(timerInterval:)` の**幅不足による打ち切り**（`compactTrailing` の `maxWidth: 44`、
   ロック画面の `HStack` でボタンと幅を取り合っている）

(b) の方針: **ロック画面とダイナミックアイランドは高さが固定で、入らないものは黙って消える。**
行数を先に決めてから中身を入れる。現状の展開表示は bottom 領域にタスク名・陳腐化注意・ボタンを積んでおり、
3つ同時には入らない。

#### 工程12 — 公開の体裁

1. **README（英語）**: 何であるか / **何でないか**（クラウドなし・LAN のみ・md 全般）、対応 OS、
   ビルド手順、**読む記法をそのまま書く**（[0025](decisions/0025-standard-checkbox-syntax-only.md)）、
   **記録しないものの明記**、支援リンク。**Obsidian を標準として書かない**
2. LICENSE（**MIT**）、`SECURITY.md`（ペアリングと認証の説明）
3. **issue テンプレートに診断ログの貼り付け欄を置く。**
   [0018](decisions/0018-diagnostic-log-policy.md) はこのために設計してある（利用者由来の文字列を含まないので、そのまま貼れる）
4. CI: `swift test`（macOS ランナー）
5. スクリーンショット（工程11 の後に撮る）
6. 支援リンクの実装（About。URL は OPEN-020）
7. 配布（OPEN-021）。ソースからのビルドのみなら、**7日で失効すること**を README に書く
8. `docs/` は日本語のまま公開する。README にその一文を置く

#### 人間の Xcode 操作が要る作業

[0013](decisions/0013-pbxproj-is-owned-by-xcode.md) により、次は私が行わない。**止めて依頼する。**

- bundle ID・ターゲット名・スキーム名・フォルダ名・モジュール名の変更（工程9。[0024](decisions/0024-rename-everything-to-mdoro.md)）
- アプリアイコンの差し替え（工程11・12）
- capability・署名・配布設定の変更（工程12、OPEN-021 が有償 Program の場合）

### 既知の不具合

**2026-08-27、実機で報告。工程11 で扱う。**

| 症状 | 性質 | 状態 |
| :---- | :---- | :---- |
| Live Activity が**誤った時間を表示し、経過もしない** | 不具合 | **修正済み**（2026-08-27）。原因は上の2つの罠。**実機での確認は未了** |
| Live Activity のテキスト・アイコン・ボタンが隠れる、余白が半端 | 設計 | 工程11。デザイン統一と一緒に見る |

**アイコンそのものは問題ないと報告を受けている。** 直すのは配置と寸法。

工程11 で見る配置の問題（把握済み）:

- 展開したダイナミックアイランドの bottom 領域に、タスク名・陳腐化注意・ボタンを積んでいる。**3つは入らない**
- `compactTrailing` の `maxWidth: 44` は、1時間を超えるセッション（`1:05:00`）で足りない。
  Focus は最大180分まで設定できる
- ロック画面の余白は `.padding()` 任せで、システム側の余白と二重になっている

### 実装しない / 見送り

- REQ-UIX-034（Mac のフローティングウィンドウ、MAY）— 見送り
- **REQ-LOG-014（前日の日次サマリ、SHOULD）— 実装しない**（2026-08-26 決定）。
  設定 UI からも外した。将来必要になれば、前日ぶんの集計にログの読み戻しが要る
- REQ-LOG-015（Dataview 形式での出力、MAY）— 見送り
