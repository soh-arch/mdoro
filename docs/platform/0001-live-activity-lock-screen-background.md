# 0001. ロック画面の Live Activity は何の上に描かれるか

- **調査日**: 2026-08-29
- **対象**: iOS 26
- **依頼の理由**: REQ-UIX-027（MUST）が「背景が利用者の壁紙であることを前提に」と書いているが、
  **その前提が確認されていない疑いがあった**（公開前の監査 POL-057）

## 問い

依頼した内容をそのまま残す。

1. ロック画面の Live Activity の背景は何か。壁紙の上に直接合成されるのか、それとも
   **システムが用意した器（マテリアル等）の上に描かれる**のか
2. 開発者が背景を指定できるのか。できるなら何を、指定しなかったときは何になるのか
3. `.primary` / `.secondary`（システムの意味色）は、その背景に対して適切に追随するのか
4. ダークモード / ライトモードで何が変わるか。器は壁紙の明るさに追随するのか
5. `activitySystemActionForegroundColor` は何を決めるのか
6. ダイナミックアイランド（コンパクト / 展開 / ミニマル）は、ロック画面と同じ扱いか

**前提を疑ってよい**と明示して依頼した。「壁紙の上に直接描く」が誤りなら、それが一番重要な報告である、と。

## 答え

**条文の前提は誤りである。** ロック画面の Live Activity は壁紙の上に直接合成されるのではなく、
**システムが用意した器（ウィジェットコンテナ）の中に描かれ、その器の背景は既定で
ライトモード＝白／ダークモード＝黒**という、システム外観に追随する背景である。

開発者は `activityBackgroundTint(_:)` でこれを差し替えられ、指定しなければ上記の既定が入る。
したがって「壁紙前提」も「コントラスト保証はロック画面上では成立しない」も、
**既定背景のままでは成り立たない。**

## 根拠

### 背景は何か

**ActivityKit「Creating custom views for Live Activities」§Use custom colors**

> "By default, the Lock Screen presentation — including the banner that appears on devices that
> don't support the Dynamic Island — **uses a solid white background color in Light Mode and a
> solid black background color in Dark Mode.**"

https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities

**SwiftUI `activityBackgroundTint(_:)`**（iOS 16.0+、deprecated なし）

> "The background tint color to apply. **To use the system's default background material, pass `nil`.**"

https://developer.apple.com/documentation/swiftui/view/activitybackgroundtint(_:)

**器が存在することの補強**: WWDC26 セッション 223「Live Activities essentials」が
`showsWidgetContainerBackground` 環境値について "This value is **true on the Lock Screen**" と述べる。
ただし**これは iOS 27 前提のセッション**であり、iOS 26 に対する直接の根拠としては使わず補強にとどめる。

**表現が割れている点**: Apple 自身が「solid ... color」と「default background material」で
言い方を統一していない。**不透明な単色なのか厚いマテリアルなのかは一次情報で確定しない。**
ただしどちらであっても**壁紙ではなく、システムが供給する器の背景**である。

### 背景の指定

| | |
| :-- | :-- |
| API | `activityBackgroundTint(_ color: Color?)`（SwiftUI、iOS 16.0+） |
| 適用範囲 | **ロック画面表示のみ**（コンパクト／ミニマル／展開には効かない） |
| `nil` を渡したとき | システム既定 |
| 半透明 | 可。"To set the translucency of the custom background color, use the `Color.opacity(_:)` view modifier or specify an opaque background color."（ActivityKit 同記事） |
| ビュー内の `.background {}` | 効く。ただし器の**中**に描かれる |

**HIG の指定不可宣言**

> "You can't customize background colors for compact, minimal, and expanded presentations.
> However, you can use a custom background color for the Lock Screen presentation."

### `.primary` / `.secondary` の追随

**直接そう書いた一次情報は見つからなかった。** 以下は**文書化された2つの事実からの帰結**である。

- **既定背景のとき: 追随する。** 背景がライト＝白／ダーク＝黒であり、`colorScheme` は
  「ユーザーがダークモードを有効にしているかどうか」を反映する（SwiftUI `colorScheme` ドキュメント）
- **カスタム tint を敷いたとき: 追随しない。** 根拠は HIG の裏返し —

  > "If you use a custom background color, **choose a color that works well in both modes or a
  > different color for each appearance.**"

  つまり**システムは tint から前景色を導出しない。** 導出が入るのは dismiss ボタンだけで、それも

  > "The system automatically generates a matching dismiss button based on the background and
  > foreground colors of your Live Activity. **Verify that the generated color matches your design**"

  と確認を求めている。

### ダーク / ライト

**HIG > Live Activities > Lock Screen presentation**

> "**By default, a Live Activity on the Lock Screen uses a light background color in the light
> appearance and a dark background color in the dark appearance.** ... Verify your choices on a
> device with an Always-On display with reduced luminance because the system adapts colors as
> needed in this appearance."

**器が追随するのは壁紙の明るさではなく、システムの外観設定（ダークモード）である。**
壁紙の明るさに追随するという記述は、HIG・API リファレンス・ActivityKit の記事・
調べた WWDC セッションの**いずれにも存在しない。**

**Always-On**（ActivityKit 同記事の Note）

> "On devices that include an Always-On display, the system dims the screen to preserve battery
> life and **renders Live Activities on the Lock Screen as if in Dark Mode.** Use SwiftUI's
> `isLuminanceReduced` environment value to detect reduced luminance ..."

### 条文が読み違えた可能性のある箇所

HIG は壁紙について、背景の説明ではなく**設計上の注意**として一度だけ触れている。

