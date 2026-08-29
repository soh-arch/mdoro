# 0003. メニューバーの地は何で、そこに色を載せられるのか

- **調査日**: 2026-08-29
- **対象**: macOS 26（Tahoe）/ macOS 26.5 SDK / Xcode 26.6 (17F113)
- **依頼の理由**: REQ-COL-022（MUST・`SPEC.md:1028`）が「**メニューバーの地は可変であり、
  コントラストを保証できない**」を前提にアクセント色を禁じているが、出典が無かった（軸 K・POL-061）。
  [0038](../decisions/0038-platform-facts-are-not-the-specs-job.md) 自身が「同じ問題に2つの答えがあり、
  片方は検証されていなかった」とこの条文を名指ししている。**検証されていなかった片方（壁紙・
  [0001](0001-live-activity-lock-screen-background.md)）は誤りだった**

## 問い

依頼した内容をそのまま残す。**それぞれ別に確度を付けること**と指示した。

1. **地は何か。** macOS 26 のメニューバーの背景は実際に何の上に描かれるか。壁紙が透けるのか、
   システムが不透明な地を敷くのか。「Reduce transparency」が有効なときはどうか
2. **OS は前景色を保証するか。** `NSImage.isTemplate` のテンプレート画像を `NSStatusItem` に載せたとき、
   AppKit は地に応じて前景の色を調整すると文書化されているか
3. **色は本当に使えないのか。** 任意の色を載せることは、可能か / 非推奨か / 禁止か。
   **「できない」と「Apple が勧めていない」を区別すること**
4. **`isLuminanceReduced` / ダークモード / Reduce transparency / Increase contrast** のうち、
   描画に影響すると文書化されているものはどれか。**アプリ側が読める API があるか**も含めて

**前提を疑ってよい**と明示して依頼した。**ビルド・シミュレータ・実機に触れないこと**も指示した
（人間が席を外していたため）。

## 答え

**前提の半分は正しく、半分は誤りである。**

**「メニューバーの地は可変である」は正しい**（文書化）。[0001](0001-live-activity-lock-screen-background.md) と違い、**ここは前提が崩れない。**

**しかし「だからコントラストを保証できない」→「色を使えない」には裏づけが無い。**
それどころか macOS 26.5 SDK の `NSStatusBarButton.h` は、条文が処方しているまさにその手段
（テンプレート画像）について "**This guarantees that the button will look correct**" と、
**保証すると明記している。**

**条文は、理由と処方が噛み合っていない。** 処方（テンプレート画像）は Apple の推奨と一致するが、
**理由（保証できない）は、その処方が成り立つ根拠の裏返しである。**

**そして REQ-UIX-035 の「色を使えないため」は、API の事実として誤りである。色は使える。禁止されていない。**

## 根拠

### 1. 地は何か — 「可変」は文書化。**合成の詳細は不明**

**macOS Tahoe 26 の Mac ユーザガイド「Change display colors on Mac」§Make transparent items solid**

> "Some windows and areas of the desktop, such as the Dock and menu bar, appear transparent by default.
> You can turn these transparent areas a solid gray to make it easier to distinguish them from the background."

**「What's new in the updates for macOS Tahoe 26」**

> "A transparent menubar makes your display feel larger."

**HIG『The menu bar』§Menu bar extras**（地が明暗どちらにもなることを Apple 自身が前提にしている）

> "...so it looks good on both **dark and light menu bars**, and when your menu bar extra is selected."

したがって、メニューバーは**既定で透過**であり、**Reduce transparency を有効にすると solid gray になる。**
明るいメニューバーと暗いメニューバーの両方が存在する。

**ただし、開発者向け文書にメニューバーの背景の記述は一つも見つからなかった。**

- HIG『The menu bar』: 背景・透明度・マテリアルへの言及は**ゼロ**（全文を機械抽出して確認）
- HIG『Materials』『Color』『Icons』『Accessibility』: "menu bar" の出現**ゼロ**
- `Adopting Liquid Glass`: "menu bar" は5箇所あるが**すべて iPadOS のメニューバー**について
- WWDC25 セッション 310「Build an AppKit app with the new design」: "menu bar" は1箇所
  （メニュー項目のアイコンの話）。"status item" / "NSStatusItem" / "template" は**ゼロ**

**確定できなかった点**: 壁紙が素通しなのか、ぼかし・輝度調整を伴うマテリアルなのか。
Liquid Glass の regular / clear のどちらの挙動に相当するのか。**「デスクトップティント」との関係** —
HIG『Dark Mode』§macOS が述べるティントは "**window backgrounds**"、システム設定の説明文は
"certain window areas, such as toolbars or status bars"（＝**ウインドウ内の**ステータスバー）で、
**いずれもメニューバーの話ではない。**

### 2. OS は前景色を保証するか — **保証すると書いてある**

**macOS 26.5 SDK, `NSStatusBarButton.h` のクラスコメント**

> "When a template image is set as the `image` property of the status bar button, it is rendered with
> the correct menu bar style. **This guarantees that the button will look correct in various button
> states and appearances (such as dark menu bar).**"

