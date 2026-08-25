# Pomodoro Timer (Mac ⇄ iPhone)

Mac をタイマー状態の正本、iPhone を表示・操作端末とする、LAN 内で完結するポモドーロタイマー。
Obsidian の `Task.md` を読み取り専用で参照し、実績を `PomodoroLog.md` へ記録する。

- **Mac**: SwiftUI / macOS 26+。メニューバー常駐＋メインウィンドウ。WebSocket サーバー。
- **iPhone**: SwiftUI / iOS 26+。表示と操作。Live Activity。
- **通信**: Network.framework（Bonjour `_pomodoro._tcp` + WebSocket / JSON）。

## 仕様書

**`Pomodoro仕様書_v2.md`（v2.5、227要件）が唯一の正。** 実装判断に迷ったら推測せず参照する。

要件IDは `REQ-{COM,SEC,PLT,TIM,NTF,TSK,LOG,UIX,COL,PRS,CFG,PRT,PER,ERR,NFR}-nnn`。
**コードコメントと commit メッセージには根拠の要件IDを書く**（例: `// REQ-TIM-035: FINISHED からの脱出先は常に IDLE`）。

仕様書を変更するときは、**必ず影響する他章を確認してから**変更する。過去に2回、1章だけ編集して矛盾を作っている（v2.1 のプリセット追加、v2.4 の状態遷移マトリクス新設）。特に第4章・第5章・第7章・第9章・第10章・第11章は互いに強く結合している。

## 動かしてはいけない3原則

1. **`Task.md` へは一切書き込まない。** 実績は `PomodoroLog.md` へ挿入のみ（既存行の書き換え・削除は禁止）。ブックマークは `securityScopeAllowOnlyReadAccess` で読み取り専用として生成し、OS レベルでも担保する。
2. **状態の正本は Mac。** iPhone は表示上のカウントダウン補間はしてよいが、**セッションの終了を確定してはならない**。周回数の加算・ログ記録の判断は Mac だけが行う。
3. **時間は絶対時刻基準。** 残り秒数を同期しない。`sessionEndAt` を配って各端末が算出する。残り時間の算出には単調時計、`sessionEndAt` の生成とログ表記には壁時計を使う。

## 実装で壊しやすい設計判断

レビューで実際に破綻していた箇所。理由まで含めて守る。

- **`committedAt` を見て確定処理を冪等に行う。** これがないと、休憩セッションが `FINISHED` に留まる間の中断・次セッション開始・リセットで**ログが二重に書かれる**（4経路）。復帰時の記録漏れも起きる（3経路）。
- **`nextSessionType` は「現在のセッションが完了したと仮定したときの次」。** 「直前のセッション」基準にすると、開始時に事前スケジュールする通知へ誤った種別が載る。倍数判定は `loopCount + 1` に対して行う（`loopCount = 0` はあらゆる `longBreakInterval` の倍数なので、0 のまま判定するとリセット直後に長い休憩が提案される）。
- **状態遷移マトリクス（4.6）は受理可否のみ。** `canAccept(action, state) -> Bool` と `apply(action) -> Effects` を分離する。副作用をマトリクスに書くと、設定の適用範囲（9.5 の A/B/C 群）や周回数の規定と衝突する。
- **`FINISHED` からの脱出先は常に `IDLE`。** 確定と同時に遷移する。
- **ログのタスク名はセッション開始時点のスナップショット**（`selectedTaskSnapshot`）。`FINISHED` 中に選び直しても反映しない。作業していないタスクが記録されてしまう。
- **設定変更で実行中の `sessionEndAt` を変えない。** 長さの変更は「延長」操作に一本化。事前スケジュール済みのローカル通知との整合が崩れるため。

## Apple プラットフォームの制約（調査済み・再検討不要）

一次情報で確認済み。回避策を探し直さない。

- **Live Activity はアプリがフォアグラウンドの間しか開始できず、更新もアプリが running の間だけ。** iOS はバックグラウンド移行後まもなく suspend する。完全ローカル構成でロック中の反映は不可能なので、`staleDate` / `isStale` で陳腐化を示す。ここを MUST 要件にしない。
- **iPhone の通知を WebSocket に依存させない。** `sessionEndAt` に対する絶対時刻のローカル通知として事前スケジュールする。バックグラウンドでは WebSocket が切れるため、これ以外に手段がない。
- **ATS は IP アドレス直接接続を既定で拒否する**（iOS 17 / macOS 14 以降）。`NSAllowsLocalNetworking = YES` が必須。
- 残りの Info.plist キーと entitlements は**仕様書 3.5 節**。1つ欠けると「繋がらない」が起き、原因の切り分けに時間を取られる。**コードより先に設定を通す。**
- ローカルネットワーク許可の状態を問い合わせる API はない。`NWBrowser` の `-65570` と `NWConnection` の `.localNetworkDenied` で検出する。初回許可取得は必ずフォアグラウンドで行う（バックグラウンドだとダイアログなしで黙って拒否される）。
- サンドボックス下の原子的書き込みは**同一ディレクトリ内**で `FileManager.replaceItemAt` を使う。`/tmp` を跨ぐ rename は失敗する。
- ファイル監視は記述子ではなく**親ディレクトリ**を張る。Obsidian は一時ファイル経由で保存するため、記述子に張った監視は inode 差し替えで無効化される。

