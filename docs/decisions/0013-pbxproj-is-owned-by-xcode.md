# 0013. `.xcodeproj` は Xcode の所有物とし、Claude Code は直接編集しない

- **状態**: accepted
- **日付**: 2026-08-26

## 文脈

このプロジェクトの3ターゲットはいずれも **buildable folder** で構成されている（[0008](0008-minimal-xcode-gui.md)）。
`.swift` をディスクに置けば自動でビルド対象に入るため、
**ファイルの追加・削除を目的として `project.pbxproj` を触る必要がない。**

共有コードは `Packages/MdoroCore` のローカル Swift Package にあり、
ターゲット・依存・ビルド対象の追加は `Package.swift` のテキスト編集で完結する。

一方 `project.pbxproj` は、Xcode が生成・管理する巨大な機械可読ファイルである。
手で書き換えると、Xcode 側の表現と食い違ったときに壊れ方が分かりにくい。

## 判断

- **`project.pbxproj`（および `.xcodeproj` 配下）は Xcode の所有物とする。Claude Code は直接編集しない。**
- ビルド対象・依存関係を変えたいときの代替手段は **`Package.swift`** である。そこで表現できるものは、
  すべてそこで表現する。
- `Package.swift` でも buildable folder でも表現できない変更
  （capability の追加、App Sandbox のビルド設定、ターゲット追加、ターゲットへのパッケージのリンク、
  署名設定）が必要になった場合は、**実装を止め、人間が Xcode で行う操作として報告する。**
  手順は具体的な操作パス（TARGETS → タブ → 項目）まで書く。

## 理由・設計意図

**buildable folder とローカルパッケージがあるから、この制約を課しても失うものがほとんどない。**
制約が実務を止めないことが分かっているから、安全側に倒せる。

`project.pbxproj` を手で編集できることにすると、
「ここだけ直せば済む」という判断が積み重なり、Xcode の GUI で見える状態とファイルの実体が乖離していく。
乖離は、次に GUI を開いたときに初めて表面化する。

`.xcodeproj` を触る必要が出た時点で止めるのは、その操作が
**[0008](0008-minimal-xcode-gui.md) が Xcode の GUI を開いてよいと認めた場面そのもの**だからである。
迂回策を探すより、人間に1回の操作を頼むほうが早く、状態も正しく残る。

## 影響

- `CLAUDE.md`「コードの置き場所」に条文がある
- **代替**: `Packages/MdoroCore/Package.swift`。共有できるコードは必ずここに置く（REQ-PRT-001）
- **停止して報告する操作の実例**（2026-08-26 に実際に発生）
  - `ENABLE_USER_SELECTED_FILES` を `readonly` → `readwrite`（REQ-PLT-001、ログ追記に必須）
  - `PomodoroWidgetExtension` への `MdoroCore` のリンク
- Info.plist は3ターゲットとも**実ファイル**として存在するため、この判断の対象外。XML として直接編集してよい
- 関連: [0008](0008-minimal-xcode-gui.md)（Xcode の GUI を開く場面の限定）

## 出典と確度

- **事実**: 「`.xcodeproj` を直接編集しない」は初期から `CLAUDE.md` にあった規約であり、
  buildable folder とローカルパッケージの構成は [0008](0008-minimal-xcode-gui.md) に記録がある。
  停止して報告した操作は 2026-08-26 に実際に発生したもの。
- **推測**: 「理由・設計意図」節の乖離の説明は、規約の意図を Claude Code が言語化したものであり、
  制定時にこの言葉で説明されたという記録はない。
