# DEVELOPMENT — プロジェクト構成・ビルド・環境

運用上の規律は `CLAUDE.md`、現在有効な方針は `docs/CONTEXT.md` を参照する。
このファイルは**手順と環境の事実**だけを置く。

---

## プロジェクト構成

```
Pomodoro_Timer/                        # プロジェクトルート
├── CLAUDE.md                          # 運用憲法
├── docs/
│   ├── SPEC.md                        # 要件の正本（版数は SPEC 自身が持つ）
│   ├── CONTEXT.md                     # 現在有効な方針の要約
│   ├── DEVELOPMENT.md                 # このファイル
│   ├── PUNCHLIST.md                   # 作業キューの正本
│   ├── PLATFORM.md                    # Apple がどう振る舞うか（索引）
│   ├── platform/                      # 調査そのもの（1件1ファイル）
│   └── decisions/                     # Decision Record
├── AGENTS.md                          # 外部の貢献者とそのエージェント向け（英語）
├── .claude/agents/                    # implementer / reviewer / spec-auditor / repo-auditor
├── buildServer.json                   # xcode-build-server の設定（Cursor の補完用）
├── Packages/MdoroCore/             # 共有コード。ここが主戦場
│   ├── Package.swift
│   ├── Sources/MdoroCore/
│   └── Tests/MdoroCoreTests/
└── PomodoroMac/                       # Xcode プロジェクト一式（フォルダ名は未改名）
    ├── PomodoroMac.xcodeproj
    ├── PomodoroMac/       PomodoroMacTests/
    ├── PomodoroiOS/       PomodoroiOSTests/
    └── PomodoroWidget/                # Live Activity（提供するのは Live Activity だけ）
```

**フォルダ名とターゲット名が食い違っている。** ターゲットは `MdoroMac` / `MdoroiOS` / `MdoroWidget`、
フォルダは `PomodoroMac/` などのまま（工程9の残り。`docs/CONTEXT.md` §6）。
**パスは上の表示どおりで正しい。**

- ターゲット3つ（`MdoroMac` / `MdoroiOS` / `MdoroWidget`）はいずれも `PomodoroMac/` の下にある。
  **`.xcodeproj` はルートではなく `PomodoroMac/` の中。**
- 各ターゲットのフォルダは buildable folder。**`.swift` をディスクに置けば自動でビルド対象に入る。**
- `Info.plist` は3ターゲットとも実ファイルとして存在する（`PomodoroMac/<フォルダ名>/Info.plist`）。
  XML として直接編集してよい。
- **`.xcodeproj` を直接編集しない。** buildable folder があるので、ファイルはディスクに置くだけでよい。

---

## ビルド・テスト

プロジェクトルート: このリポジトリのルート
Xcode プロジェクト: `./PomodoroMac/PomodoroMac.xcodeproj`

### 共有パッケージ

プロジェクトルートから実行する。

```bash
(cd Packages/MdoroCore && swift test)
```

**`xcbeautify` は任意である。** ログを読みやすくするだけで、ビルドの結果は変わらない。
入れるなら `brew install xcbeautify`。入れないなら `| xcbeautify` ごと落とす ——
**初回 clone の機体には入っておらず、残したままだと `command not found` になる。
パイプラインの終了コードは末尾のコマンドのものなので、コマンド全体が失敗として返る**
（`set -o pipefail` は関係ない。あれが効くのは `xcodebuild` が失敗した側を拾うためである）。

### macOS アプリ

```bash
set -o pipefail && xcodebuild \
  -project ./PomodoroMac/PomodoroMac.xcodeproj \
  -scheme MdoroMac \
  -destination 'platform=macOS' \
  build | xcbeautify
```

### iOS アプリ（シミュレータ）

シミュレータ: iPhone 17 / UDID `78F6E5B6-EFAE-4892-B121-C3454DB871EC`

```bash
set -o pipefail && xcodebuild \
  -project ./PomodoroMac/PomodoroMac.xcodeproj \
  -scheme MdoroiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build | xcbeautify
```

### シミュレータ一覧

```bash
xcrun simctl list devices available
```

---

## 署名は xcconfig から入る

`DEVELOPMENT_TEAM` は `project.pbxproj` に**書かれていない**。プロジェクトの Debug / Release が
`Config/Signing.xcconfig` を base configuration として持ち、そこから
`Config/Signing.local.xcconfig`（Git 管理外）を `#include?` で読む。

**Xcode の Signing & Capabilities で Team を選ばないこと。** 選ぶとターゲット側に
`DEVELOPMENT_TEAM` が書き戻され、xcconfig より優先される。チームを変えるときは
`Config/Signing.local.xcconfig` を書き換える。

