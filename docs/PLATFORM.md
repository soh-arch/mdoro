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

## Live Activity — データの上限とネットワーク

**調査**: [0004](platform/0004-live-activity-payload-size-and-network.md) / **確認日**: 2026-08-29 / **対象**: iOS 26 / iPhoneOS26.5.sdk

| 事実 | 確度 |
| :---- | :---- |
| **上限 4KB は静的（`ActivityAttributes`）と動的（`ContentState`）の合計に掛かる。** "can't exceed a **combined** size of 4 KB"。**プッシュ限定ではない** — "including data for **ActivityKit updates** and ActivityKit push notifications" と明記されている。測るのは **encoded**（シリアライズ後）の大きさ | 文書化 |
| `request(...)` が超過すると `ActivityAuthorizationError.attributesTooLarge` を throw し、開始しない | 文書化 |
| **`update` / `end` は `async` のみで `throws` を持たず、超過時の挙動はどの文書にも無い** | **不明** |
| `update` / `end` のリファレンスは「`state` **単体**が 4KB」と書き、概説記事の「**合計** 4KB」と**食い違う。両方が現行。安全側は合計** | 文書化（矛盾あり） |
| **Live Activity はネットワークにアクセスできない。** "Each Live Activity runs in its own **sandbox**, and — **unlike a widget** — it can't access the network or receive location updates" | 文書化 |
| **ウィジェット拡張のネットワークは可能であり、Apple が専用記事で手順を書いている**（インライン / バックグラウンド `URLSession`）。ただし "a request may not have enough time to complete before the system halts the widget extension" — **不可能ではなく、当てにできない** | 文書化 |
| `LiveActivityIntent.perform()` は**アプリ本体のプロセス**で走るため、この制約の対象外。**境界は表示面ではなくプロセスである** | 文書化 |
| **`com.apple.security.network.client` は macOS 専用**（対応プラットフォームは macOS 10.7 のみ）。**iOS に相当する entitlement は無く、この制約は entitlement で開けられない** | 文書化 |

**条文との食い違い**: REQ-UIX-025 は「**動的データ**が 4KB」と書くが、上限は静的との**合計**である。
REQ-UIX-026 の「不可能」「サンドボックス上」は Apple の原文どおりで**正しいが、主語が誤っている** —
**不可能なのは Live Activity であって、ウィジェット拡張ではない。**

**4KB が 4096 バイトか 4000 バイトかは分からない。** Apple は "4 KB" と "4KB" を混用し、
**バイト数を一度も示さない**（[0004](platform/0004-live-activity-payload-size-and-network.md)）。

---

## ローカルネットワークと、接続に要る設定

**調査**: [0005](platform/0005-local-network-privacy-and-platform-settings.md) / **確認日**: 2026-08-29 / **対象**: macOS 26.5.1（25F80）/ iOS 26 / Xcode 26.6

