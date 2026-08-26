# CONTEXT — 現在有効な方針と状態

このファイルは**今の状態だけ**を書く。経緯は書かない。経緯が必要なら `docs/decisions/` を参照する。

- 要件の正本: `Pomodoro仕様書_v2.md`（v2.6、231要件）
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

## 5. 未決事項

`CLAUDE.md`「未決事項の扱い」により、**これらに触れる実装は止めて報告する。** 推測で埋めない。

| ID | 内容 |
| :-- | :---- |
| OPEN-001 | 通知音の具体的な音源（システムサウンド流用か独自音源か） |
| OPEN-002 | 集中表示ビューのタイポグラフィ（数字書体・等幅の可否・ウェイト）。配色は解決済み |
| OPEN-003 | 診断ログの保持期間とローテーション方針 |
| OPEN-004 | 無制限モード（REQ-TIM-045）実装時の Live Activity 再開方法 |
| OPEN-007 | 無償 Personal Team で Time Sensitive Notifications capability を有効化できるか |
| OPEN-008 | `MenuBarExtra` の label で残り時間を毎秒更新した場合の安定性。不安定なら `NSStatusItem` へ |
| OPEN-009 | REQ-NTF-020〜023 の数値の刻み（残り1〜15分、経過50〜95%を5刻み）は旧PMが決めたもの。**人間の確認が取れていない** |
| OPEN-010 | 仕様書ファイル（124KB）の置き場所。ルートのままか `docs/spec/` へ移すか |

---

## 6. 現在の作業状態

**最終更新: 2026-08-26**

### 完了

- `PomodoroCore` の状態機械（仕様書 第4章・9.5・10.3 相当）を実装済み。コミット `aa64471`
  - `TimerEngine` / `TimerContext` / `PresetContext` / `Preset` / `Effect` / `TimerAction` /
    `SessionType` / `StateTransitionMatrix`
  - ファイル I/O・ネットワーク・UI は含まない。ログ確定は `Effect.commitLog` として呼び出し側へ渡す
- **`swift test` 34テスト全通過**（7スイート、2026-08-26 実行）
- 開発体制の移行（[0011](decisions/0011-claude-code-as-orchestrator.md)）

### 未着手

- **実装が仕様 v2.6 に追いついていない。** コードは v2.5 相当（[0010](decisions/0010-extension-window.md) が未反映）

  | 仕様 | 現在のコード |
  | :---- | :---- |
  | REQ-TIM-046（新設）延長受付ウィンドウ | 存在しない。`extend` は `RUNNING`/`PAUSED`/`FINISHED` で常に受理される（`StateTransitionMatrix.swift:21`） |
  | REQ-TIM-043 猶予 **1分** | `extensionGraceSeconds = 5 * 60` のまま（`TimerEngine.swift:8`） |
  | `error.code: extendWindowClosed` | 存在しない |
  | `Preset.preNotifications`（最大2トリガ） | `preNotifySeconds: Int`（0〜300 で検証）のまま（`Preset.swift:24,82`） |
  | REQ-NTF-020〜023 予告通知 | 未実装（通知機能そのものが未着手） |

  なお **REQ-TIM-040 の起点固定（`sessionEndAt` 基準の加算）は既に実装済み**である（`TimerEngine.swift:155,163`）。

- 通信層（Bonjour / WebSocket）、ファイル監視、ログ書き込み、Mac UI、iOS UI、Live Activity — すべて未着手
- 色のコントラストと ΔE の自動検証（REQ-COL-020）を `PomodoroCore` のテストとして追加する
