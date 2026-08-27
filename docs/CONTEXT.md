# CONTEXT — 現在有効な方針と状態

このファイルは**今の状態だけ**を書く。経緯は書かない。経緯が必要なら `docs/decisions/` を参照する。

- 要件の正本: `SPEC.md`（v2.6.1、232要件）
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

### スコープ外（やらない。提案もしない）

- クラウド同期、アカウント、APNs（完全ローカル駆動の原則）
- `Task.md` の編集機能（タスクの作成・完了は Obsidian 側の操作）
- iPad / Apple Watch、複数クライアント同時接続、LAN 外からの接続

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

### 前面にいるあいだ、通知は出ない

macOS も iOS も、**アプリが最前面のあいだは `UNUserNotificationCenterDelegate.willPresent` が
無ければ通知を出さない。** バナーも音も出ない。設定も権限も正しいので、原因が見えない。

iPhone 側には工程7で置いたが **Mac 側に無く**、「Focus が終わっても Mac だけ鳴らない」
になっていた（2026-08-27、実機で報告）。**片方のプラットフォームで踏んだ穴は、
もう片方も見に行くこと。**

音が鳴らない原因は OS 設定側にもありうる（通知そのものの不許可・バナー切り・通知音切り）。
`UNUserNotificationCenter.notificationSettings()` で読めるので、**読んで画面に出す。**

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

| ID | 内容 |
| :-- | :---- |
| OPEN-004 | 無制限モード（REQ-TIM-045）実装時の Live Activity 再開方法 |
| OPEN-016 | **iOS の通知音**。`/System/Library/Sounds` は iOS に存在せず（ランタイムで確認）、`UNNotificationSound(named:)` はアプリバンドルと `Library/Sounds` しか見ないため、[0017](decisions/0017-system-notification-sounds.md) の対応表（Glass / Submarine / Tink）を iOS で使えない。現在は無音以外すべて OS 既定音。選択肢は「iPhone では既定音のみ（Mac だけ4種）」か「音源をバンドルに同梱する」（0017 の『独自音源を同梱しない』と衝突） |
| OPEN-011 | `--border-strong` が WCAG 1.4.11 の 3.0 を満たすのは `--bg` 上のみ（ライト 3.10 / ダーク 3.30）。`--surface-raised` 上では 2.91 / 2.68 に落ちる。仕様書は `-strong` の保証面を規定していない。**工程4では顕在化しなかった**（設定画面の入力欄はシステム標準のコントロールを使い、`-strong` を自前で描いていない）。枠を自前で描く場面が来たら判断が要る |

---

## 6. 現在の作業状態

**最終更新: 2026-08-26**

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
  - UI 文字列は **String Catalog**（`Localizable.xcstrings`）経由。工程9で英語を入れる
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

**M3: 英語対応**

| 工程 | 内容 | 前提 |
| :-- | :---- | :-- |
| 9 | **英語ローカライズ**（2026-08-26 決定）。日本語と英語の2言語。他言語は対象外 | 工程8 |

英語は**マスト**である。工程8まで終えてから着手する。
**工程6以降に追加する UI 文字列は、最初から String Catalog 経由で書くこと**（2026-08-27 承認）。
後から全文字列を洗い出すより、書く時点で通しておくほうが安い。
既存の Mac UI のぶんは工程9でまとめて拾う。

未決事項の着手時期: OPEN-002 は工程6。着手前に止めて確認する（`CLAUDE.md`「未決事項の扱い」）。

### 未着手

- **通知のスケジュール層**（第5章）— 未着手。
  発火時刻の決定（`PreNotificationSchedule`）だけが `PomodoroCore` にある
- REQ-UIX-034（Mac のフローティングウィンドウ、MAY）— 見送り
- **REQ-LOG-014（前日の日次サマリ、SHOULD）— 実装しない**（2026-08-26 決定）。
  設定 UI からも外した。将来必要になれば、前日ぶんの集計にログの読み戻しが要る
- REQ-PER-010 / 011（iPhone が最後の `stateSnapshot` を永続化し、取得時刻を併記する）は
  `stateSnapshot` 型そのものが第10章の通信仕様に属するため、**工程5で実装する**
- REQ-PER-006（`RUNNING` 中の Mac のアイドルスリープ抑止）はアプリのライフサイクルに属するため、**工程4で実装する**