**HIG『The menu bar』§Menu bar extras**

> "Both interface icons and symbols use black and clear colors to define their shapes;
> **the system can apply other colors to the black areas in each image so it looks good on both
> dark and light menu bars**, and when your menu bar extra is selected. The menu bar's height is 24 pt."

**`NSStatusItem.h`（deprecated な `view` プロパティのコメント）**

> "Custom views should not be set on a status item. **The button property with a template image will
> allow proper styling of the status item in various states and contexts** and should be used instead."

**重要な限定が2つある。**

**(i) `NSImage.isTemplate` の文書には、地に応じた調整の記述が無い。**

> "Template images are not intended to be used as standalone images. They are always mixed with
> other content and processed to create the desired appearance."

つまり「地に追随する」保証は `NSImage` 側ではなく、**`NSStatusBarButton` が status bar 用に行うこと**
として書かれている。

**(ii) 保証の言葉は "look correct" / "looks good" であり、コントラスト比の保証ではない。**
数値的な保証（4.5:1 等）を述べた Apple の記述は見つからなかった。

### 3. 色は本当に使えないのか — **禁止されていない**

**A. API の制約**

| 手段 | 状態 |
| :--- | :--- |
| `statusItem.button.image` に**非テンプレート画像** | **可能。** 禁止する記述は `NSStatusBarButton.h` にも `NSStatusItem.h` にも文書にも無い |
| `statusItem.button.attributedTitle` に**色付きテキスト** | **可能。** `NSStatusItem.attributedTitle` は 10.14 で deprecated だが、理由は "Use the receiver's **button.attributedTitle** instead" であり、**button 側は非 deprecated** |
| `statusItem.button.contentTintColor` | **色を載せる正規 API が存在する**（下記） |
| `statusItem.view` にカスタムビュー | **これだけが禁止**。"Custom views should not be set on a status item."（10.14 で deprecated） |

**`NSButton.h`（macOS 10.14+）— これが一番重要である**

> "Applies a tint color to **template image and text content**, in combination with other
> theme-appropriate effects. **Only applicable to borderless buttons.** A nil value indicates the
> standard set of effects without color modification. The default value is nil. Non-template images
> and attributed string values are not affected by the contentTintColor."

`NSStatusBarButton : NSButton` なので、このプロパティは status item のボタンに存在する。
しかも "**in combination with** other theme-appropriate effects" —
**テンプレート画像の系統的な扱いと色付けは排他ではない**と書かれている。

**つまり「色を使うとテンプレート画像の恩恵を失う」という関係ではない。**

**B. 文書化された推奨（API の制約とは別）**

**HIG『The menu bar』§Menu bar extras**

> "**Consider** using a symbol to represent your menu bar extra."

**"Consider" は HIG の最も弱い推奨形である**（HIG は強い禁止に "Don't" / "Avoid" を使う）。

**探して見つからなかったもの**: HIG に「メニューバーで色を使うな」に相当する文は**無い。**
『The menu bar』『Icons』『Color』『Materials』『Accessibility』を全文抽出して確認した。
`Color`・`Materials`・`Icons` には "menu bar" の出現自体がゼロである。

参考として、HIG『Color』§Liquid Glass color には次がある（**メニューバー限定の記述ではない**）:

> "Apply color sparingly to the Liquid Glass material, and to symbols or text on the material.
> If you apply color, reserve it for elements that truly benefit from emphasis,
> **such as status indicators** or primary actions."

### 4. どの設定が描画に影響し、アプリから読めるか

| 設定 | メニューバーへの影響 | 読む API | 確度 |
| :--- | :--- | :--- | :--- |
| **Reduce transparency** | **メニューバーが solid gray になる** | `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`（10.10+） | **文書化** |
| **ダークモード / ライト** | メニューバーは明暗どちらにもなる | `NSAppearanceNameAqua` / `NSAppearanceNameDarkAqua` | **文書化** |
| **Increase contrast** | **メニューバーへの影響を述べた記述は見つからなかった。** 設定の説明は "borders around buttons or boxes" | `accessibilityDisplayShouldIncreaseContrast`（10.10+）/ `NSAppearanceNameAccessibilityHighContrast{Aqua,DarkAqua,VibrantLight,VibrantDark}` を `bestMatchFromAppearancesWithNames:` で判定 | **不明**（API は文書化、効果は不明） |
| **`isLuminanceReduced`** | **メニューバーとは無関係**（下記） | — | **前提の誤り** |

**REQ-UIX-035（形状で区別）に直接効く API がある。** `NSAccessibility.h`:

> "Get the current accessibility display option for **differentiate without color**. If this is true,
> **UI should not convey information using color alone and instead should use shapes or glyphs**
> to convey information."

`accessibilityDisplayShouldDifferentiateWithoutColor`（10.10+）。
4つとも `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` で変化を監視できる
（**`NSWorkspace` の notification center。通常の `NotificationCenter.default` ではない**）。
宣言場所は `NSWorkspace.h` ではなく **`NSAccessibility.h` の `NSWorkspace (NSWorkspaceAccessibilityDisplay)` カテゴリ**。

