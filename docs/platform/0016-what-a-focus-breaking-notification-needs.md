# 0016. 集中モードを貫く通知に、何が要るか

- **調査日**: 2026-09-18
- **対象**: UserNotifications（iOS 15.0 / macOS 12.0 以降）。利用者側の設定は **macOS Tahoe 26** の固定ページで確認。iOS は現行版の iPhone User Guide
- **問い**: `interruptionLevel = .timeSensitive` が効くために何が要るか。**capability は要るか。利用者側の設定は要るか。無償の Personal Team で取得できるか**
- **実測はしていない。** macOS も Xcode も無い環境からの調査であり、**すべて文書の上での確認である**

## 問いの出どころ

`REQ-NTF-005` は通知を Time Sensitive として送ると定める。**2026-08-27、無償の Personal Team の実機で
「`.timeSensitive` を指定しても集中モード中は届かない」ことが観測された。**
`SPEC.md` v2.23（POL-070）は、**その観測が示すのは配信の側だけであるとして**、
「無償枠では利用できない」という断定を取り下げ、**`OPEN-007`（capability を有効化できるか）を未決のまま残した。**

**リポジトリには entitlements ファイルが1つも無く、`.pbxproj` に `CODE_SIGN_ENTITLEMENTS` も無い**
（2026-09-18・`grep` で確認）。**capability が要るのかどうかを、誰も確かめていなかった。**

## 分かったこと

### capability は要る

**`UNAuthorizationOptions.timeSensitive` は、導入されたのと同じバージョンで deprecated になっている。**
その理由として Apple が書いているのは1文だけである。

> `deprecationSummary`: **"Use time-sensitive entitlement"**

| プラットフォーム | 導入 | 非推奨 |
| :---- | :---- | :---- |
| iOS / iPadOS / Mac Catalyst / tvOS | 15.0 | **15.0** |
| macOS | 12.0 | **12.0** |
| watchOS | 8.0 | **8.0** |
| visionOS | 1.0 | **1.0** |

出典: <https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/timesensitive>
（本文は JS 描画のため、`https://developer.apple.com/tutorials/data/documentation/…json` から取得した）

**つまり Apple は「認可オプションで要求する」方式を最初から捨て、entitlement 方式に一本化している。**
WWDC 2021 セッション 10091 も同じことを述べる。

> "**To configure Time Sensitive notifications, enable the associated capability via Xcode for your application.**
> Set the Time Sensitive interruption level on the notification request being posted."

出典: <https://developer.apple.com/videos/play/wwdc2021/10091/>

**macOS と iOS で差は無い。** 非推奨の印は両方に同じ文言で付いている。

### 無償の Personal Team では取得できない

Apple Account Help の Supported capabilities 表（`<table>` を直接読んだ。2026-09-18）。

**iOS** — <https://developer.apple.com/help/account/reference/supported-capabilities-ios>

| Capability | ADP | ADEP | Apple Developer |
| :---- | :-- | :-- | :-- |
| **Time Sensitive Notifications** | ✓ | ✓ | **（空欄）** |
| Push notifications | ✓ | ✓ | **（空欄）** |

**macOS** — <https://developer.apple.com/help/account/reference/supported-capabilities-macos>

| Capability | ADP | Developer ID | Apple Developer |
| :---- | :-- | :-- | :-- |
| **Time Sensitive Notifications** | ✓ | ✓ | **（空欄）** |
| Push notifications | ✓ | ✓ | **（空欄）** |

両ページの凡例が `Apple Developer` 列を定義している。

> "**Apple Developer**: Apple Account holders who have agreed to the Apple Developer Agreement to access
> certain resources on the Apple Developer website. **No cost is associated with this agreement and
> developers can't distribute apps.**"

**表の注記にある `* Development only` は、この行には付いていない。**「開発時だけ使える」例外にも当たらない。

⚠ **「`Apple Developer` 列 ＝ Xcode の Personal Team」を1文で述べた Apple の記述は見つからなかった。**
Xcode 側の文書は「your Apple Developer Program **or personal Apple Account**」と書き分けている
（<https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices>）。
**同定は帰結である。**

**有効化しようとしたときに何が起きるかは、個別には書かれていない。**
Xcode の文書が述べるのは、候補そのものが絞られるということである。

> "**The Capabilities library displays only the capabilities available to the target platform and your
> program membership.**"

出典: <https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app>

### 利用者側の門は2つあり、macOS は両方要る

**初回は自動で有効になる。「許可しますか」は出ない。**

> "**The first time a Time Sensitive notification arrives from your app, the system describes how such a
> notification works and gives people a way to turn it off** if they don't agree that the information
> requires their immediate attention."

出典: <https://developer.apple.com/design/human-interface-guidelines/managing-notifications>

**macOS 26 では、通知設定側と集中モード側の2つが要る。両方のページが互いを指している。**

