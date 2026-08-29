# 0006. SF Symbols のカタログは共通か、可用性は何で決まるか

- **調査日**: 2026-08-29
- **対象**: macOS 26.5.1（25F80）/ iOS 26.5（23F77・シミュレータランタイム）/ Xcode 26.6 / SF Symbols 8 beta
- **依頼の理由**: `SymbolNameTests.swift:22` のコメント「**SF Symbols のカタログは両プラットフォームで共通**」に
  出典が無く、**テストの検査方法そのものがその主張の上に乗っていた**（軸 K・POL-077）。
  誤りなら `peerSymbolsOfBothPlatformsExist` は「**確かめたつもり**」で通り続ける

## 問い

依頼した内容をそのまま残す。**それぞれ別に確度を付けること**と指示した。

1. **カタログは macOS と iOS で同一か**
2. **シンボルごとにプラットフォーム別の可用性があるか**
3. **`NSImage(systemSymbolName:)` が macOS で `nil` でないことは、`UIImage(systemName:)` が
   iOS で `nil` でないことを保証するか。** ここが検査の成否そのもの
4. **テストが名指ししている13個**の可用性
5. **可用性を実行せずに確かめる手段はあるか**

**前提を疑ってよい**、**「そもそもこの検査は何を確かめたかったのか」という指摘も歓迎する**と明示して依頼した。

## 答え

**「カタログは両プラットフォームで共通」は、macOS 26.5 / iOS 26.5 について実測で真である。**
メタデータ10ファイルが SHA-256 で完全一致した。

**ただしこの主張は、テストが本当に必要としている保証ではない。**

**効いている軸はプラットフォームではなく OS バージョンである。**
テストは macOS 26.5 で走るが、配備対象は **26.0**。**この差に落ちるシンボルが現に 29 個ある。**
**「カタログは共通」は真だが、真であっても検査の穴は塞がらない。**

**軸 K のこれまでの4件と同型で、制約は本物・限定の軸が誤りである。**

## 根拠

### 1. カタログは同一か — **同一である（実測）**

macOS 26.5.1 と、インストール済み iOS 26.5 シミュレータランタイムの `CoreGlyphs.bundle` を直接突き合わせた。

| 比較対象 | 結果 |
| :--- | :--- |
| `name_availability.plist` | **SHA-256 一致**（両方 **9,184名**） |
| `symbol_categories.plist` / `symbol_search.plist` / `symbol_order.plist` | 一致 |
| `name_aliases.strings` / `nofill_to_fill.strings` / `semantic_to_descriptive_name.strings` | 一致 |
| `symbol_restrictions.strings` / `categories.plist` / `legacy_flippable.plist` | 一致 |
| `Assets.car` | **サイズは異なる**（macOS 160,168,520 / iOS 151,235,144） |

**`Assets.car` の差はグリフ名の差ではない。** `assetutil --info` で展開して名前集合を比較したところ、
**両方とも 8,305名で差分ゼロ**（iOS 側に1件多い `ZZZZPackedAsset-3.0.1-gamut0` は内部パック用の器であってシンボルではない）。
差はレンディション数（macOS 174,291 / iOS 144,507）＝**倍率と描画バリアントの数**である。

読んだ場所（絶対パス）:

```
/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/
/Library/Developer/CoreSimulator/Volumes/iOS_23F77/Library/Developer/CoreSimulator/Profiles/
  Runtimes/iOS 26.5.simruntime/Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/
  SFSymbols.framework/CoreGlyphs.bundle/
```

**文書側の裏取り。** HIG の SF Symbols ページ末尾:

> "Platform considerations — No additional considerations for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS."

SF Symbols 製品ページ（現在は SF Symbols 8 beta の記述）:

> "These new symbols are available in apps running iOS 27, iPadOS 27, macOS 27, watchOS 27, tvOS 27, and visionOS 27."

**新シンボルが全プラットフォームへ同時に載ることは Apple 自身が書いている。**

**ただし「カタログは常に共通である」と明言した Apple の一次情報は見つからなかった。**
上記2つはそれを強く含意するが、断定はしていない。
**共通性は観測された不変条件であって、文書化された保証ではない。**