| 事実 | 確度 |
| :---- | :---- |
| **ATS は Network.framework に適用されない。** "ATS doesn't apply to calls your app makes to lower-level networking interfaces like the Network framework or CFNetwork"。**このアプリの通信経路に ATS は一度も掛からない**（REQ-PLT-002 が Network.framework を指定。`URLSession` の使用は0件）。**`NSAllowsLocalNetworking` は必須ではない** | 文書化 |
| iOS 17 / macOS 14 以降、ATS が IP 直結を既定で拒否するのは**事実**。ただし対処は `NSExceptionDomains` への**個別 IP と CIDR レンジ**の列挙であると Apple が明記している。**「DHCP では回避できない」は誤り** | 文書化 |
| **Bonjour の「登録」も許可を要する**（TN3179: Registering a service with Bonjour = **yes**）。一方「TCP を待ち受けて accept する」ことは許可を要しない（**no**）。**Mac が許可を要する理由は待ち受けではなく登録である** | 文書化 |
| **`NSBonjourServices` は iOS 限定ではない。** macOS 11.0+ に存在し、TN3179 は**登録側・探索側の双方に**要求する。`NSNetServices.h` は "NSBonjourServices and NSLocalNetworkUsageDescription are **required** in Info.plist"（`NSNetServicesMissingRequiredConfigurationError`、`macos(11.0)`）と明記 | 文書化（+ SDK ヘッダ） |
| ローカルネットワークプライバシーは **macOS 15 で導入**（iOS は 14）。macOS では `launchd` **デーモン**・root プロセス・Terminal / SSH 起動のコマンドラインツールが自動許可される。**GUI アプリと `launchd` エージェントは例外に入らない** | 文書化 |
| **許可状態を問い合わせる公開 API は存在しない。** "There's **no general API** that returns whether the current process has local network access (FB8711182)"。検出は `NWBrowser` の `kDNSServiceErr_PolicyDenied`（**-65570**）と `NWConnection` の `currentPath?.unsatisfiedReason == .localNetworkDenied`。**Apple がそのコード例を載せている** | 文書化 |
| `UnsatisfiedReason.localNetworkDenied` は macOS 11.0 / iOS 14.2 から。**iOS 26 / macOS 26 で新設も変更も非推奨も無い。** `-65570` に SDK ヘッダのコメントは無く、**意味づけの根拠は TN3179 のみ** | 文書化（SDK） |
| **バックグラウンドでの拒否は記録されない**（iOS）。フォアグラウンドで再試行すれば初回として提示される。**取り逃しは恒久ではない。** macOS に同じ条項は無い | 文書化 |
| **Bonjour（`mDNSResponder`）へのアクセスは `network.client` または `network.server` の どちらかで開く。** `network.client` を「Bonjour のため」とする理由は OS の判定と一致しない | **実測**（`/System/Library/Sandbox/Profiles/application.sb:759-762`） |
| security-scoped bookmark に**追加の entitlement は要らない**。`files.user-selected.read-write` があれば `com.apple.scopedbookmarksagent.xpc` が開く | **実測**（`application.sb:295-300`） |
| **シミュレータはローカルネットワークプライバシーを実装していない。実機でしか検証できない** | 文書化 |
| macOS では許可を未決定へ戻せない（FB14944392）。許可の同一性には Apple 発行の署名が要る（REQ-PLT-009） | 文書化 |
| `securityScopeAllowOnlyReadAccess` で読み取り専用のブックマークを作れる（REQ-PLT-003） | 文書化 |
| `network.client` を外して macOS 版が動くか | **不明**（未実測） |
| 設定漏れと許可拒否が同じエラーコードで返るか | **不明** |

**条文との食い違い**: REQ-PLT-001 の「いずれか1つでも欠けると接続が成立しない」は**導けない**
（8行中、接続の成立に効くのは**4行**）。**完全に正しいのは `NSLocalNetworkUsageDescription` の行だけである。**
**REQ-PLT-008 は正しい**（精確を期すなら「**公開 API としては**存在しない」）。

---

## SF Symbols — カタログの共通性と、可用性の軸

**調査**: [0006](platform/0006-sf-symbols-catalog-and-availability.md) / **確認日**: 2026-08-29 / **対象**: macOS 26.5.1（25F80）/ iOS 26.5（23F77・シミュレータランタイム）/ SF Symbols 8 beta

| 事実 | 確度 |
| :---- | :---- |
| **カタログは macOS 26.5 と iOS 26.5 で同一。** `CoreGlyphs.bundle` のメタデータ10ファイルが SHA-256 で一致（各 **9,184名**）。`Assets.car` はサイズが違うが**グリフ名集合は同一**（各 8,305名）。差は倍率と描画バリアントの数 | **実測** |
| **可用性はプラットフォーム別ではなくバージョン別である。** `name_availability.plist` はシンボル1件につき「年」を1つだけ持ち、`year_to_release` が年を全 OS のバージョンへ一括で対応づける。**シンボル単位でプラットフォームを分ける欄が存在しない** | **実測** |
| HIG は可用性を**バージョンの問題**として書く。"Availability of individual symbols … varies based on the version of the system you're targeting" / "Platform considerations — **No additional considerations** for iOS, iPadOS, macOS, tvOS, visionOS, or watchOS" | 文書化 |
| **`systemSymbolName:` が引くのは「動いている OS のカタログ」であって普遍のカタログではない**（ヘッダ: "A name from **the system's** SF Symbols catalog"）。**macOS 26.5 で非 `nil` でも、26.0 の端末では `nil` になりうる。導入年 2025.1（＝26.1）のシンボルが 29件実在する** | **実測** |
| **`largecircle.fill.circle` は実体を持たないエイリアス**（→ `inset.filled.circle`）。`Assets.car` にグリフを持たない。エイリアス表は両 OS で一致するので動作は同じ | **実測** |
| **`iphone.gen3` / `iphone.gen3.slash` は使用制限付きシンボル。** "may not be modified and **may only be used to refer to Apple's iPhone**"。**Mdoro の用法は適合している**（接続先の iPhone を指しているため） | 文書化 |
| **SF Symbols アプリのカタログは稼働 OS の超集合。** 8 beta は 9,476名で、macOS 26.5 の 9,184名＋**次期 OS（2026 ＝ 27 系）の 292名**。**アプリに載っているだけでは 26 系で使える根拠にならない** | **実測** |
| 可用性を実行せずに確かめるなら `/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/name_availability.plist` を読む。iOS 側はマウント済みのシミュレータランタイム内の同じバンドル（**起動は不要**） | **実測** |
| **「カタログは常に共通である」と明言した Apple の一次情報** | **見つからなかった。** 含意はあるが断定ではない。**共通性は観測された不変条件であって、文書化された保証ではない** |

