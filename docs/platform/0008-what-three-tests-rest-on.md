# 0008. テストが乗っている3つの主張

- **調査日**: 2026-08-29
- **対象**: macOS 26.5.1（25F80）/ Xcode 26.6（17F113）/ MacOSX26.5.sdk /
  mDNSResponder-2881.120.11
- **依頼の理由**: コードが独自に主張しているプラットフォームの事実26件のうち（POL-074）、
  **人間の決定（2026-08-29）により「正しさが依存しているものだけ調べる」**とした3組。
  **「主張が真か」だけでなく「乗っているものを支えるのに十分か」も見るよう依頼した**
  （[0006](0006-sf-symbols-catalog-and-availability.md) では**主張は真だったが、テストが必要としている保証ではなかった**）

## 答え

**3組すべてで「制約は本物だが、付いていた限定が誤り」の型が出た。**
**そして1組目は、実測で主張そのものが覆った。**

| 組 | 何が乗っているか | 判定 |
| :-- | :---- | :---- |
| **1. Bonjour の番号** | **`deduplicated` の正しさ** | **主張が誤り。`deduplicated` は最新を捨てうる** |
| **2. `TestHost`** | **POL-047 の解決策の全体** | **効果は正しいが、機序が2箇所とも誤り。加えて未文書の落とし穴** |
| **3. `StringCatalogTests`** | 4本のテスト | **4つとも成立。ただし2つに誤った限定** |

---

## 1. Bonjour の重複した登録の番号 — **主張は誤り**

### コードの主張

> プロセスが不意に終わると Bonjour の登録がすぐには消えず、macOS が番号を付け直す。
> **古いほうが番号が小さい**

### 誰が番号を付けるか — 文書化

**mDNSResponder（システムのデーモン）である。`NWListener` でも `NetService` でもない。**

- `MacOSX26.5.sdk/usr/include/dns_sd.h:286-293`（`kDNSServiceFlagsNoAutoRename`）:
  > "By default, name conflicts are automatically handled by **renaming the service.**"
- `Network.framework/Headers/advertise_descriptor.h:89-105`:
  > "Disable auto-rename for the Bonjour service registration. **Auto-rename is enabled by default.**"

**Mdoro は `noAutoRename` を設定していない**（`ServerInfo.swift:67-74`）ので、既定の auto-rename が効いている。

### 番号の形 — Apple 公開ソース

`mDNSResponder-2881.120.11` の `mDNSCore/DNSCommon.c`（`IncrementLabelSuffix`）:

```c
if      (val == 0) val = 2;
else if (val < 10) val++;
else val += 1 + mDNSRandom(99);
```

**10以上では `+1 + 乱数(0..98)`。「番号は1つずつ増える」は 10 以降で偽である。**

### 番号の若さと新旧の関係 — **文書化なし。実測すると成り立たない**

**Apple の一次情報のどこにも、番号と新旧の対応は書かれていない。**
`NWListener.Service` の Developer Documentation はアブストラクト1行のみで、競合も改名も記述がない。

**実測**（2026-08-29 21:57–21:58、macOS 26.5.1、`dns-sd`。
**捨て用のサービス型 `_mdoroprobe._tcp` を使い、`_mdoro._tcp` には触れていない**）:

| 手順 | 結果 |
| :--- | :--- |
| A を登録 | `MdoroProbe` |
| B を登録（A は生存中） | **`MdoroProbe (2)`** — 新しいほうが大きい番号 |
| **A を kill、B は生存** | **B は `(2)` のまま。番号を返上しない** |
| C を登録 | **`MdoroProbe`** — **最新が番号なしを取る** |
| ブラウズ | `MdoroProbe (2)`（古い・生存）と `MdoroProbe`（最新）が並ぶ |

**この状態で `deduplicated` は `MdoroProbe (2)` を残し、最新の `MdoroProbe` を捨てる。**

**さらに、前提の「消えない」も誤りだった。** 別の実測（SIGKILL）:

| 時刻 | 事象 |
| :--- | :--- |
| 21:58:32.494 | `Add ... KillProbe` |
| 21:58:35 | 登録プロセスを `kill -9` |
| **21:58:36.766** | **`Rmv ... KillProbe`** |

**プロセスが不意に死んでも、登録は約1.7秒で消える。**
ソース上も一致する（`mDNSShared/uds_daemon.c` の `regservice_termination_callback` が
UDS 接続断で `mDNS_DeregisterService` を呼び、goodbye を送る）。

**「不意に終わる → 消えない → 番号が振り直される」という因果は成立していない。**
実際に見た `Name` + `Name (2)` は、**2つの登録が同時に生きていた**ときのものである。

### 乗っているものを支えるのに十分か — **足りていない**

**`deduplicated` が誤る場面を4つ**（設計の提案ではなく、成り立たない場面の列挙）:

1. **上の実測そのもの。** 生存中の `Name (2)` があるとき、新しい `Name` が現れると、
   **最大番号を残す規則は最新を隠す**
