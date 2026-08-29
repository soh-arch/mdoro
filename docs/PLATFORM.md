# PLATFORM — Apple プラットフォームの事実

**ここは「Apple がどう振る舞うか」の索引である。**「Mdoro が何をするか」は `SPEC.md`、
「いま何をしているか」は `CONTEXT.md`。**外部の事実と、自分たちの決定を混ぜない。**

仕様書が「iOS はこうなっている」と主張してはならない。条文は**この文書を参照する**。
条文が外部の事実を抱えると、**事実が変わったときにどの要件が影響を受けるのかが読めなくなる**
（[0038](decisions/0038-platform-facts-are-not-the-specs-job.md)）。

## この文書と `platform/` の関係

| | |
| :---- | :---- |
| **この文書** | 事実の**索引**。1行で何が分かっているかを示し、調査を指す |
| **`docs/platform/`** | **調査そのもの。** 問い・引用・確度・確かめられなかったこと |

**要約はここにしか置かない。調査は要約しない。**
条文が実態と食い違ったとき、**調査が悪いのか・参照が甘いのか・条文の書き方が悪いのか**を
切り分けられるようにするためである。判断の材料を、要約した側の手で削らない。

## 書き方

**1項目につき、次を必ず書く。**

| 欄 | 内容 |
| :---- | :---- |
| **調査** | `docs/platform/` の該当ファイル。**無いなら `未検証`** |
| **確度** | `文書化` / `実測` / `帰結` / `二次情報` / `未検証` |
| **確認日** | いつ確かめたか |
| **対象** | どの OS / Xcode のバージョンについての記述か |

**確度が `未検証` の項目を根拠に条文を書かない。** 書くなら先に確かめる。
**推測を書かない。** 分からないことは「分からない」と書く。
**回避策の提案も書かない。** ここは事実だけを置く場所である。

## 再調査について

**出典と確度が付いた項目は再調査しない。** 疑うなら、要約ではなく**調査のほうを当たる。**

ただし**バージョンが上がったときは別である。** 対象欄より新しい OS で作業するなら、
その項目はもう一度確かめる価値がある。**「再調査しない」は「永久に正しい」という意味ではない。**

調査は `platform-researcher`（`.claude/agents/platform-researcher.md`）が行う。

---

## Live Activity

**調査**: [0001](platform/0001-live-activity-lock-screen-background.md) / **確認日**: 2026-08-29 / **対象**: iOS 26

| 事実 | 確度 |
| :---- | :---- |
| **ロック画面の Live Activity は壁紙の上に描かれない。** システムのウィジェットコンテナの中に描かれ、既定背景はライトモードで白、ダークモードで黒。**追随するのは壁紙の明るさではなくシステムの外観設定** | 文書化 |
| 背景は `activityBackgroundTint(_:)`（iOS 16.0+）で差し替える。**ロック画面表示にのみ効く。** `nil` で既定。半透明にするなら `Color.opacity(_:)`。**コンパクト・ミニマル・展開の背景は指定できない** | 文書化 |
| 既定背景のままなら `.primary` / `.secondary` は外観に追随する | **帰結**（明文なし。文書化された2つの事実から） |
| **コントラストが成立しなくなるのは2つだけ** — (a) カスタム背景色を敷いたとき（システムは tint から前景色を導出しない）、(b) Always-On の輝度低下時（ダークモードとして描かれる。`isLuminanceReduced` で検出） | 文書化 |
| `activitySystemActionForegroundColor` が決めるのは**終了ボタンの文字色だけ**。本体ではない | 文書化 |
| **ダイナミックアイランドは不透明な黒に白文字で固定。** 背景を変更できない。指定できるのは `DynamicIsland.keylineTint(_:)` のみ。**固定値でコントラストを組める唯一の面** | 文書化 |
| iOS 26 で変更なし | 文書化 |

**HIG が壁紙に触れているのは、背景の説明としてではない。** 「壁紙の隣に並ぶので、独自の背景色や
透明度を使いすぎるな」という**設計上の注意**である。**条文はここを読み違えた可能性がある**（[0001](platform/0001-live-activity-lock-screen-background.md)）。