**条文・コードとの関係**: 「カタログは両プラットフォームで共通」は**真だが、`SymbolNameTests` が必要としている保証ではない。**
**実在の検査で効く軸はプラットフォームではなく OS バージョン**であり、
`symbolExists` は**検査ホストのカタログしか見られないため、この軸を構造的に観測できない**
（[0006](platform/0006-sf-symbols-catalog-and-availability.md)）。

---

## 原子的な差し替え（ファイル）

**調査**: [0007](platform/0007-atomic-replacement-is-a-volume-constraint.md) / **確認日**: 2026-08-29 / **対象**: macOS 26.5.1（25F80）/ macOS 26.5 SDK

| 事実 | 確度 |
| :---- | :---- |
| **制約は「同一ボリューム」であって「同一ディレクトリ」ではない。** `rename(2)` は同一ファイルシステム内でのみ成立し（`man 2 rename`: "must reside on the **same file system**" / `EXDEV`）、**ディレクトリ関係を見る記述は無い** | 文書化 |
| `FileManager.replaceItemAt` は "works only when the … parameters are located on the **same volume**" と明記する | 文書化 |
| **Apple の第一推奨は OS の一時ディレクトリ。同一ディレクトリは「一時ディレクトリが使えないとき」の次善策**（`NSFileManager.h:290` に同文） | 文書化 |
| `url(for:in:appropriateFor:create:)` の `appropriateFor` は **"Only the volume of this parameter is used."** — **API 自体がボリューム単位で設計されており、ディレクトリを見ていない** | 文書化 |
| **App Sandbox はこの制約に関与しない。** 基底プロファイル `/System/Library/Sandbox/Profiles/application.sb` に `rename` の規則も、ソースと宛先のディレクトリ関係を見る規則も**存在しない**。サンドボックスは両端のパスを**独立に**評価する | 文書化（**ただし Apple は同ファイルを「私的インタフェース」と宣言している**） |
| 同プロファイル `:812-813` は、**全マウントポイント直下の `.TemporaryItems/` への読み書きを全アプリに許している** — `itemReplacementDirectory` の置き場所であり、**別階層からの差し替えを OS 側が支えている** | 文書化（同上） |
| **`/private/tmp` とユーザーのホームは同一 device id**（APFS の firmlink。実測 `16777234`）。**`/tmp` 経由が失敗するのは `EXDEV` ではない** | **実測** |
| `/tmp` への書き込みが拒否されるのは**サンドボックスのパス規則**による（`system.sb:84-88` は `read-metadata` と `test-existence` しか与えない）。**失敗するのは `rename` ではなく `open` / `write` の段階** | 文書化 |
| security-scoped bookmark をディレクトリに対して発行すると、**そのサブツリー全体**を覆う（"recursively in nested folders"） | 文書化 |
| `replaceItemAt` が実際に呼ぶシステムコール | **不明**（逆アセンブルしていない） |
| 外付けボリューム / SMB 上で `itemReplacementDirectory` が実際に成功するか | **不明**（未実測） |

**条文・コードとの食い違い**: REQ-PLT-004 の「サンドボックス外を跨ぐ `rename` は失敗する」も、
`LogWriter.swift` / `FileStateStore.swift` の「ディレクトリを跨げば失敗する」も**誤り。**
**REQ-LOG-004 も同じ前提の上に立っている**（[0007](platform/0007-atomic-replacement-is-a-volume-constraint.md)）。

---

## 型に収まらない数は `DecodingError` ではない

