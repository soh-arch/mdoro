# DEVELOPMENT — プロジェクト構成・ビルド・環境

運用上の規律は `CLAUDE.md`、現在有効な方針は `docs/CONTEXT.md` を参照する。
このファイルは**手順と環境の事実**だけを置く。

---

## プロジェクト構成

```
Pomodoro_Timer/                        # プロジェクトルート
├── CLAUDE.md                          # 運用憲法
├── docs/
│   ├── SPEC.md                        # 要件の正本（v2.6.1、232要件）
│   ├── CONTEXT.md                     # 現在有効な方針の要約
│   ├── DEVELOPMENT.md                 # このファイル
│   └── decisions/                     # Decision Record
├── .claude/agents/                    # implementer / reviewer
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

- ターゲット3つ（`PomodoroMac` / `PomodoroiOS` / `PomodoroWidget`）はいずれも `PomodoroMac/` の下にある。
  **`.xcodeproj` はルートではなく `PomodoroMac/` の中。**
- 各ターゲットのフォルダは buildable folder。**`.swift` をディスクに置けば自動でビルド対象に入る。**
- `Info.plist` は3ターゲットとも実ファイルとして存在する（`PomodoroMac/<ターゲット名>/Info.plist`）。
  XML として直接編集してよい。
- **`.xcodeproj` を直接編集しない。** buildable folder があるので、ファイルはディスクに置くだけでよい。

---

## ビルド・テスト

プロジェクトルート: `/Users/sohta/Documents/Development/Pomodoro_Timer`
Xcode プロジェクト: `./PomodoroMac/PomodoroMac.xcodeproj`

### 共有パッケージ

プロジェクトルートから実行する。

```bash
(cd Packages/PomodoroCore && swift test)
```

### macOS アプリ

```bash
set -o pipefail && xcodebuild \
  -project ./PomodoroMac/PomodoroMac.xcodeproj \
  -scheme PomodoroMac \
  -destination 'platform=macOS' \
  build | xcbeautify
```

### iOS アプリ（シミュレータ）

シミュレータ: iPhone 17 / UDID `78F6E5B6-EFAE-4892-B121-C3454DB871EC`

```bash
set -o pipefail && xcodebuild \
  -project ./PomodoroMac/PomodoroMac.xcodeproj \
  -scheme PomodoroiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build | xcbeautify
```

### シミュレータ一覧

```bash
xcrun simctl list devices available
```

---

## 環境メモ

- Xcode 26.6 / Swift 6.3。deployment target は macOS 26.0 / iOS 26.0。
- 署名は無償の Personal Team。**iPhone 実機のアプリは7日で失効する**ので、切れたら再ビルドして入れ直す。
- Push 通知と iCloud は Personal Team では使えないが、本仕様は使わない（ローカル通知に capability は不要）。
- **Xcode を開くのは、ターゲット追加・capability 追加・実機デバッグ・Instruments・アイコン作成のときだけ。**
  それ以外では開かない（[0008](decisions/0008-minimal-xcode-gui.md)）。
- セットアップ手順書: https://claude.ai/code/artifact/79598e4c-33c6-49c6-aaeb-aa64e2cc6f3b

Apple プラットフォームの制約（ATS、ローカルネットワーク許可、Live Activity、ファイル監視など）は
`docs/CONTEXT.md` §3 にまとめてある。**再調査しない。**
