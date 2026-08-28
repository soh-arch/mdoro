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

## ローカルネットワーク許可の検証

**macOS には、許可状態を未決定へ戻す手段がない**（REQ-PLT-009）。一度許可または拒否すると、
同じユーザーアカウントでは初回ダイアログを再現できない。

**検証は別ユーザーアカウントか仮想環境で行う。** ad-hoc 署名では許可の同一性が保たれず、
挙動が不安定になるため、Apple 発行の署名 ID で署名したビルドを使う。

---

## 環境メモ

- Xcode 26.6 / Swift 6.3。deployment target は macOS 26.0 / iOS 26.0。
- 署名は無償の Personal Team。**iPhone 実機のアプリは7日で失効する**ので、切れたら再ビルドして入れ直す。
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

Apple プラットフォームの制約（ATS、ローカルネットワーク許可、Live Activity、ファイル監視など）は
`docs/CONTEXT.md` §3 にまとめてある。**再調査しない。**