2. **同名の別 Mac 2台。** どちらも生きているのに片方を黙って落とし、名前も番号なしに揃えて表示する
   （`differentMacsAreNotMerged` は**別名の場合しか見ていない**）
3. **正当に `(2)` で終わる Mac 名。** macOS は共有名の衝突でも `" (2)"` を付ける。
   **「Studio (2)」という Mac は「Studio」へ書き換えられ、本物の「Studio」と混ざる**
4. **識別子がない。** Mac は自分が何という名前で登録されたかを知らない
   （`serviceRegistrationUpdateHandler` を使っていない）。**TXT は `ws` と `v` だけで、
   インスタンスを一意に指す値が電波に乗っていない。** 名前の文字列以外に判定材料がない

### 確度

| 内容 | 確度 |
| :---- | :---- |
| auto-rename が既定 / 番号は mDNSResponder が付ける | **文書化** |
| `" (2)"` 形式・10以降は乱数増分 | **Apple 公開ソース** |
| 新しい登録が `(2)` を取る / `(2)` は返上しない / 最新が番号なしを取りうる / SIGKILL 後 約1.7秒で撤去 | **実測**（同一 Mac 上、`dns-sd`） |
| **番号の若さと新旧の関係** | **文書化なし。実測すると成り立たない** |
| LAN 越し（`NWBrowser`）でのキャッシュ残存時間 | **不明**（Wi-Fi 断・スリープ・電源断では goodbye が出ず TTL まで残りうるが、**測っていない**） |

---

## 2. `TestHost` の2つの主張 — **効果は正しく、機序は誤り**

### 2a. 「`@testable import` には `BUNDLE_LOADER` が要る」— **機序が誤り**

**`@testable` が要求するのは `ENABLE_TESTABILITY`（`-enable-testing`）であって `BUNDLE_LOADER` ではない。**
`BUNDLE_LOADER` が要るのは、**取り込む先が App モジュールだから**である。

- Apple Build Settings Reference の `BUNDLE_LOADER`:
  > "Undefined symbols from the bundle are checked against the specified executable"
- `man ld:526-530`: `-bundle_loader executable` — 同じ説明
- `man 5 xcodebuild.xctestrun` の `TestHostPath`:
  > "**For framework tests, this should be a path to the xctest command line tool.**
  > For application hosted tests, this should be a path the application host."

**テストバンドルは App でなく `xctest` CLI にホストさせることもできる。**
**ホストが App でなければならないのは、App のシンボルへリンクするときである。**

**このプロジェクトについては結論が正しい** —— 両テストターゲットが App モジュールを `@testable import` し、
`project.pbxproj` に `BUNDLE_LOADER = "$(TEST_HOST)"` が入っている。**理由の説明だけが誤り。**

### 2b. 「XCTest がこれを設定する」— **誤り。設定するのは起動側**

**`XCTestCore` は読む側である。** `-[XCTestConfigurationLoader init]` を逆アセンブルすると、
環境変数を**2つ**読む。そして `loadTestConfiguration` の分岐順は:

```
1. XCTestConfigurationEncodedValueEnvironmentKey   ← 先に試される
2. XCTestConfigurationFilePath
3. 一時ディレクトリの最新 .xctestconfiguration
```

**`XCTestConfigurationFilePath` は2番手である。**

Xcode.app 全体の走査:

| 文字列 | 出現する場所 |
| :--- | :--- |
| `XCTestConfigurationEncodedValueEnvironmentKey` | `XCTestCore`（読む側）、`XCUIAutomation` |
| `XCTestConfigurationFilePath` | `DVTFoundation` / `IDEFoundation` / `XCTHarness` / `IDEiOSSupportCore`（**起動側**）、`XCTestCore` |

**起動側（Xcode / `xcodebuild`）が書いている。だから現状は動く。**
**しかし文書化されていない実装詳細であり、優先順位では下である。**

### Swift Testing だけのバンドルでも設定されるか — **される（文書化はされていない）**

- 両ターゲットとも `productType = "com.apple.product-type.bundle.unit-test"`。
  **テストの書き方に関係なく `.xctest` バンドルで、ホストの起動経路は同一**
- `XCTestCore` に `SWIFT_TESTING_XCTEST_INTEROP_MODE` / `XCTSwiftTestingExitTestEntryPoint` /
  `com.apple.SwiftTesting` が含まれる。**Swift Testing は XCTestCore の上で駆動されている**
- `CoreBuildSystem.xcspec`（`ENABLE_TESTING_SEARCH_PATHS`）は **`Testing` を XCTest と並列に扱う**
- `Testing.framework` は `XCTest.framework` と並んで同梱されている

**このリポジトリの2ターゲットは `import XCTest` を1行も持たず、全て `import Testing` である。**

### 確かめられなかったこと

- **`XCTestConfigurationFilePath` は Apple のどの文書にも載っていない。**
  Xcode の環境変数リファレンスは Xcode Cloud 用で、この変数を含まない。**「文書化」区分には入らない**
- **実際に走らせて環境変数の有無を確認していない**（ビルド・テスト実行の禁止に従った）
- **encoded value 経路がどの起動モードで使われるのかは分からなかった**