### 2. プラットフォーム別の可用性はあるか — **データモデルにその軸が存在しない（実測）**

**これが今回いちばん構造的な発見である。** `name_availability.plist` は2つのキーしか持たない。

- `symbols`: **シンボル名 → 「年」文字列が1つだけ**（例 `timer` → `2019`）
- `year_to_release`: **年 → 全プラットフォームのバージョンの対応表**

```
2019   → iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0,  visionOS 1.0
2020   → iOS 14.0, macOS 11.0,  tvOS 14.0, watchOS 7.0,  visionOS 1.0
2024   → iOS 18.0, macOS 15.0,  tvOS 18.0, watchOS 11.0, visionOS 2.0
2025   → iOS 26.0, macOS 26.0,  tvOS 26.0, watchOS 26.0, visionOS 26.0
2025.1 → iOS 26.1, macOS 26.1,  tvOS 26.1, watchOS 26.1, visionOS 26.1
```

**シンボル単位でプラットフォームを分ける欄がそもそも無い。**
「iOS 13.0+, macOS 10.15+」という注記は、**1つの年から表引きで機械的に生成されている**のであって、
プラットフォーム別に採取された事実ではない。
**したがって「片方にしか無いシンボル」も「導入バージョンが片方だけずれるシンボル」も、この形式では表現できない。**

HIG も可用性を**バージョンの問題として**書いている。

> "Availability of individual symbols and features varies based on the version of the system
> you're targeting. Symbols and symbol features introduced in a given year aren't available
> in earlier operating systems."

**注意すべき非対称が1つある。** 年→バージョンの対応は**プラットフォーム間で同じ数字ではない**。
2019年組は macOS 10.15 に対応づくが、`imageWithSystemSymbolName:` 自体が `API_AVAILABLE(macos(11.0))` である。
**メタデータ上の可用性と API の可用性が一致しない区間が存在する**（macOS 10.15）。
本プロジェクトは 26 系のみが対象なので実害は無いが、事実として記録する。

### 3. macOS で `nil` でないことは、iOS を保証するか — **問いを2つに割る必要がある**

**3a. 「名前がカタログに在ること」の保証 → する**（macOS 26.5 と iOS 26.5 に限れば、実測）

カタログが完全一致している以上、名前の実在という一点については macOS 側の判定がそのまま iOS 側に移る。

名前空間の衝突リスクも無い。`NSImage(systemSymbolName:)` が万一 AppKit の旧来 `NSImageName`（SDK に139個）へ
フォールバックしたとしても、**それらは全て `NS` で始まり、カタログ側に `NS` で始まる名前は0件**である。

**3b. 「対象 OS で描けること」の保証 → しない。ここが穴である**

`symbolExists(_:)` が問い合わせているのは、**テストを走らせている実機の OS のカタログ**である。
ヘッダの文言もそれを裏づける。

```
/// @param name A name from the system's SF Symbols catalog
+ (nullable instancetype)imageWithSystemSymbolName:(NSString *)name
        accessibilityDescription:(nullable NSString *)description API_AVAILABLE(macos(11.0));
```

**「the system's catalog」——動いているシステムのカタログである。普遍のカタログではない。**

`Package.swift` の配備対象は `.macOS(.v26), .iOS(.v26)` ＝ **26.0**。CI が回すのは **macOS 26.5**。
**この 0.5 の差に落ちるシンボルは実在する。**

| 導入年 | 対応バージョン | 該当シンボル数 | macOS 26.5 の CI | 26.0 の実機 |
| :--- | :--- | ---: | :--- | :--- |
| 2025 | iOS/macOS **26.0** | 616 | 通る | 通る |
| **2025.1** | iOS/macOS **26.1** | **29** | **通る** | **`nil` になる** |

**将来 `2025.1` 以降のシンボルを名前リストに足せば、CI は緑のまま、実機でアイコンが消える。**
**そしてこれは iOS 固有の話ですらない — macOS 26.0 の実機でも同じように消える。**

