# 0011 — LaunchServices は plist の多重起動禁止をテストホストにも強制する

**問い**: `LSMultipleInstancesProhibited` で多重起動を防げるか（POL-116 の実装手段の選定）。

**方法**: 実測（implementer・2026-09-02）。`Info.plist` にキーを入れて `xcodebuild test` を実行。
**対象**: macOS 26 / Xcode 26。

| 事実 | 確度 |
| :---- | :---- |
| テストスイートは MdoroMac.app（同じ bundle identifier）をホストとして走るため、**本物の Mdoro が起動中の機体では、キーを入れた瞬間に `xcodebuild test` がホスト起動時点で失敗する**（"The test runner exited with code 0"） | 実測 |
| plist 層の禁止は `TestHost.isRunning` では迂回できない —— 判定はプロセスが生まれる前に LaunchServices が行う | 帰結 |

**帰結**: Mdoro は plist 層を採用せず、`init` 内のコード判定（`NSRunningApplication` 走査）だけで
多重起動を退ける。**キーの再導入はテストで禁止されている**（`SingleInstanceTests` の plist 走査）。

## 確かめられなかったこと

- LaunchServices を経ない起動（バイナリ直接実行）にキーが効かないことは文書上の帰結で、個別には実測していない