**調査**: [0012](platform/0012-a-number-the-type-cannot-hold-is-not-a-decoding-error.md) / **確認日**: 2026-09-03 / **対象**: Foundation の `JSONDecoder`（Swift 6.3 / macOS 26）

| 事実 | 確度 |
| :---- | :---- |
| JSON の数が Swift の型に収まらないとき、**ネストした復号の catch に届くのは `JSONError` であって `DecodingError` ではない**。`catch let error as DecodingError` は素通りする | 実測（最小再現あり） |
| **外から見ると `dataCorrupted` に見える** —— `JSONDecoder.decode` が最後に包むため。スタックの一番外で型を見て分岐を推定すると読み違える | 実測 |
| 列挙型に無い raw 値は `DecodingError.dataCorrupted`、型違いは `typeMismatch`。**これらは catch に届く** | 実測 |

**依拠する条文**: REQ-PRT-005。**この線引きを `DecodingError` の型だけで表現すると、型に収まらない数はその線の外に落ちる。**
**このリポジトリの実装は、もうその線を error の型だけでは引いていない**（2026-09-03 の是正）—— 残り半分は JSON の文法の走査が負っており、**型に収まらない数は破棄されず `settingOutOfRange` が返る。**
**それでもこの事実は条文の射程の内側にある**（半分がこのとおりに振る舞うことを前提に、残り半分が組まれている）。**詳細は記録の末尾。**
**同じ場所で2回読み違えた**（検証役が外側の型を見て誤り、実装役が実経路で覆した）。

---

## LaunchServices は plist の多重起動禁止をテストホストにも強制する

**調査**: [0011](platform/0011-launchservices-enforces-the-plist-on-the-test-host.md) / **確認日**: 2026-09-02 / **対象**: macOS 26 / Xcode 26

| 事実 | 確度 |
| :---- | :---- |
| `LSMultipleInstancesProhibited` は、同じ bundle id のテストホスト起動にも適用される —— 本物のアプリが起動中の機体でスイート全体が死ぬ | 実測 |

**条文・コードとの食い違い**: 無し（POL-116 が plist 層を不採用にした根拠）。

---

## 広告する側は、拒否を知らされない

**調査**: [0010](platform/0010-the-advertiser-is-not-told-no.md) / **確認日**: 2026-09-02 / **対象**: macOS 26（TN3179 現行版 / 26.5 SDK）

| 事実 | 確度 |
| :---- | :---- |
| `NWListener` は許可拒否を API に表出しない（登録側の検出経路は文書上存在しない） | 文書化（不在） |
| 許可状態を問い合わせる API は無い —— macOS 15+ を対象に含む明文（FB8711182） | 文書化 |
| 唯一の文書化された検出は self-browse。ただし macOS 実機では未実測 | 文書化／未検証 |

**条文・コードとの食い違い**: 無し（POL-164 の対処方針の根拠。裁定: 常設の案内文言で補い、self-browse は実機実証できたら）。

---

## サービス登録の更新通知と、ローカルネットワーク許可の効く時点

**調査**: [0009](platform/0009-what-the-owners-field-test-showed.md) / **確認日**: 2026-09-02 / **対象**: macOS 26 / iOS 26（所有者の実機・1回の観察）

| 事実 | 確度 |
| :---- | :---- |
| `serviceRegistrationUpdateHandler` は、衝突改名の際に実際に呼ばれる（改名案内の表示で確認） | 実測 |
| ローカルネットワーク許可の OFF は、既に立っている登録・接続には即座に効かない | 実測 |
| 許可 OFF 状態での新規の広告は、**アプリにエラーが渡らないまま**不可視になる（bind は成功する） | 実測 |

**条文・コードとの食い違い**: 3行目により、Mac は「広告できていない」ことを検出も表示もできていない
（POL-164。REQ-ERR-008 / Decision 0035 の「失敗には届き先が要る」に反する）。

---

## Bonjour の同名衝突と番号

**調査**: [0008](platform/0008-what-three-tests-rest-on.md) / **確認日**: 2026-08-29 / **対象**: macOS 26.5.1 / mDNSResponder-2881.120.11