> "Choose colors that work well on a personalized Lock Screen. People customize their Lock Screen
> with wallpapers, custom tint colors, and widgets. To make a Live Activity fit a custom Lock
> Screen aesthetic while remaining legible, use custom background or tint colors and opacity
> **sparingly**."

**「背景が壁紙である」ではなく「壁紙の隣に並ぶので、透明度や独自色を使いすぎるな」**という趣旨である。

### `activitySystemActionForegroundColor`

SwiftUI（iOS 16.1+）

> "**The text color for the auxiliary action button that the system shows next to a Live Activity
> on the Lock Screen.**" / "Pass `nil` to use the system's default color."

**Live Activity 本体の文字色ではない。** システムが横に添える終了ボタンの文字色だけである。

### ダイナミックアイランド

**別扱いである。**

- HIG: "**Live Activities in the Dynamic Island use a black opaque background.**"
- ActivityKit 記事: "Live Activities in the Dynamic Island use a **black background color with
  white text**." / "**You can't change the background color** of Live Activities in the Dynamic Island."
- 色を指定できるのは `DynamicIsland.keylineTint(_:)`（iOS 16.1+）のみ —
  ダークモード時に島の周囲に出るキーラインの色

壁紙も外観設定も関係しない。**不透明な黒に対して固定値でコントラストを組める、唯一の面である。**

### iOS 26 での変更

**無い。**

- **ActivityKit updates / June 2025**: Mac メニューバー、CarPlay、`request(...start:)` による
  予約開始のみ。背景の記述なし
- **WidgetKit updates / June 2025**: Liquid Glass 対応は `WidgetAccentedRenderingMode`
  （**ホーム画面ウィジェット**の accented rendering の話）
- **iOS 26 リリースノート**および**「Adopting Liquid Glass」**: "Live Activity" / "ActivityKit" /
  "WidgetKit" の語が**0件**（取得して grep 済み）
- `activityBackgroundTint(_:)` は iOS 16.0+ のまま、deprecation なし
- HIG > Live Activities の最終更新は **2025-12-16**（iOS 26 出荷後。仕様表に iPhone 17 / iPhone Air を収載）

**副次的な変更点**: 現行 HIG は "The system uses the Lock Screen presentation to display
**a banner at the bottom of the Lock Screen**" と書いている。「通知リストの上部」ではなく**下部**である。

## 確度

| 区分 | 内容 |
| :---- | :---- |
| **文書化** | 背景の既定色／`activityBackgroundTint` の挙動と適用範囲／ダーク・ライトの追随先／Always-On の扱い／`activitySystemActionForegroundColor` の対象／ダイナミックアイランドの固定黒／iOS 26 で変更が無いこと |
| **帰結**（明文なし） | `.primary` / `.secondary` が既定背景に追随すること。**文書化された2つの事実からの帰結であり、直接の明文は無い** |
| **二次情報** | なし（個人ブログ・Stack Overflow は使っていない） |
| **不明** | 下記 |

## 確かめられなかったこと

1. **既定背景の実際の不透明度。** Apple 自身が "solid ... color"（ActivityKit 記事）と
   "default background material"（API リファレンス）で表現が割れており、一次情報で決着しない。
   **実測もしていない**（simulator に Clock アプリが無く、本リポジトリの Live Activity は
   Mac サーバ接続が前提のため、この調査の範囲では起動経路を作れなかった）
2. カスタム tint を半透明にしたとき、その下に来るのが壁紙なのか既定マテリアルなのか
3. Live Activity の `widgetRenderingMode` が `.fullColor` であるという明文。
   `WidgetRenderingMode` の Overview は "The system can modify the appearance of **accessory
   family** widgets" と対象を限定しており、Live Activity には触れていない
4. **iOS 26 実機での見た目。** 文書上の変更が無いことを確認しただけである
5. WWDC26-223 は iOS 27 前提のセッションのため、iOS 26 に対する直接の根拠としては使っていない

## 影響を受ける記述

- **`docs/SPEC.md` REQ-UIX-027** — 「背景が利用者の壁紙であることを前提に、固定値と半透明素材で
  組むこと。コントラスト保証はロック画面上では成立しない」。**前提が誤り**
- **`PomodoroMac/PomodoroWidget/MdoroWidgetLiveActivity.swift` のコメント** —
  `// REQ-UIX-027: 背景は壁紙なので「対 --bg」のコントラスト保証が成立しない。`
  **同じ誤った前提を引いている**
- **`docs/CONTEXT.md` §3** — Live Activity についての記録があるが、背景と配色には触れていない

## 主要な出典

- [ActivityKit: Creating custom views for Live Activities](https://developer.apple.com/documentation/activitykit/creating-custom-views-for-live-activities)
- [SwiftUI: activityBackgroundTint(_:)](https://developer.apple.com/documentation/swiftui/view/activitybackgroundtint(_:))
- [SwiftUI: activitySystemActionForegroundColor(_:)](https://developer.apple.com/documentation/swiftui/view/activitysystemactionforegroundcolor(_:))
- [HIG: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities/)
- [WidgetKit: WidgetRenderingMode](https://developer.apple.com/documentation/widgetkit/widgetrenderingmode)
- [ActivityKit updates](https://developer.apple.com/documentation/updates/activitykit) / [WidgetKit updates](https://developer.apple.com/documentation/updates/widgetkit)
- [iOS & iPadOS 26 Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26-release-notes) / [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [WWDC25 session 278: What's new in widgets](https://developer.apple.com/videos/play/wwdc2025/278/) / [WWDC26 session 223: Live Activities essentials](https://developer.apple.com/videos/play/wwdc2026/223/)（iOS 27 前提、補強のみ）