### 乗っているものを支えるのに十分か — **実効性は保たれるが、支えは細い**

- 検出の根拠は**未文書の環境変数1本**で、**`XCTestCore` の優先順位では2番手。**
  **Xcode が encoded value 経路に切り替えたら、`TestHost.isRunning` は黙って `false` を返し、
  ガードは無言で開く**
- それを捕まえられるのは app-hosted の `TestHostDetectionTests` だけで、
  **CI（`swift test` を `Packages/MdoroCore` で走らせるだけ）では実行されない**
- `MdoroCoreTests/TestHostTests.swift` は**ガードがテキストとして存在すること**しか見ていない。
  **検出が発火することは、CI では一度も確かめられていない**

---

## 3. `StringCatalogTests` の4つの前提 — **4つとも成立。2つに誤った限定**

### 3a. 「`xcodebuild` は `.stringsdata` を書き、`.xcstrings` へ書き戻さない」— **成立**

ビルドのタスクグラフ（`PomodoroMac/build/XCBuildData/*.xcbuilddata/manifest.json`、全217コマンド）:

- **ソースの `Localizable.xcstrings` を出力に持つコマンドは0件**
- `xcstringstool` の呼び出しは **`generate-symbols` のみ**
- `XCStrings.xcspec` の `CommandLine` は **`xcstringstool compile` だけ**。
  **Xcode.app 全体を走査しても `sync` を呼ぶものはない**

### 3b. 「見つからないときはキーをそのまま返す」— **文書化**

`Bundle.localizedString(forKey:value:table:)`:

> "If `key` is not found and `value` is `nil` or an empty string, **returns `key`.**"

**注意**: 同じ文書に、`NSShowNonLocalizedStrings` が true のときは
**「キーを大文字化して返す」**とある（既定では無効）。**素通しではない経路が存在する。**

### 3c. 「キーは補間の型に依存する」— **文書化 ＋ 実測**

[Localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog):

> "Determines which specifier to use for the interpolated string (`%lld` representing a 64-bit integer in this case)."

**実測**（`Theme.stringsdata`）: `\(seconds / 60)` → `%lld`、`String` の補間 → `%@`。

### 3d. 「`.xcstrings` は Xcode のエディタだけが書く」— **限定が誤り**

**書く経路は2つある。**

1. **Xcode（IDE）のビルド。** Apple が明記している:
   > "**Each time you build your project, Xcode updates your string catalogs** with changes you make
   > to localizable strings in your code."

   **ただしこれはビルドのタスクグラフの外**で、書き戻しの API は IDE プラグイン
   `IDEXCStringsSupportCore.framework` にある
2. **公開 CLI `xcstringstool sync`**: "Updates an .xcstrings file based on strings present in .stringsdata files."

### 乗っているものを支えるのに十分か — **十分だが、書かれている理由が狭い**

- 4本とも **`swift test` で走る。CI もこれだけ**なので、**CI では Xcode ビルドが起きず、
  カタログは自動更新されない。** テストが守ろうとしている状況は成立する
- **ただし失敗が起きうる範囲は、条文が書いているより狭い。**
  Xcode で App をビルドした人の手元では**カタログは自動更新される。**
  **このテストが実際に捕まえるのは「Xcode を開かずに書いて、そのまま出した変更」**である。
  **「`xcodebuild` が書き戻さないから」ではなく「そのカタログを commit していないから」が正しい説明**
- `noViewBuildsItsKeyAfterTheCompilerHasGone`（`Text(.init(` の禁止）は**直接の裏付けを見つけられなかった。**
  `xcstringstool extract --help` の "using **lightweight parsing**" と整合はする。**この1点は「不明」寄り**

## やらなかったこと

- **ビルド・テスト実行・シミュレータ起動をしていない。** DerivedData と `PomodoroMac/build` は
  既存の生成物を読んだだけ
- 実測は `dns-sd` のみ。**捨て用のサービス型を数秒だけ広告し、後始末（プロセス kill と残存なしの確認）まで済ませた**

## 影響を受ける記述

| 箇所 | 理由 |
| :---- | :---- |
| **`DiscoveredServer.swift` の `deduplicated` と、その根拠のコメント** | **主張が誤り。実装が最新を捨てうる。** 4つの場面で誤る |
| `TestHost.swift:3-7` | `@testable` が要求するのは `ENABLE_TESTABILITY`。`BUNDLE_LOADER` が要るのは App のシンボルへリンクするから |
| `TestHost.swift:20-24` | **設定するのは XCTest ではなく起動側。** そして**優先順位では2番手** |
| `StringCatalogTests.swift:106-107` | 「エディタだけが書く」は誤り。**Xcode のビルドと `xcstringstool sync` が書く** |
| `StringCatalogTests.swift:7-9` | 主張は正しいが、**このテストが捕まえるのは「カタログを更新せずに出した変更」** |
| CI（`.github/workflows/tests.yml`） | **app-hosted のテストが CI で走らない。** `TestHost` の検出が壊れても誰も気づかない |