| 事実 | 確度 |
| :---- | :---- |
| **番号を付けるのは mDNSResponder であり、`NWListener` ではない。** auto-rename は既定で有効（`dns_sd.h` の `kDNSServiceFlagsNoAutoRename` / `advertise_descriptor.h`「**Auto-rename is enabled by default**」） | 文書化 |
| 形式は `" (2)"`。2〜9 は +1、**10 以降は `+1 + 乱数(0..98)` で連番にならない** | Apple 公開ソース（`mDNSCore/DNSCommon.c`） |
| **登録プロセスを SIGKILL しても、約1.7秒で登録は撤去される**（UDS 接続断で goodbye が出る） | **実測** |
| **`Name (2)` は番号を返上しない。** 先に登録した側が消えても `(2)` のままで、**後から起動した登録が空いた `Name` を取る** | **実測** |
| **番号の若さと登録の新旧に、文書化された関係は無い。「古いほうが番号が小さい」は成り立たない** | **実測で反証** |
| **Mac は自分が何という名前で登録されたかを知らない**（`serviceRegistrationUpdateHandler` を使っていない）。TXT は `ws` と `v` だけで、**インスタンスを一意に指す値が電波に乗っていない** | 実測（実装） |
| LAN 越し（`NWBrowser`）でのキャッシュ残存時間。Wi-Fi 断・スリープ・電源断では goodbye が出ず TTL まで残りうる | **不明**（測っていない） |

**コードとの食い違い**: `DiscoveredServer.deduplicated` は「古いほうが番号が小さい」に乗っており、
**最大番号を残す規則が最新を捨てうる**（POL-110）。

---

## テスト実行の検出と String Catalog

**調査**: [0008](platform/0008-what-three-tests-rest-on.md) / **確認日**: 2026-08-29 / **対象**: Xcode 26.6

| 事実 | 確度 |
| :---- | :---- |
| **`@testable import` が要求するのは `ENABLE_TESTABILITY`（`-enable-testing`）であって `BUNDLE_LOADER` ではない。** `BUNDLE_LOADER` が要るのは**取り込む先が App モジュールだから**（`man ld` の `-bundle_loader`）。**App のシンボルを要さないバンドルは `xctest` CLI にホストさせられる**（`man 5 xcodebuild.xctestrun`） | 文書化 |
| **`XCTestConfigurationFilePath` を設定するのは XCTest ではなく起動側**（Xcode 26.6 では `DVTFoundation` / `IDEFoundation` / `XCTHarness` が書く）。**Apple の文書には一切記載が無い** | 実測（バイナリ走査） |
| **`XCTestCore` の `loadTestConfiguration` は `XCTestConfigurationEncodedValueEnvironmentKey` を先に試す。** `XCTestConfigurationFilePath` は**2番手** | 実測（逆アセンブル） |
| Swift Testing だけのターゲットでも `.xctest` バンドルとして同じ経路で起動されるため設定される。**Swift Testing は XCTestCore の上で駆動されている** | 実測 |
| **ビルドのタスクグラフはソースの `.xcstrings` を出力に持たない**（マニフェスト全217コマンドで0件。`xcstringstool` は `compile` と `generate-symbols` のみ） | 実測 |
| **書き戻しは「エディタだけ」ではない。** Apple は「**Each time you build your project, Xcode updates your string catalogs**」と明記し、実装は**ビルドの外の IDE プラグイン** `IDEXCStringsSupportCore` にある。公開 CLI `xcstringstool sync` も書ける | 文書化 |
| 参照はキーへ落ちる。**ただし `NSShowNonLocalizedStrings` が true のときはキーを大文字化して返す** | 文書化 |
| 補間は型で指定子になる（`Int` → `%lld`、`String` → `%@`） | 文書化 ＋ 実測 |

**支えの細さ**: `TestHost.isRunning` は**未文書の環境変数1本**に乗っており、しかも**優先順位では2番手**。
**Xcode が encoded value 経路に切り替えたら、検出は黙って `false` を返してガードが開く。**
**それを捕まえる app-hosted のテストは、2026-09-12 から CI で走る**（POL-225。`TestHostDetectionTests` は `MdoroMacTests` にあり、`mac` ジョブが走らせる48本に入っている）。**この節が「CI で走らない」と書いていた期間の記録として、支えの細さ自体は変わらない** —— 検出が黙って `false` を返せばガードは開く。**変わったのは、それに気づく機械があることである。**

---

## OS の更新の後、外れていた署名の信頼と、生き残ったペアリング

**調査**: [0013](platform/0013-the-trust-was-gone-after-an-os-update.md) / **確認日**: 2026-09-05 / **対象**: macOS 26.5.1 / **iOS 26.6.1** / Xcode 26.6（所有者の実機・1回の観察）