**確かめられなかったこと**（既定背景の不透明度、実機での見た目ほか）は [0001](platform/0001-live-activity-lock-screen-background.md) に列挙してある。

---

## Live Activity — 開始と更新の門

**調査**: [0002](platform/0002-live-activity-background-start-and-suspend.md) / **確認日**: 2026-08-29 / **対象**: iOS 26

| 事実 | 確度 |
| :---- | :---- |
| Live Activity の開始は**原則フォアグラウンドに限られる**（Apple 自身は "In general" と留保）。API は背面からの開始を `ActivityAuthorizationError.visibility` で弾く | 文書化 |
| **開始の例外は APNs だけではない。** `LiveActivityIntent`（iOS 17.0+）は、**アプリを開かずにアプリのプロセスを起動して** `perform()` を走らせ、そこから開始できる。さらに iOS 26.0+ の `request(...alertConfiguration:start:)` は、**指定日時にアプリが背面にあってもシステムが開始する**（`AlertConfiguration` 必須、開始まで `.pending`）。**どちらもサーバーを要さない** | 文書化 |
| **更新にフォアグラウンドは要求されない。** `Activity.update(_:)` はバックグラウンド実行中も使える（Apple は `BackgroundTasks` を例示）。**制約の門は running / suspended であって、フォアグラウンド / 背面ではない** | 文書化 |
| バックグラウンド移行後、`applicationDidEnterBackground(_:)` は **5 秒**で戻る必要があり、戻った直後にシステムが suspend する。`beginBackgroundTask` で延長でき、残りは `backgroundTimeRemaining` で読める | 文書化 |
| **suspend 中はプロセス内のコードが実行されない。** 予定外の状態変化をその時点で Live Activity へ反映することはできない | 文書化 |
| `LiveActivityIntent.perform()` は**アプリ本体のプロセスで走る**（REQ-UIX-024 の記述は正しい） | 文書化 |
| 継続時間の上限は**アクティブ8時間 / 残留を含め計12時間**（REQ-UIX-028 の数値は正しい） | 文書化 |
| **`BackgroundTasks` からの反映は禁止されていない。** `earliestBeginDate` は「それより早く始まらない」ことのみを保証し、起動時刻を保証しない。**不可能ではなく、保証できない** | 文書化 |
| suspend 時に WebSocket が切れるか | **不明。** Apple の記述は TN2277（2011年・iOS 4・**archive**）の「資源を回収して閉じる**ことがある**」のみ。**ただしコードが走らない以上、ソケットの生死は帰結を変えない** |
| **「ロック中」を条件にした制約** | **不明。** どの文書にも見つからなかった。**門は running / suspended であって locked / unlocked ではない** |

**このアプリは `URLSessionWebSocketTask` を使っていない**（Network.framework の `NWConnection` +
`NWProtocolWebSocket`）。**`URLSessionWebSocketTask` についての記述は、このコードには適用できない**
（[0002](platform/0002-live-activity-background-start-and-suspend.md)）。

**残り時間の表示はこの門の対象外である。** `Text(timerInterval:)` はシステムが自律更新するため、
反映できないのは**予定外の状態変化**（一時停止・再開・延長・スキップ・中断）に限られる。

**確かめられなかったこと**（`NWConnection` の実挙動、スケジュール開始の実挙動ほか）は
[0002](platform/0002-live-activity-background-start-and-suspend.md) に列挙してある。

---

## メニューバー（macOS）

**調査**: [0003](platform/0003-menu-bar-ground-and-status-item-color.md) / **確認日**: 2026-08-29 / **対象**: macOS 26 / macOS 26.5 SDK