| 場所 | 項目 | そのページが書いていること |
| :---- | :---- | :---- |
| System Settings > Notifications > アプリ | **Allow time sensitive alerts** | "**To show these notifications when a Focus is on, you must also set the option for the Focus in Focus settings.**" |
| System Settings > Focus > 各 Focus | **Time Sensitive Notifications** | "**(Make sure you also select the option that allows apps to send these notifications in Notifications settings.)**" |

出典: <https://support.apple.com/guide/mac-help/notifications-settings-mh40583/26.0/mac/26.0> /
<https://support.apple.com/guide/mac-help/set-up-a-focus-mchl613dc43f/26.0/mac/26.0>

**iOS も2つある。**アプリ側のトグルには**条件節が付いている。**

> "Allow time-sensitive notifications: **If the app supports it**, turn on Time Sensitive Notifications."

出典: <https://support.apple.com/guide/iphone/change-notification-settings-iph7c3d96bab/ios> /
<https://support.apple.com/guide/iphone/allow-or-silence-notifications-for-a-focus-iph21d43af5b/ios>

### HIG の表を、配送の保証として読まない

同じ HIG が、割り込み段階の表では Time Sensitive を**無条件に**「Breaks through Focus: **Yes**」と書く。
**一方、API リファレンスと WWDC は条件付きで書く。**

> "Time Sensitive notifications … can break through system controls such as Notification Summary and Focus.
> **The user can turn off the ability for time sensitive notification interruptions.**"
> — <https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel/timesensitive>

> "these can breakthrough system controls such as notification summary and Focus **if allowed to do so**"
> — WWDC21 10091

⚠ **表は「その段階に何ができるか」の記述であって、届くことの保証ではない。表だけを根拠に条文を書くと外す。**

## 確かめられなかったこと

- ⚠ **entitlement が無いまま `.timeSensitive` を指定したときに何が起きるかは、Apple のどこにも書かれていない。**
  黙って `.active` に落ちるのか、そのまま通るのかが分からない。
  **代入の時点でエラーになる経路だけは無い** —— `interruptionLevel` は `var` であり、`throws` でも failable でもない（帰結）。
- ⚠ **この entitlement には文書ページが存在しない。** Entitlements リファレンスは 168 件を列挙するが、
  `com.apple.developer.usernotifications.time-sensitive` は**無い**（同じ接頭辞では `…critical-alerts` と
  `…filtering` の2件だけが在る。当該キーの JSON は **404**、`…critical-alerts` は 200）。
  **Apple が公開しているのは capability の表示名と "Use time-sensitive entitlement" という散文だけで、
  キー文字列そのものは公開していない。**⚠ **このキーを根拠に条文を書かない。**
  手で書く必要も無い —— Xcode の `+ Capability` が書き込む（[0013](../decisions/0013-pbxproj-is-owned-by-xcode.md)）。
- **`UNNotificationSettings.timeSensitiveSetting` が、entitlement の無いアプリで `.notSupported` を返すか。**
  `UNNotificationSetting` に `.notSupported`（"The setting is not available to your app."）という値は在るが、
  **どういう条件でそれになるかを Apple は書いていない。**
- **利用者側トグルの既定値**（per-app・per-Focus のどちらも）。**2026-08-27 の観測は、ここが原因でもあり得る。**
- **iOS 26 に固定したページの本文。** 目次しか取れなかったので、iOS については現行版の記述までしか言えない。

## 2026-08-27 の観測について

**3つの仮説は独立ではなかった。**

無償の Personal Team では capability を**取得できない**ので、
**「無償枠の制限だから」と「entitlement が無いから」は、同じ1つの原因の表と裏である。切り分けられない。**

**残る「利用者側の許可が無いから」だけが未検証**であり、しかも macOS ではそれが**独立した2つの門**として実在する。
⚠ **ただし、その門を確かめても結論は出ない。** entitlement 側が閉じている限り、
**利用者側を開けても届かないので、どちらが効いているかは分からない。**
**枝を開けられるのは Apple Developer Program に加入した場合だけである。**

## 出典と確度

- **文書化**: capability が要ること（非推奨の文言と WWDC21 10091）。無償枠の列が空欄であること（Supported capabilities 表）。
  利用者側の門が2つあり macOS では両方要ること（Apple のサポートページ2本が互いを指している）。初回が opt-out であること（HIG）。
- **帰結**: 「`Apple Developer` 列 ＝ Personal Team」の同定。代入時にエラーにならないこと。
  Personal Team では候補に現れないこと（capability ライブラリが membership で絞られる、という一般則から）。
- **不明**: entitlement 無しでの実際の挙動。`timeSensitiveSetting` の戻り値。利用者側トグルの既定値。
- **二次情報は結論に使っていない。** 検索に現れたブログ類は読んだが根拠にしていない。
  Apple Developer Forums は本文に到達できず、到達できても一次情報ではない。