| 事実 | 確度 |
| :---- | :---- |
| **塞いでいたのは Personal Team 署名の開発者信頼が無い状態。** 設定 > 一般 > VPN とデバイス管理で信頼し直すまで、アプリは起動せず**再ビルドも通らない**（＝**既知の7日失効ではない**。それなら再ビルドで直る） | **実測** |
| **その信頼を外したのが OS の更新そのものかは切り分けていない。** 観察されたのは**更新直後に起きたという時間的な一致**であって機構ではない。更新と無関係な時間経過型の失効が重なった可能性を排除できていない | **不明** |
| **症状が原因を指さない。** 先に出るのは起動失敗とビルド失敗で、「Developer が認証されていない」旨の案内は**数回の試行と数分の後**に出た。**遅れの原因は切り分けていない** | **実測**（文言は**不明**） |
| **Xcode 26.6 は iOS 26.6.1 の実機へ降ろせる。** 信頼さえ戻れば device support は足りている | **実測** |
| **ローカルネットワーク許可は OS の更新をまたいで生存する。** 再許可のダイアログは出なかった | **実測** |
| **ペアリングも生存する。** 再信頼後、iPhone は**操作なしで** Mac へ自動的に接続した —— Keychain のトークン・Mac 側の `issuedDeviceTokens`・Bonjour の発見が同時に成立していた（**Mac 側が更新中ずっと起動していたかは不明**。所有者は「意識して記憶していない」と述べている） | **実測** |
| **Live Activity のロック画面表示とセッション終了通知は、更新後も機能する** | **実測** |
| メジャー更新でも同じか / 有償の Developer Program でも同じか | **不明**（26.6 → 26.6.1 の1例、Personal Team のみ） |

**文書との食い違い（POL-199 / POL-205 で解消）**: `README.md` と `docs/DEVELOPMENT.md` は
**7日失効しか書いていなかった。** **症状が原因を指さないぶん、読者は原因に辿り着けない。**
いまは**3つ**に、症状から入る再信頼の手順がある —— `README.md`（利用者）/
`AGENTS.md`（貢献者のエージェント）/ `docs/DEVELOPMENT.md`（保守する側）。

---

## 未検証（軸 K で確認する）

**`CONTEXT.md` §3 から移した項目である。**
**「一次情報で確認済み」と書かれていたが、9項目のうち出典が残っていたのは1つだけだった。**
調査を当てるまで `未検証` とする。**これらを根拠に新しい条文を書かない。**

| 事実として書かれていたこと | 確度 |
| :---- | :---- |
| **エディタは保存時に一時ファイル経由で置き換える**（記述子ではなく親ディレクトリを監視する、は**これへの対処**であって事実ではない） | 実測（Obsidian で確認。**日付と手順の記録なし**） |
| `MenuBarExtra` のラベルを毎秒更新しても安定する | **実測** — 2026-08-26、Debug ビルド、3時間のセッション進行中に CPU 0.1〜0.4%、RSS は約2.5分間で増加なし。**対象**: macOS 26 |
| 署名は無償の Personal Team。iPhone 実機のアプリは7日で失効する。Push 通知と iCloud は使えない | 未検証 |

**この表から3項目を外した**（2026-08-29・POL-069）。

| 外したもの | 理由 |
| :---- | :---- |
| 「iPhone の通知を WebSocket に依存させず、絶対時刻で事前スケジュールする」 | **設計判断である**（REQ-NTF-002 そのもの）。事実の部分は「suspend 中はコードが実行されない」で、**上の節に出典つきで載っている** |
| 「`FileManager.replaceItemAt` を使う」「親ディレクトリに張る」 | **手段の選択である。** 事実の部分だけを残した |
| 「Xcode 26.3 以降には MCP サーバーがある」 | **どの条文もこれに依拠していない。** この文書は「**条文が依拠する事実の索引**」であり、開発環境の覚書を置く場所ではない |

**当初の9項目のうち、5項目は調査して上の節へ移した**（Live Activity の開始・更新 / ATS とローカルネットワーク許可の2件）。
**「例外は APNs のみ」も「`NSAllowsLocalNetworking` は必須」も誤りだった。**

**`CONTEXT.md` §2 と §6 にも事実が混ざっている**（`isStale` の遅延、`MainActor.assumeIsolated`、
SF Symbol の実在検証、展開ダイナミックアイランドの `.center` など）。**軸 K で仕分ける。**
**洗い出しは `PUNCHLIST.md` の付録にある。**