**この形にした理由は2つある**（2026-08-29）。

1. 作者のチーム ID がコミットに混ざり、貢献者が毎回書き換えることになっていた
2. **`xcodebuild` がビルドのたびに `project.pbxproj` を書き換えていた**（`DEVELOPMENT_TEAM` を `""` に）。
   ターゲット側に行が無くなったことで起きなくなった。ビルド前後で差分が出ないことを確認済み

## ローカルネットワーク許可の検証

**macOS には、許可状態を未決定へ戻す手段がない**（REQ-PLT-009）。一度許可または拒否すると、
同じユーザーアカウントでは初回ダイアログを再現できない。

**検証は別ユーザーアカウントか仮想環境で行う。** ad-hoc 署名では許可の同一性が保たれず、
挙動が不安定になるため、Apple 発行の署名 ID で署名したビルドを使う。

---

## 環境メモ

- Xcode 26.6 / Swift 6.3。deployment target は macOS 26.0 / iOS 26.0。
- 署名は無償の Personal Team。**iPhone 実機のアプリは7日で失効する**ので、切れたら再ビルドして入れ直す。
- **起動もビルドも通らなくなったら、開発者信頼が外れていることがある。** 7日失効と違い、**再ビルドでは直らない。** iPhone の 設定 > 一般 > VPN とデバイス管理 でアカウントを信頼し直してからビルドする。**原因を名指す案内は、数回の試行と数分の後に出る**ので、先に見えるのは起動失敗のほうである。**OS の更新の直後に起きた例があるが、更新が原因だとは分かっていない**（[platform/0013](platform/0013-the-trust-was-gone-after-an-os-update.md)）。
- **`Tools/*.py` は文書の道具で、Mdoro のビルドには要らない。** 対応する Python の範囲は `.github/workflows/tests.yml` の `tools` ジョブが持つ（**数字をここに書き写さない**）。
- Push 通知と iCloud は Personal Team では使えないが、本仕様は使わない（ローカル通知に capability は不要）。
- **Xcode を開くのは、ターゲット追加・capability 追加・実機デバッグ・Instruments のときだけ。**
  それ以外では開かない（[0008](decisions/0008-minimal-xcode-gui.md)）。
- **アプリ名は `Mdoro`**（[0021](decisions/0021-published-as-oss-named-mdoro.md)）。ターゲット名・bundle ID は
  改名済み（工程9、[0024](decisions/0024-rename-everything-to-mdoro.md)）。リポジトリ名は `mdoro`。
  リポジトリのフォルダ名だけは `Pomodoro_Timer` のままで、この文書のパスもそれに従う。
- **アイコンの正本は SVG。** `swift Tools/make_icon.swift` が PNG を書き出す。
  描画は AppKit の SVG 対応に任せてあり、外部ツールは要らない。
  **PNG を手で置き換えず、SVG を直して回す**（色リテラルをビューに書かないのと同じ理由）。
  - `Tools/mdoro-icon.svg` → 両プラットフォームの `AppIcon.appiconset`
    （iOS のライト・ダーク・ティントと macOS の10寸法）
  - `docs/images/icons/mdoro-menubar-{idle,running-60,paused}.svg` →
    メニューバーの imageset 3つ。**メニューバーの正本だけは `docs/images/icons/` にある。**
    3枚しか使わない（`MenuBarMark`）。画像を足すときは `make_icon.swift` の
    `menuBarStates` と `MenuBarMark` の両方を変える
    （名前が食い違うと、何も描かれないまま静かに失敗する。`MenuBarMarkTests` が検査する）
- セットアップ手順書のリンクは `docs/PRIVATE-LINKS.md`（Git に入れていない）。

## Apple プラットフォームの事実

**`docs/PLATFORM.md`（索引）と `docs/platform/`（調査そのもの）を見る。**
`CONTEXT.md` §3 にあった記述は、[0038](decisions/0038-platform-facts-are-not-the-specs-job.md) でそちらへ移した。

**「再調査しない」は、出典と確度が付いた項目についてだけ有効である。**
§3 は「一次情報で確認済み。再調査しない」と宣言していたが、**9項目のうち出典が残っていたのは1件だけ**で、
その後の調査で**いくつかは実際に誤っていた**（ロック画面の背景、開始経路、メニューバーの色、
3.5 の設定表）。**確度が `未検証` の項目を根拠に条文やコードを書かないこと。**

**ローカルネットワーク許可はシミュレータで確かめられない。** シミュレータはこの仕組みを実装しておらず、
許可ダイアログが出ることも拒否されることもない。**Mac と iPhone の接続は実機でしか検証できない**
（`docs/PLATFORM.md`）。