**コメントが立てている「プラットフォーム」という軸は、この検査で実際に危険な軸ではない。**
危険なのは**検査ホストの OS バージョンと配備対象の差**であり、
**`symbolExists` はその差を構造的に観測できない**（常に自分より新しいカタログに問い合わせてしまう）。

### 4. 名指しされた13個 — **すべて安全。ただし副産物が2つ出た**

**13個すべて両プラットフォームのカタログに存在し、すべて導入年 ≤ 2024。**
**よって iOS 26.0 / macOS 26.0 で全て利用可能。片側にしか無いものは1つも無い。**

| シンボル名 | 導入年 | iOS | macOS |
| :--- | :--- | :--- | :--- |
| `iphone.gen3` / `iphone.gen3.slash` | 2022.1 | 16.1 | 13.0 |
| `laptopcomputer` | 2020 | 14.0 | 11.0 |
| `laptopcomputer.slash` | 2022.1 | 16.1 | 13.0 |
| `arrow.trianglehead.2.clockwise` | 2024 | 18.0 | 15.0 |
| `cup.and.saucer` | 2021 | 15.0 | 12.0 |
| `moon.zzz` / `largecircle.fill.circle` / `timer` / `folder` / `circle` | 2019 | 13.0 | 10.15 |
| `gearshape` / `paintpalette` | 2020 | 14.0 | 11.0 |

**4a. `largecircle.fill.circle` は実体を持たないエイリアスである。**
`Assets.car` を引くと、この名前だけ**両プラットフォームでグリフ0件**。`name_aliases.strings` に登録がある。

```
'largecircle.fill.circle' -> 'inset.filled.circle'
```

エイリアス表も両プラットフォームで SHA-256 一致しているので**解決結果は同じであり、動作に問題は無い。**
ただしこの名前は他の12個とは**解決経路が違う。**

**4b. `iphone.gen3` / `iphone.gen3.slash` は使用制限付きシンボルである。**
`symbol_restrictions.strings`（605件、両プラットフォームで一致）に登録がある。

> "This symbol may not be modified and may only be used to refer to Apple's iPhone."

HIG も対応する規定を持つ。

> "SF Symbols includes copyrighted symbols that depict Apple products and features.
> You can display these symbols in your app, but you can't customize them."

**Mdoro の用法は制限に適合している。** `ConnectionStatus.symbolName` は接続先の iPhone そのものを指しており、
"used to refer to Apple's iPhone" に該当する。**変更や違反ではない。**
ただし**OSS として公開する以上、制限付きシンボルを使っていること自体は把握しておく価値がある**
（13個中2個が該当し、テストはこれを一切区別していない）。

### 5. 実行せずに可用性を確かめる手段 — **ある。3つ**

**(1) 稼働中の OS が持つランタイムカタログ — 最も正確**

```
/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist
```

`plutil` や `plistlib` で読める。バンドル ID は `com.apple.CoreGlyphs`、CFBundleVersion 190.4.0.1。
iOS 側は、インストール済みシミュレータランタイム内の同じバンドル
（**マウント済みで、読むのにシミュレータの起動は不要**。`xcrun simctl runtime list -j` で `mountPath` が引ける）。

**(2) SF Symbols アプリのメタデータ — ただし超集合であり、そのままでは使えない**

```
/Applications/SF Symbols Beta.app/Contents/Resources/Metadata/name_availability.plist
```

**この落とし穴は明記しておく価値がある。** インストールされているのは **SF Symbols 8 beta（8.0 / build 123）**で、
カタログは **9,476名。稼働中の macOS 26.5 は 9,184名。**

- 差分は**きっかり 292件で、すべて導入年 2026（＝ iOS/macOS 27）**
- **アプリにあって OS に無い名前は 292。OS にあってアプリに無い名前は 0**
- 共通する名前の**導入年の食い違いは 0件**

**アプリのカタログ ＝ OS のカタログ ＋ 次期 OS の新規シンボル**である。
**「SF Symbols アプリで見つかったから使える」は、26 系を対象にする限り誤りうる。**

**(3) SDK ヘッダ — API の可用性だけ。シンボル名は分からない**