| 事実 | 確度 |
| :---- | :---- |
| **メニューバーは既定で透過である。** Reduce transparency を有効にすると solid gray になる。**「地が可変」は正しい** | 文書化 |
| **合成の詳細（壁紙の素通しか、ぼかしを伴うマテリアルか）は開発者向け文書に記述が無い。** HIG『The menu bar』は背景に一切触れない | 不明 |
| **テンプレート画像を `statusItem.button.image` に載せると、OS が地に応じて正しく描く。** `NSStatusBarButton.h`: "This guarantees that the button will look correct in various button states and appearances (such as dark menu bar)"。**ただし「正しく見える」であって、コントラスト比の保証ではない** | 文書化 |
| **メニューバーで色を使うことは禁止されていない。** `NSButton.contentTintColor`（10.14+）は「テンプレート画像とテキストに色を適用する。他の theme-appropriate effects と**併用**される」と明記。**禁止されているのは `statusItem.view`（カスタムビュー）のみ。** HIG の "Consider using a symbol" は**推奨であって禁止ではない** | 文書化 |
| `NSStatusBarButton` が `contentTintColor` の言う borderless に該当し、実際に色が乗るかは**未実測**。ヘッダは "Only applicable to borderless buttons" と限定する | 不明 |
| Reduce transparency / Increase contrast / **Differentiate without color** は `NSWorkspace`（`NSAccessibility.h` のカテゴリ）から読め、`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` で変化を監視できる（**`NotificationCenter.default` ではない**）。**Increase contrast がメニューバーに何をするかは文書に無い** | 文書化 / 効果は不明 |
| `accessibilityDisplayShouldDifferentiateWithoutColor` は "UI should not convey information using color alone and instead should use **shapes or glyphs**" と述べる。**形状で区別することには、色の可否とは別の一次的根拠がある** | 文書化 |
| **`isLuminanceReduced` は macOS のメニューバーとは無関係。** macOS 13.0+ で宣言はあるが、文書が挙げる成立条件は watchOS の wrist-down のみ。**Always-On ディスプレイの概念であり、混線と思われる** | **前提の誤り** |

**条文との食い違い**: REQ-COL-022 の括弧内の理由（コントラストを保証できない）と、
REQ-UIX-035 の「**色を使えないため**」は、上表と食い違う（[0031](decisions/0031-the-menu-bar-mark-shows-the-session.md) も同じ理由に乗る）。
**処方（テンプレート画像を使う）は Apple の推奨と一致する。食い違っているのは理由のほうである。**

---

## 未検証（軸 K で確認する）

**`CONTEXT.md` §3 から移した項目である。**
**「一次情報で確認済み」と書かれていたが、9項目のうち出典が残っていたのは1つだけだった。**
調査を当てるまで `未検証` とする。**これらを根拠に新しい条文を書かない。**

| 事実として書かれていたこと | 確度 |
| :---- | :---- |
| iPhone の通知を WebSocket に依存させない。絶対時刻のローカル通知として事前スケジュールする | 未検証 |
| ATS は IP アドレス直接接続を既定で拒否する（iOS 17 / macOS 14 以降）。`NSAllowsLocalNetworking = YES` が必須 | 未検証 |
| ローカルネットワーク許可の状態を問い合わせる API はない。`NWBrowser` の `-65570` と `NWConnection` の `.localNetworkDenied` で検出する。初回取得は必ずフォアグラウンドで | 未検証 |
| サンドボックス下の原子的書き込みは同一ディレクトリ内で `FileManager.replaceItemAt` を使う | 未検証 |
| ファイル監視は記述子ではなく親ディレクトリに張る。エディタは一時ファイル経由で保存する | 実測（Obsidian で確認。**日付と手順の記録なし**） |
| Xcode 26.3 以降には MCP サーバーがある（`xcrun mcpbridge`） | 未検証 |
| `MenuBarExtra` のラベルを毎秒更新しても安定する | **実測** — 2026-08-26、Debug ビルド、3時間のセッション進行中に CPU 0.1〜0.4%、RSS は約2.5分間で増加なし。**対象**: macOS 26 |
| 署名は無償の Personal Team。iPhone 実機のアプリは7日で失効する。Push 通知と iCloud は使えない | 未検証 |

**この表から1項目減った。** Live Activity の開始・更新は [0002](platform/0002-live-activity-background-start-and-suspend.md) で調べ、上の節へ移した。
**「例外は APNs のみ」は誤りだった。**

**`CONTEXT.md` §2 と §6 にも事実が混ざっている**（`isStale` の遅延、`MainActor.assumeIsolated`、
SF Symbol の実在検証、展開ダイナミックアイランドの `.center` など）。**軸 K で仕分ける。**
**洗い出しは `PUNCHLIST.md` の付録にある。**