## 色

- **色リテラルをビューに書かない。** 役割名（`sessionFocus`, `warning`, `danger`, `textPrimary`）で参照する。
- 各色相は `subtle` / `line` / `graphic` / `solid` / `text` の5役。**役を取り違えるとコントラスト保証が消える。** 進行リングなど意味を持つ図形は `-graphic`、文字が乗る塗りは `-solid`、背景上のテキストは `-text`。
- セッション3色（藍 / 青磁 / 黄土）は**絶対輝度に段差がある**。同一明度に揃えると色覚多様性下で識別できなくなる。
- 定義は仕様書 8.5 節。視覚的なリファレンス: https://claude.ai/code/artifact/ff49365a-63a3-4942-b4cc-4c1a10ac7383

## スコープ外

やらない。提案もしない。

- クラウド同期、アカウント、APNs（完全ローカル駆動の原則）
- `Task.md` の編集機能（タスクの作成・完了は Obsidian 側の操作）
- iPad / Apple Watch、複数クライアント同時接続、LAN 外からの接続

## プロジェクト構成

```
Pomodoro_Timer/                        # プロジェクトルート
├── CLAUDE.md / Pomodoro仕様書_v2.md
├── buildServer.json                   # xcode-build-server の設定（Cursor の補完用）
├── Packages/PomodoroCore/             # 共有コード。ここが主戦場
│   ├── Package.swift
│   ├── Sources/PomodoroCore/
│   └── Tests/PomodoroCoreTests/
└── PomodoroMac/                       # Xcode プロジェクト一式
    ├── PomodoroMac.xcodeproj
    ├── PomodoroMac/       PomodoroMacTests/    PomodoroMacUITests/
    ├── PomodoroiOS/       PomodoroiOSTests/    PomodoroiOSUITests/
    └── PomodoroWidget/                # Live Activity
```

- ターゲット3つ（`PomodoroMac` / `PomodoroiOS` / `PomodoroWidget`）はいずれも `PomodoroMac/` の下にある。**`.xcodeproj` はルートではなく `PomodoroMac/` の中**。
- 各ターゲットのフォルダは buildable folder。`.swift` をディスクに置けば自動でビルド対象に入る。
- `Info.plist` は3ターゲットとも実ファイルとして存在する（`PomodoroMac/<ターゲット名>/Info.plist`）。XML として直接編集してよい。
- **共有できるコードは必ず `PomodoroCore` に置く。** 状態機械・通信プロトコル・データモデルを Mac 版と iPhone 版で二重に実装しない（REQ-PRT-001）。
- **`.xcodeproj` を直接編集しない。** buildable folder があるので、ファイルはディスクに置くだけでよい。

## 環境メモ

- Xcode 26.6 / Swift 6.3。deployment target は macOS 26.0 / iOS 26.0。
- 署名は無償の Personal Team。**iPhone 実機のアプリは7日で失効する**ので、切れたら再ビルドして入れ直す。
- Push 通知と iCloud は Personal Team では使えないが、本仕様は使わない（ローカル通知に capability は不要）。
- ターゲット追加・capability 追加・実機デバッグ・Instruments・アイコン作成のときだけ Xcode を開く。それ以外は開かない。
- セットアップ手順: https://claude.ai/code/artifact/79598e4c-33c6-49c6-aaeb-aa64e2cc6f3b

## Build and test commands

Project root: `/Users/sohta/Documents/Development/Pomodoro_Timer`
Xcode project: `./PomodoroMac/PomodoroMac.xcodeproj`

### Shared core package

Run from the project root:

```bash
(cd Packages/PomodoroCore && swift test)
```

### macOS app

```bash
set -o pipefail && xcodebuild \
  -project ./PomodoroMac/PomodoroMac.xcodeproj \
  -scheme PomodoroMac \
  -destination 'platform=macOS' \
  build | xcbeautify
```

### iOS app simulator

Simulator: iPhone 17 / UDID: `78F6E5B6-EFAE-4892-B121-C3454DB871EC`

```bash
set -o pipefail && xcodebuild \
  -project ./PomodoroMac/PomodoroMac.xcodeproj \
  -scheme PomodoroiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build | xcbeautify
```

### List available simulators

```bash
xcrun simctl list devices available
```

### TODO

- [ ] 色のコントラストと ΔE の自動検証（REQ-COL-020）を `PomodoroCore` のテストとして追加する