**シンボル名の一覧を持つヘッダや、名前を検査する Apple 公式のコンパイル時 API は見つからなかった。**
SwiftUI にも `Image(systemName:)` の名前を静的に検証する仕組みは無い。

### 前提への疑い — この検査は何を確かめたかったのか

`peerSymbolsOfBothPlatformsExist` は名前を13個ベタ書きしている。しかし `ConnectionStatus` の全6名は、
**直下の `connectionStatusSymbolsExist` がすでに列挙で検査している。**
13個のうち3つは、macOS 上では**両方のテストが同じ名前を二度検査している**
（`#if os(macOS)` 側で `symbolName` と `peerSymbolName` が同一のため）。

**この検査が固有に足しているのは、実質 `laptopcomputer` / `laptopcomputer.slash` の2つだけである。**
残る8つ（`timer` 等）は `ConnectionStatus` とは無関係な、別の場所で使う名前をここに間借りさせたものである。

**「もう片方の名前を名指しで確かめる」という設計意図そのものは正しく、機能している。**
カタログが共通なので `laptopcomputer` 系の検査は macOS 上で有効に働く。
**壊れているのは意図ではなく、コメントが挙げた根拠の軸である。**

## 確度

| 主張 | 確度 |
| :---- | :---- |
| カタログは macOS 26.5 と iOS 26.5 で同一（メタデータ10ファイルが SHA-256 一致、グリフ名 8,305 で差分ゼロ） | **実測** |
| 可用性はプラットフォーム別ではなくバージョン別。**データモデルにプラットフォームの軸が無い** | **実測** |
| HIG は可用性をバージョンの問題として書き、"No additional considerations" とする | **文書化** |
| `systemSymbolName:` が引くのは**動いている OS のカタログ**。26.5 で非 `nil` でも 26.0 で `nil` になりうる。**導入年 2025.1 のシンボルが 29件実在** | **実測**（+ 文書化） |
| `largecircle.fill.circle` は実体を持たないエイリアス | **実測** |
| `iphone.gen3` / `.slash` は使用制限付き。**Mdoro の用法は適合** | **文書化** |
| SF Symbols アプリのカタログは稼働 OS の**超集合**（8 beta = 9,476 = 9,184 + 次期 292） | **実測** |
| **「カタログは常に共通」と明言した Apple の一次情報** | **見つからなかった**（含意はあるが断定ではない） |

## 確かめられなかったこと

**推測で埋めない。**

- **`NSImage(systemSymbolName:)` / `UIImage(systemName:)` が `CoreGlyphs.bundle` を参照していることを、
  実行で証明していない。** バンドル ID・配置・内容から**きわめて強く示唆される**が、
  **API との結線を明記した Apple の一次情報は見つからなかった。これは推論である**
- **実機の iPhone で確認していない。** iOS 側は**シミュレータランタイムのイメージを読んだだけ**であり、
  実機 iOS 26.5 のカタログと同一である保証は文書上見つけられなかった
- **測ったのは macOS 26.5 と iOS 26.5 の1組だけ**であり、**将来のバージョンで成り立ち続ける保証ではない**
- watchOS / tvOS / visionOS は比較していない（スコープ外）
- `Assets.car` のレンディション数の差の内訳を完全には分解していない

## 影響を受ける記述

**列挙のみ。直し方はこの記録では判断しない。**

| 箇所 | 理由 |
| :---- | :---- |
| `SymbolNameTests.swift:22` のコメント | **主張は真だが、検査が必要としている保証ではない。** 効く軸はプラットフォームではなく OS バージョン |
| `symbolExists(_:)` の検査方法 | **検査ホストのカタログしか見られない。** 配備対象（26.0）との差を構造的に観測できない |
| `peerSymbolsOfBothPlatformsExist` の名前リスト | 13個中3個は `connectionStatusSymbolsExist` と重複。**固有に足しているのは実質2個** |
| `largecircle.fill.circle` | エイリアスであり、他の12個と解決経路が違う |
| `iphone.gen3` / `iphone.gen3.slash` | **使用制限付き。** 公開前に把握しておく価値がある |