**`isLuminanceReduced` について — 前提を疑った結果**

**この値は macOS のメニューバーとは無関係である。**
`EnvironmentValues.isLuminanceReduced` は macOS 13.0+ で**利用可能とは宣言されている**が、
文書が挙げる成立条件は watchOS のものだけである:

> "On watchOS, the system typically sets this value to `true` when the user lowers their wrist,
> but the display remains on."

**macOS でこれが `true` になる条件を述べた記述は見つからなかった。**
これは Always-On ディスプレイの概念であり、[0001](0001-live-activity-lock-screen-background.md) で
Live Activity の Always-On を扱った際の用語である。**メニューバーの調査に持ち込まれたのは混線と思われる。**

## 確度

| 主張 | 確度 |
| :---- | :---- |
| メニューバーは既定で透過。Reduce transparency で solid gray になる | **文書化**（出典は開発者向けではなく Apple 一次のユーザ向け文書） |
| 合成の詳細（素通しか、ぼかしを伴うマテリアルか） | **不明** |
| テンプレート画像なら OS が地に応じて正しく描く | **文書化**（`guarantees` という語で明記） |
| **コントラスト比**を保証する | **不明**（そう書いた一次情報は無い。"look correct" 止まり） |
| 色は API 上可能で、禁止されていない | **文書化**（禁止の不在＋`contentTintColor` の存在） |
| Apple はシンボル／テンプレート画像を推奨している | **文書化**（ただし "Consider" の強さ） |
| `isLuminanceReduced` がメニューバーに影響する | **前提の誤り**（macOS での成立条件は不明） |

## 確かめられなかったこと

**推測で埋めない。実行を禁じたため、次は静的には確認できなかった。**

- **`NSStatusBarButton` が `contentTintColor` の言う "borderless buttons" に該当し、実際に色が乗るか。**
  ヘッダは borderless に限ると書いているが、status bar button の `bezelStyle` / `isBordered` の実値は
  静的には確認できない。**REQ-UIX-035 を見直すなら、ここが唯一の実測すべき点である**
- 非テンプレート画像が status bar で原色のまま描かれるか、系統的に加工されるか
- SwiftUI の `MenuBarExtra` のラベルに `.foregroundStyle` / `.renderingMode(.original)` が効くか。
  **`MenuBarExtra` の文書には色・テンプレート画像への言及が一切ない**（全文確認）

## 影響を受ける記述

**列挙のみ。直し方はこの記録では判断しない。**

| 条文の主張 | 判定 |
| :--- | :--- |
| 「メニューバーの地は可変」 | **正しい**（文書化）。[0001](0001-live-activity-lock-screen-background.md) と違い前提は崩れない |
| 「コントラストを保証できない」（`SPEC.md:1028` の括弧内） | **テンプレート画像については誤り。** `NSStatusBarButton.h` が "This guarantees that the button will look correct" と明記。ただし**コントラスト比**の保証ではない |
| 「アクセント色を使用せず」（処方そのもの） | **Apple の推奨と一致する**（HIG "Consider using a symbol"）。**推奨の強さは "Consider"** |
| REQ-UIX-035「**色を使えないため**、形状で区別する」（`SPEC.md:843`） | **誤り。色は使える。** `contentTintColor` はテンプレート画像に色を載せる正規 API で、系統的な扱いと**併用**すると書かれている。禁止されているのは `statusItem.view` だけ |
| [0031](../decisions/0031-the-menu-bar-mark-shows-the-session.md) | 同じ理由に乗っている |

**形状で区別すること自体には、別の一次的根拠がある** —
`accessibilityDisplayShouldDifferentiateWithoutColor` の "should use shapes or glyphs"。
**理由が変わっても処方が残る余地はある。**

## 参照した一次情報

- `NSStatusBarButton.h` / `NSStatusItem.h` / `NSButton.h` / `NSAccessibility.h` / `NSAppearance.h` —
  `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk/System/Library/Frameworks/AppKit.framework/Versions/C/Headers/`
- [HIG: The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar) /
  [Color](https://developer.apple.com/design/human-interface-guidelines/color) /
  [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) /
  [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode) /
  [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) /
  [Icons](https://developer.apple.com/design/human-interface-guidelines/icons)
- [NSImage.isTemplate](https://developer.apple.com/documentation/appkit/nsimage/istemplate) /
  [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) /
  [isLuminanceReduced](https://developer.apple.com/documentation/swiftui/environmentvalues/isluminancereduced)
- [Change display colors on Mac (macOS Tahoe 26)](https://support.apple.com/guide/mac-help/change-display-colors-mchl11ddd4b3/mac) /
  [Change Appearance settings on Mac](https://support.apple.com/guide/mac-help/change-appearance-settings-mchlp1225/mac) /
  [What's new in macOS Tahoe 26](https://support.apple.com/en-us/122868)
- [WWDC25 セッション 310](https://developer.apple.com/videos/play/wwdc2025/310/)（**言及が無いことを確認するために**参照）

**二次情報は一切使っていない。**
