# PUNCHLIST — 公開前に潰すことの一覧

**このファイルが作業キューの正本である。** ここに無い作業を始めない。

監査役（`.claude/agents/spec-auditor.md` / `repo-auditor.md`）が列挙し、
**起票はオーケストレーターだけが行う。** 監査役は直接書き込まない。
採否を決めるのは人間である。

経緯は書かない。決定の背景は `docs/decisions/`、現在の方針は `docs/CONTEXT.md`。

---

## 記法

| 欄 | 内容 |
| :---- | :---- |
| **ID** | `POL-nnn`。連番。**欠番を作らない**（却下したものも残す） |
| **症状** | 一行。何が起きるか。原因ではなく現象 |
| **根拠** | 要件ID / `CONTEXT` の項 / Decision Record 番号 |
| **軸** | A〜J |
| **レーン** | `agent`（コードだけで直る） / `human`（実機確認・Xcode 操作・判断が要る） |
| **重大度** | `blocker` / `major` / `minor` |
| **状態** | `open` → `doing` → `review` → `done` / `rejected` / `deferred`。人間の採否だけが済んで着手前のものは **`決定済み`**（決定の内容は下の「決定済みの方針」表） |
| **PR** | ブランチ名か PR 番号 |

**却下と先送りには理由を1行残す。** 理由のない close をしない。
実証研究では、エージェントの PR の却下のうち **33.1% が理由を観測できない沈黙の close** だった。
何を採らないと決めたかは、採ると決めたことと同じだけ残す価値がある。

## 軸

| 軸 | 内容 | 監査役 |
| :-- | :---- | :---- |
| **A** | 名称（`Mdoro` への改名の取り残し） | 両方 |
| **B** | 立ち位置（Markdown-first。Obsidian を前提にしない） | spec-auditor |
| **C** | 言語（アプリの文字列・識別子・コメントを英語へ） | 両方 |
| **D** | 利用者像（個人用途の語彙と、それを根拠にした結論） | spec-auditor |
| **E** | ファイル書き換え動作と README の誠実さ | repo-auditor |
| **F** | コメント規律（グローバル `CLAUDE.md`）。**軸 C の英語化の後に回す** | repo-auditor |
| **G** | 決定の反映漏れ。**最後に回す** | 両方 |
| **H** | 他人の環境でビルドできるか | repo-auditor |
| **I** | 私生活の写り込み（画像・履歴・パス） | repo-auditor |
| **J** | ライセンスと第三者素材の出所 | repo-auditor |
| **K** | **条文が依拠しているプラットフォームの事実。** 仕様書と `CONTEXT.md` が主張している Apple / Xcode の仕様を洗い出し、**一次情報で確認されたもの・実測されたもの・確認されていないもの**に分ける | `platform-researcher` |
| **—** | 軸に紐づかないが根拠のある指摘（監査の途中で見つかったもの） | 両方 |

---

## 進行中・未着手

**2026-08-28 の監査の結果を起票。** 重大度順。
**POL-001〜023 は工程13b（`spec-auditor`、軸 A / B / C / D）**、
**POL-024〜032 は工程14b の先行分（`repo-auditor`、軸 A / C）**。
軸 E / F / H / I / J は工程14b の残りとして実施する。

| ID | 症状 | 根拠 | 軸 | レーン | 重大度 | 状態 | PR |
| :-- | :---- | :---- | :-- | :---- | :---- | :---- | :-- |
| **POL-010** | 条文が日本語の UI 文言そのものを規定している箇所が **19件**。REQ-UIX-038（MUST）と正面衝突 | REQ-UIX-038 / [0022](decisions/0022-english-only-ui.md) | C | human | blocker | done | `docs/spec-v2.10` |
| **POL-011** | 10.3 の `notificationSound`（`chime` / `bell` / `wood`）は**コードの raw 値と一致しており、条文は誤っていない**（2026-08-28、repo-auditor が確認）。欠けているのは**表示名の対応表**。UI は `Glass` / `Submarine` / `Pop` を出すが、条文にその対応がない | 0.12節 / REQ-NTF-006 / [0017](decisions/0017-system-notification-sounds.md) / `Preset.swift:6-32` | C | human | major | done | `docs/spec-v2.10` |
| **POL-001** | 表題が「システム要件定義・仕様書：**ポモドーロタイマー**」。公開リポジトリで最初に読まれる1行が旧名 | [0021](decisions/0021-published-as-oss-named-mdoro.md) / [0024](decisions/0024-rename-everything-to-mdoro.md) | A | agent | major | done | `docs/spec-v2.10` |
| **POL-002** | 1.1「目的」が製品を「ポモドーロタイマー」と定義。**同じ節の2行下で 0021 を引きながら、0021 が避けると決めた語で自分を名乗っている** | [0021](decisions/0021-published-as-oss-named-mdoro.md) | A | agent | major | done | `docs/spec-v2.10` |
| **POL-006** | 9.4 の背景が置き場所を **`Vault`** と呼ぶ。Obsidian の固有名詞。9.3 は `taskFilePath` / `logFolderPath` を持つだけで Vault という単位は存在しない | [0023](decisions/0023-markdown-first-not-obsidian-first.md) / 9.3 | B | agent | major | done | `docs/spec-v2.10` |
| **POL-012** | 既定プリセット名「標準」が条文本体に **11件**。7.2 のログ例だけ `[Standard]`。**同じ仕様書に既定プリセット名が2つある** | 0.12節 / [0022](decisions/0022-english-only-ui.md) | C | agent | major | done | `docs/spec-v2.10` |
| **POL-013** | 工程10 で確定した語 9件のうち、**条文から引けるのは2件だけ**。残りは改訂履歴 0.12 にしかない | [decisions/README.md](decisions/README.md)「反映」 | C | human | major | done | `docs/spec-v2.10` |
| **POL-014** | Info.plist の usage description の言語がどの条文にも規定されていない。**利用者が最初に読むアプリの文章**なのに REQ-UIX-038 の列挙に含まれない | REQ-UIX-038 / REQ-PLT-001 | C | agent | major | done | `docs/spec-v2.10` |
| **POL-016** | 1.1 の背景が「**個人開発**かつローカル環境での運用に特化」。同期競合を排除しているのは開発体制ではなく [0001](decisions/0001-mac-as-single-source-of-truth.md) | [0021](decisions/0021-published-as-oss-named-mdoro.md) / [0001](decisions/0001-mac-as-single-source-of-truth.md) | D | human | major | done | `docs/spec-v2.10` |
| **POL-017** | 第14章の背景が「**個人利用**における」。「作者1人」とも「1人の利用者の2端末」とも読める | [0021](decisions/0021-published-as-oss-named-mdoro.md) / REQ-NFR-008 | D | human | major | done | `docs/spec-v2.10` |
| **POL-018** | 1.3 の配布欄が「**TestFlight 配布を想定**」のまま。0021 は「ソースからのビルドのみ」と確定済み。OPEN-021 も未決のまま残っている | [0021](decisions/0021-published-as-oss-named-mdoro.md) | D | human | major | done | `docs/spec-v2.10` |
| **POL-019** | 第14章が Time Sensitive 通知を「利用できない**可能性がある**」。REQ-NTF-005 は「成立しない」と実機確認済み。**配布がソースのみである以上、全利用者が該当する** | REQ-NTF-005 / [0021](decisions/0021-published-as-oss-named-mdoro.md) | D | agent | major | done | `docs/spec-v2.10` |
| **POL-020** | **パス未設定のまま使い始めた状態の条文がない。** 既定値は「未設定」で全利用者がそこから始まるが、条文は「一度設定した後」を前提にしている。未設定のまま確定に至ったときキューに積むかが引けない | REQ-ERR-001 / REQ-LOG-002 / REQ-LOG-005 / 9.3 | D | human | major | done | `docs/spec-v2.10` |
| **POL-003** | 3.1 の背景が作業1本を「ポモドーロ」と呼ぶ。他所はすべて「セッション」。用語集にない語 | 第16章 / 4.1 | A | agent | minor | done | `docs/spec-v2.10` |
| **POL-004** | 4.7 が「ポモドーロ手法」、7.3 が「集中と休憩を繰り返す手法」。**同じ技法の呼び方が2つ。違反ではないので残す判断も成立する** | 7.3 の既存表現 | A | human | minor | done | `docs/spec-v2.10` |
| **POL-005** | `CONTEXT.md` §1 の原則が `PomodoroLog.md` のまま。SPEC は `MdoroLog.md` に統一済み | [0024](decisions/0024-rename-everything-to-mdoro.md) | A | agent | minor | done | `docs/spec-v2.10` |
| **POL-007** | REQ-TSK-015 が `[[...]]` と `#tag` を「Markdown 記法」と総称。REQ-LOG-013 は「Obsidian / Logseq **などが解釈する**」と書き分けている | REQ-LOG-013 / [0023](decisions/0023-markdown-first-not-obsidian-first.md) | B | agent | minor | done | `docs/spec-v2.10` |
| **POL-008** | OPEN-018 の題が「**Obsidian 以外の**ツール固有記法」。Obsidian を基準点に置いている | [0023](decisions/0023-markdown-first-not-obsidian-first.md) / [0025](decisions/0025-standard-checkbox-syntax-only.md) | B | agent | minor | done | `docs/spec-v2.10` |
| **POL-009** | REQ-LOG-015（Dataview / Tasks 形式での出力、MAY・見送り）が **Obsidian のプラグイン名を条文に持ったまま公開される**。監査役は「見送り済みは挙げない」規則により除外し、人間の判断に委ねた | [0023](decisions/0023-markdown-first-not-obsidian-first.md) / `CONTEXT.md` §6 | B | human | minor | done | `docs/spec-v2.10` |
| **POL-024** | **ローカルネットワーク許可のダイアログ本文が日本語。** `INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Mac と iPhone を接続するために使用します"` が4構成すべてに。**利用者が最初に見る文字列**。POL-014 の実物 | REQ-UIX-038 / [0022](decisions/0022-english-only-ui.md) | C | **human**（Xcode。[0013](decisions/0013-pbxproj-is-owned-by-xcode.md)） | blocker | done | #5 |
| **POL-027** | **`LogTests` の3アサーションが常に真で、何も検証していない。** `contains("周回")` を見ているが `LogFormatter` は `Loop` しか出さない。REQ-LOG-011（周回は WORK の正常完了行のみ）が**テストで守られていない** | REQ-LOG-011 / `LogTests.swift:77-79` | — | agent | major | done | #6 |
| **POL-025** | プリセット表示に**全角括弧**（U+FF08 / U+FF09）。`Standard（25 / 5 / 15）` と出る。コード7箇所＋カタログ4行。**アプリ内で唯一残った CJK 文字** | REQ-UIX-038 | C | agent | major | done | `fix/remaining-english-strings` |
| **POL-026** | **テストの `@Suite` 表示名43件が全件日本語**、`#expect` の失敗メッセージ85件以上も日本語。CI 出力と貢献者の `swift test` が日本語になる。**コメントではないので工程14a では拾われない** | [0032](decisions/0032-code-comments-are-english.md) | C | agent | major | done | #7 |
| **POL-028** | OS 由来の `error.localizedDescription` が画面と診断ログへそのまま流れる。日本語環境の Mac では日本語で返る。`String(describing:)` の生の enum 表記も画面に出る。**`why` にパスが混入する経路の疑いあり**（軸 E / I と重なる） | REQ-UIX-038 / [0018](decisions/0018-diagnostic-log-policy.md) | C | agent | major | done | `fix/error-codes-not-messages` |
| **POL-029** | アプリの文言40件以上が **String Catalog を経由していない**（Mac の通知本文が素のリテラル、iOS は `String(localized:)`）。表示言語は英語なので REQ-UIX-038 は破れていないが、**[0022](decisions/0022-english-only-ui.md) の設計意図（文言を1箇所に集める）が破れている** | [0022](decisions/0022-english-only-ui.md) | C | agent | minor | done | `fix/catalog-and-wire-prose` |
| **POL-030** | 診断ログは `sound=chime`、UI は `Glass`。**対応表は日本語の [0017](decisions/0017-system-notification-sounds.md) にしかなく、issue を読む第三者に同じものと分からない** | [0018](decisions/0018-diagnostic-log-policy.md) / [0017](decisions/0017-system-notification-sounds.md) | C | agent | minor | done | `fix/remaining-english-strings` |
| **POL-031** | `Tools/make_icon.swift:186` の `print` に日本語が1行。同ファイルの他の `print` は全て英語 | [0032](decisions/0032-code-comments-are-english.md) | C | agent | minor | done | `fix/remaining-english-strings` |
| **POL-032** | 作者のチーム ID `DEVELOPMENT_TEAM` が `project.pbxproj` に6箇所コミットされている。貢献者は毎回ローカルで書き換え、その差分を PR に含めない注意が要る | [0013](decisions/0013-pbxproj-is-owned-by-xcode.md) | H | **human**（Xcode） | minor | done | `fix/catalog-and-wire-prose` |
| **POL-033** | [0033](decisions/0033-unset-log-path-records-nothing.md) が `committedAt` の扱いを書いていなかった。立てないと復帰時に REQ-PER-003(d) へ落ち、**記録先が無いのに確認を求める** | REQ-PER-003 / REQ-LOG-019 / 第16章 | — | agent | blocker | done | `docs/audit-followup` |
| **POL-034** | **Mac 側の診断ログにテストがない。** `AppModel` の `notify.test` / `notify.finished` が `rawValue` へ戻っても `swift test` は落ちない（`MdoroCore` 内の呼び出し口しか押さえていない）。`MdoroMacTests` に診断ログの検証が1件も無い | [0018](decisions/0018-diagnostic-log-policy.md) / REQ-ERR-010 | — | agent | minor | done | `fix/audit-leftovers` |
| **POL-038** | **`StateStoreError` がどの画面にも届かない。** `AppModel.init` は `try? store.loadAndRestore`、`persist()` は `try? store.save`。**保存状態が壊れていても書けなくても、利用者には何も出ない。**「失敗を黙らせない」に対する握り潰し | `CONTEXT.md` §2 / REQ-PER-001 | — | **human**（何をどう出すか） | major | done | `fix/failures-that-reach-someone` |
| **POL-035** | 診断ログ自身の書き込み失敗が原文のまま画面へ（`DiagnosticLogFile.swift:38` → `SettingsView.swift:128`）。**ログに書けない失敗のコードは、ログに書けない。** 画面に出すか捨てるかの判断が要る | [0034](decisions/0034-os-errors-are-recorded-as-codes.md) / REQ-ERR-010 | — | **human** | major | done | `fix/failures-that-reach-someone` |
| **POL-037** | **同じ穴が iPhone 側にも空いている。** `LiveActivityController.swift:177` の `diagnostic = "Could not start: \(String(describing: error))"` が `ClientModel.liveActivityProblem` 経由で画面へ。`CONTEXT.md` §2「片方のプラットフォームで踏んだ穴は、もう片方も見に行く」 | [0034](decisions/0034-os-errors-are-recorded-as-codes.md) / `CONTEXT.md` §2 | — | agent | major | done | `fix/failures-that-reach-someone` |
| **POL-036** | 診断ログの書き出し先への保存失敗が原文のまま画面へ（`SettingsView.swift:148`） | [0034](decisions/0034-os-errors-are-recorded-as-codes.md) | — | agent | minor | done | `fix/failures-that-reach-someone` |
| **POL-039** | `ProtocolErrorPayload(message:)` が列挙の生表記（`invalidStateForAction` 等）を iPhone へ送る。OS 由来ではないので今回の漏れには当たらないが、**人向けの文ではない**（`AppModel.swift:515, 522`） | [0034](decisions/0034-os-errors-are-recorded-as-codes.md) / REQ-UIX-038 | — | **human** | minor | done | `fix/failures-that-reach-someone` |
| **POL-040** | **集中表示ビューでは拒否が見えない。** `fullScreenCover` なので `MainScreen` のオーバーレイが隠れる。REQ-UIX-010 が副次情報を4種に限定しており、行を足すと条文に触れる | REQ-UIX-010 / REQ-ERR-016 | — | **human** | major | 決定済み | `docs/audit-leftovers` |
| **POL-044** | **メニューバー常駐なので、起動時にウィンドウが閉じていると復元失敗の帯がその場では見えない。** 閉じるまで残るので「1度示す」は満たすが、通知にするかは条文にない | REQ-ERR-017 / [0035](decisions/0035-a-failure-needs-somewhere-to-arrive.md) | — | **human** | minor | 決定済み | `docs/audit-leftovers` |
| **POL-041** | **ビューに色リテラルが残っている。** `.red` が `SettingsView:96`、`PresetEditorView`（4箇所）、`PairingView:38`。`CLAUDE.md`「色リテラルをビューに書かない」 | `CLAUDE.md` / [0007](decisions/0007-oklch-color-system.md) / REQ-COL-001 | — | agent | minor | done | `fix/audit-leftovers` |
| **POL-043** | Live Activity の開始失敗のコードを捨てている（iOS に診断ログが無いため）。**[0035](decisions/0035-a-failure-needs-somewhere-to-arrive.md) の「画面にコードを出す唯一の場面」を2箇所に広げるか**の判断 | [0035](decisions/0035-a-failure-needs-somewhere-to-arrive.md) / [0018](decisions/0018-diagnostic-log-policy.md) | — | **human** | minor | rejected | — |
| **POL-042** | `ProtocolErrorPayload(message:)` の2箇所が `String(describing:)` のまま（`AppModel.swift`）。漏洩ではないが、[0034](decisions/0034-os-errors-are-recorded-as-codes.md) の「自前のエラーも同じ形で出す」に沿うなら `diagnosticSummary` が筋。`CommandTranslation.Failure` の適合作業が要る | [0034](decisions/0034-os-errors-are-recorded-as-codes.md) | — | agent | minor | done | `fix/audit-leftovers` |
| **POL-045** | **2つの MUST が同じ場面で両立しない。** `.ioFailed` で保存が止まる間、REQ-LOG-005「キューを永続化すること」が成立しない。REQ-ERR-017（v2.15）は「画面に示して保存を止める」と明示しており、実装は条文どおり。**条文の側に調停がない** | REQ-LOG-005 / REQ-ERR-017 / [0036](decisions/0036-an-unreadable-state-file-is-set-aside.md) | — | **human** | major | 決定済み | `docs/audit-leftovers` |
| **POL-046** | `stateSaveProblem` が `persistBlockedBy` を含むことを守るテストが無い。**コードは正しいが、外しても242件すべて通過する。** 帯を閉じた後、保存が止まっていることが画面のどこにも残らなくなる | REQ-ERR-017 | — | agent | minor | done | #12 |
| **POL-047** | **`xcodebuild test` が本物の `MdoroMac.app` をテストホストとして起動する。** 起動したアプリは通常どおり通知を配信し、ウィンドウを前面に出し、Bonjour を広告し、**利用者の `Task.md` を監視する。** プロダクトオーナーが実際に「数秒おきに通知が飛び交う」「ウィンドウが急に最前面に来る」を観測（2026-08-28）。**貢献者が回すたびに、その人の通知・LAN・ファイルに触れる** | 3原則1 / [0002](decisions/0002-task-md-read-only.md) / `CONTEXT.md` §2 | — | **human**（`TEST_HOST` はビルド設定。[0013](decisions/0013-pbxproj-is-owned-by-xcode.md)） | major | done | `fix/final-audit-items` |
| **POL-048** | `AppModel.reject(...)` の3箇所が `message` に英文の散文を入れており（`"No stableId"` 等）、**このファイルで唯一 `case(domain:code)` でない送信経路**になった。POL-041 が問題にした「同じファイル内で不統一」と同じ形 | [0034](decisions/0034-os-errors-are-recorded-as-codes.md) / 10.2 | — | agent | minor | done | `fix/catalog-and-wire-prose` |
| **POL-049** | ビューに `.primary` / `.secondary` が約25箇所。**色相リテラルではなく OS の意味色**なので走査の対象外にしてある。`theme.textSecondary` へ寄せるかは**見た目が変わる判断** | [0007](decisions/0007-oklch-color-system.md) / REQ-COL-001 | — | **human** | minor | done | `fix/final-audit-items` |
| **POL-050** | `MdoroServer` の接続拒否6文言が**どの画面にも届いていない**（`MdoroClient` は `payload.code` しか読まない）。`AuthFailureCode` が `case(domain:code)` の形になっていないことが、残っている不整合 | [0034](decisions/0034-os-errors-are-recorded-as-codes.md) / 10.2 | — | agent | minor | done | `fix/final-audit-items` |
| **POL-051** | `taskList.parseError` は **Mac が書いた文を iPhone がそのまま表示する**（`ConnectionViews.swift:216`）。[0035](decisions/0035-a-failure-needs-somewhere-to-arrive.md) の「送る側が相手の画面の文言を決めない」と同じ構図だが、**条文は `error.message` にしか及んでいない** | [0035](decisions/0035-a-failure-needs-somewhere-to-arrive.md) / 10.2 | — | **human** | minor | deferred | — |
| **POL-052** | `TaskListView` の空状態の注記だけ Markdown が描画されない（`SettingsView` の同種の注記はコード体裁で出る）。揃えるなら `LocalizedStringKey` にするだけ | REQ-TSK-016 / REQ-UIX-047 | — | agent | minor | done | `fix/final-audit-items` |
| **POL-053** | **テストが本物の IOPM アサーションを取る。** `record()` でセッションを走らせると `IdleSleepGuard.begin()` が実機のスリープ抑止を掛ける。POL-047 と同じ「テストが利用者の環境に触る」類。通知と同じ継ぎ目に載せられる | `CONTEXT.md` §2 / POL-047 | — | agent | minor | done | `fix/three-that-touch-the-outside` |
| **POL-054** | **接続拒否が診断ログに残らない。** `MdoroServer` は `DiagnosticLog` を持たない。「ペアリングできない」という issue で、**5回間違えたのか、トークンが失効したのか、別端末が繋がっていたのかが読めない** | REQ-ERR-010 / [0018](decisions/0018-diagnostic-log-policy.md) | — | agent | minor | done | `fix/three-that-touch-the-outside` |
| **POL-055** | 空状態の注記の `##` だけコード体裁にならない（バッククォートで囲めば揃うが、カタログのキーが変わる） | REQ-TSK-016 | — | agent | minor | open | — |
| **POL-056** | 受け取る側が引く文言の出所が2種類（`ProtocolErrorCode.displayMessage` は `MdoroCore`、`AuthFailureCode` は `ConnectionViews` の `LocalizedStringKey`）。同じ 10.2 の役割なのに揃っていない | [0022](decisions/0022-english-only-ui.md) / 10.2 | — | agent | minor | open | — |
| **POL-057** | **REQ-UIX-027 が、確認されていないプラットフォームの事実を前提にしている。** 「背景が利用者の壁紙である」が事実か未確認のまま、固定値と半透明素材で組むことを MUST で要求している。**この条文は改訂履歴に一度も現れず、Live Activity の実装が2回書き直された後も突き合わされていない。** 同じ理由から引かれた REQ-COL-022（メニューバー）は「色を使わない」という別の答えに落ち着いている。**意匠の問題ではなく、条文が実態に則していない問題として扱う** | REQ-UIX-027 / REQ-COL-022 / `CONTEXT.md` §3 | — | **human** | major | done | `fix/final-audit-items` |
| **POL-058** | **軸 K の洗い出し。** 仕様書と `CONTEXT.md` §2 が主張しているプラットフォームの事実を列挙し、確度で分ける。**`PLATFORM.md` の `未検証` 8項目**（§3 から移送）も対象。条文が事実を抱えている箇所は `PLATFORM.md` への参照に置き換える。**結果は下の付録。81件のうち出典があったのは1件** | [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) | K | `platform-researcher` | major | done | `fix/final-audit-items` |
| **POL-059** | **訂正済みの前提をコードが引いている箇所が8件**（走査で判明。当初は1件と見ていた）。壁紙3件（`MdoroWidgetLiveActivity.swift:13` / `ColorLiteralTests.swift:39-45,159-161`）、メニューバーの色2件（`MenuBarMark.swift:4` / `MenuBarViews.swift:5`）、WebSocket とロック中1件（iOS の `NotificationScheduler.swift:6`）、開始の門2件（`LiveActivityController.swift:8-9,81,152` / `ClientModel.swift:42`）。**条文は v2.18 / v2.19 で訂正済み。コードだけが古い前提を語り続けている** | [platform/0001](platform/0001-live-activity-lock-screen-background.md) / [0002](platform/0002-live-activity-background-start-and-suspend.md) / [0003](platform/0003-menu-bar-ground-and-status-item-color.md) 。**コードの8箇所に加えて、条文に3箇所残っていた** — `REQ-UIX-024`（実装役が発見）、**`REQ-NTF-002` の背景・理由と `REQ-UIX-035`（検証役が発見。どちらも MUST）**。**「WebSocket が切れる」は4箇所にあり、v2.19 が直したのは1箇所だけだった。** SPEC v2.21 で全部訂正 | K | agent | **major** | done | `fix/comments-that-outlived-their-premise` |
| **POL-060** | **8.3 冒頭の「プラットフォーム制約（Apple 公式で確認済み）」に出典がない**（`SPEC.md:818`）。REQ-NTF-002（**MUST**）、REQ-UIX-020 / 022 の **MUST→SHOULD 格下げの唯一の理由**、REQ-UIX-024 の禁止、第14章の帰結がこの一文に乗る。さらに **[0009](decisions/0009-live-activity-scope.md) は出典欄に「仕様書 8.3 冒頭」、[0030](decisions/0030-live-activity-is-display-only.md) は「`CONTEXT.md` §3（一次情報で確認済み）」と書いており、その §3 は [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) で空になった。**「確認済み」という文字列だけが**4文書**を巡回していた（`CONTEXT.md:653` も §3 を指す）。**調査完了（[platform/0002](platform/0002-live-activity-background-start-and-suspend.md)）: (b) と suspend は文書化されていたが、「例外は APNs による push-to-start のみ」は誤り。サーバー不要の開始経路が2つある**（`LiveActivityIntent` / iOS 26 のスケジュール開始）。**REQ-NTF-002 の支えは崩れていない**（根拠が「WebSocket が切れる」から「suspend 中はコードが走らない」に変わる）。**人間の決定（2026-08-29）: 事実を条文から追い出し `PLATFORM.md` を参照する。挙動は変えない。** SPEC v2.19 で反映 | `SPEC.md:818` / [platform/0002](platform/0002-live-activity-background-start-and-suspend.md) | K | **human** | **major** | done | `fix/axis-k-platform-facts` |
| **POL-061** | **REQ-COL-022（MUST）「メニューバーの地は可変でコントラストを保証できない」に出典がない**（`SPEC.md:1028`）。REQ-UIX-030・REQ-UIX-035（ともに **MUST**）と [0031](decisions/0031-the-menu-bar-mark-shows-the-session.md) の「印を3枚に分ける」設計がこの上に乗る。**[0038](decisions/0038-platform-facts-are-not-the-specs-job.md) 自身が「同じ問題に2つの答えがあり、片方は検証されていなかった」と名指ししている。**直ったのは壁紙側（POL-057）で、**調査完了（[platform/0003](platform/0003-menu-bar-ground-and-status-item-color.md)）: 「地は可変」は正しい。しかし「コントラストを保証できない」は誤りで、`NSStatusBarButton.h` は テンプレート画像について "This guarantees that the button will look correct" と明記している。そして REQ-UIX-035 の「色を使えないため」も誤り** — `NSButton.contentTintColor` は テンプレート画像に色を載せる正規 API で、系統的な扱いと**併用**すると書かれている。禁止されているのは `statusItem.view` だけ。**ただし形状で区別すること自体には別の根拠がある**（`accessibilityDisplayShouldDifferentiateWithoutColor` の "shapes or glyphs"）。**人間の決定（2026-08-29）: 理由だけ差し替える。処方（テンプレート画像・印3枚）は変えない。** 根拠を `accessibilityDisplayShouldDifferentiateWithoutColor` に置き換えた。SPEC v2.19 で反映 | REQ-COL-022 / [platform/0003](platform/0003-menu-bar-ground-and-status-item-color.md) | K | **human** | **major** | done | `fix/axis-k-platform-facts` |
| **POL-062** | **3.5 の表8行すべてに出典がなく、REQ-PLT-001（MUST）が「いずれか1つでも欠けると接続が成立しない」と断定している。****調査完了（[platform/0005](platform/0005-local-network-privacy-and-platform-settings.md)）: 断定は誤り。8行中、接続の成立に効くのは4行。** `NSAllowsLocalNetworking` は**不要**（**ATS は Network.framework に適用されない**）、`NSSupportsLiveActivities` と `files.user-selected.read-write` は**接続と無関係**、`network.client` は**理由が誤り**。`NSBonjourServices` の「対象: iOS」も誤り（**macOS 11.0+ にもあり、登録側にも要る**）。**「DHCP では `NSExceptionDomains` で回避できない」も誤り**（Apple は CIDR レンジを明示）。**完全に正しいのは `NSLocalNetworkUsageDescription` の1行だけ。****SPEC v2.20 で訂正済み**（表に「必要性」欄を新設） | REQ-PLT-001 / [platform/0005](platform/0005-local-network-privacy-and-platform-settings.md) | K | **human** | major | done | `fix/axis-k-round-two` |
| **POL-063** | **否定的事実の上に立つ MUST が2件。両方とも調査完了。****REQ-PLT-008（「許可状態を問い合わせる API は存在しない」＋ `-65570`）は正しい** — TN3179 が "There's **no general API**…(FB8711182)" と明文で否定し、**Apple 自身が `-65570` と `.localNetworkDenied` のコード例を載せている**（[platform/0005](platform/0005-local-network-privacy-and-platform-settings.md)）。正確には「**公開 API としては**存在しない」。**REQ-UIX-026 も「不可能」「サンドボックス上」は Apple の原文どおりで正しいが、主語が誤っている** — 不可能なのは **Live Activity** であって**ウィジェット拡張ではない**（[platform/0004](platform/0004-live-activity-payload-size-and-network.md)） | REQ-UIX-026 / REQ-PLT-008 | K | **human** | major | done | `fix/axis-k-round-two` |
| **POL-064** | **数値だけの MUST。両方とも調査完了。** ~~REQ-UIX-028（8時間 / 計12時間）~~ は [platform/0002](platform/0002-live-activity-background-start-and-suspend.md) で**正しいと確認できた。REQ-UIX-025 の 4KB も数値は正しい。ただし条文の限定が誤っている（緩すぎる方向に）** — 上限は**静的（`ActivityAttributes`）と動的（`ContentState`）の合計**に掛かる。**動的だけを 4KB に収めても制約を満たしたことにならない。** プッシュ限定でもない（[platform/0004](platform/0004-live-activity-payload-size-and-network.md)） | REQ-UIX-025 / [platform/0004](platform/0004-live-activity-payload-size-and-network.md) | K | **human** | minor | done | `fix/axis-k-round-two` |
| **POL-065** | **`CONTEXT.md:185` の記述が API の性質と食い違う疑い。**「`end()` は OS 上にあるものを全部畳む」は `Activity.end(...)` の説明ではなく、**`Activity.activities` を回す自前の実装の説明**である可能性。**プラットフォームの事実の形をした、自分のコードの説明** | `CONTEXT.md` §2 | K | agent | minor | done | `fix/three-that-touch-the-outside` |
| **POL-066** | **`CONTEXT.md:83`「ビューに Timer を置くと表示が止まる」が、原因未特定のまま一般則として書かれている。** `Timer.publish(...).autoconnect()` + `.onReceive` は通常機能する。**観測された文脈（`MenuBarExtra` のラベル）に固有かもしれない**。**人間の決定（2026-08-29）: B — 記述を観測された文脈に限定する。** 一般則として書くと、**次の人が使えるはずの手段を避ける。** 調べるほどの実害はない | `CONTEXT.md` §2 | K | **human** | minor | done | `fix/what-we-actually-checked` |
| **POL-067** | **空になった `§3` を根拠として指す参照が8箇所残っている。** `CONTEXT.md:483,647,653` / `SPEC.md:1580` / [0021](decisions/0021-published-as-oss-named-mdoro.md) / [0024](decisions/0024-rename-everything-to-mdoro.md) / [0030](decisions/0030-live-activity-is-display-only.md) / [0031](decisions/0031-the-menu-bar-mark-shows-the-session.md)。**行き先を `PLATFORM.md` へ張り替える**（[0038](decisions/0038-platform-facts-are-not-the-specs-job.md) 自身の §3 への言及は経緯なので残す）。**Live Activity に関わる3箇所は SPEC v2.19 で修復済み**（0009 / 0030 / `CONTEXT.md:661`）。**残り5箇所**（`CONTEXT.md:497` / `SPEC.md:1580` / 0021 / 0024 / 0031）は署名・通知・接続の話で、**それぞれの事実がまだ確認されていない** | [0038](decisions/0038-platform-facts-are-not-the-specs-job.md)。**残り5箇所も張り替えた**（2026-08-29）— `SPEC.md` OPEN-008 と 0021 は `PLATFORM.md` へ、`CONTEXT.md:517` と 0024 は**そもそも §2 が正しい行き先だった**（「通知には正しい署名が要る」は §2 にある）。0031 は訂正の注記が既に付いている。**調査記録（`platform/`）と経緯の記述は、後から書き換えないので残す** | K | agent | minor | done | `docs/punchlist-triage` |
| **POL-068** | **REQ-UIX-035 の参照先が誤り**（`SPEC.md:843`）。「iPhone は背面に回れば接続が切れる（**3.5 のプラットフォーム制約**）」とあるが、**この主張は 3.5 になく 8.3 冒頭にある。** POL-060 への依存が1件、参照の誤りで見えなくなっている | REQ-UIX-035 | K | agent | minor | done | `fix/axis-k-platform-facts` |
| **POL-069** | **`PLATFORM.md` の `未検証` に設計判断が混ざっている。** 2（通知を事前スケジュールする＝**REQ-NTF-002 そのもの**）、5（`replaceItemAt` を使う）、6（親ディレクトリに張る）は手段の選択であって事実ではない。7（Xcode の MCP サーバー）は**どの条文も依拠していない**（索引に置く性質の項目ではない） | `PLATFORM.md`。**3項目を外した**（2026-08-29） | K | agent | minor | done | `docs/punchlist-triage` |
| **POL-070** | **OPEN-007 が未決のまま、条文は断定している。** OPEN-007（`SPEC.md:1579`）は「無償 Personal Team で Time Sensitive を有効化できるか」を未決とするが、REQ-NTF-005 と第14章は「利用できない」と断定済み。**capability の有効化と配信挙動は別事象**。**人間の決定（2026-08-29）: B — 条文を実測の範囲に留める。** 確かめたのは**配信されないこと**だけで、**capability を有効化できるかは別の事象。** OPEN-007 は未決のまま残す | OPEN-007 / REQ-NTF-005 | K | **human** | minor | done | `fix/what-we-actually-checked` |
| **POL-071** | **同じ誤前提がコードと外向け文書に残っていないかの走査。****完了（2026-08-29・付録）: 既知の誤り8件 / 条文にない主張26件 / 条文と一致19件 / 出典あり2件。** 起票は POL-059・074〜078 | [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) / `CLAUDE.md` | K | `repo-auditor` | minor | done | `fix/axis-k-round-two` |
| **POL-072** | **iOS 26 に、サーバー不要で背面から Live Activity を開始する API がある**（`request(...alertConfiguration:start:)`）。**対象バージョンちょうどで入った。** 条文は「完全ローカル駆動と push-to-start は二者択一」という構図を前提にしているが、**その構図が一次情報と合っていない。** 第15章 FUT-013 の位置づけと、REQ-UIX-020 / 022 の格下げ理由に効く。**人間の決定（2026-08-29）: いまは採らない。** FUT-013 を「背面から開始・更新する3経路（うち2つはサーバー不要）」として書き直し、**採否を未決のまま残した**。スケジュール開始は開始時刻が事前に決まる場合の道具で、**利用者の操作で始まる Mdoro のセッションには現状あてはまらない** | [platform/0002](platform/0002-live-activity-background-start-and-suspend.md) / FUT-013 | K | **human** | major | done | `fix/axis-k-platform-facts` |
| **POL-073** | **`NSStatusBarButton` に `contentTintColor` が実際に効くかは静的に確認できない。** ヘッダが "Only applicable to borderless buttons" と限定しており、status bar button の `isBordered` の実値は実行しないと分からない。**軸 K で唯一、実測が要る点だった** | [platform/0003](platform/0003-menu-bar-ground-and-status-item-color.md) | K | — | minor | **不要** | — |
| **POL-074** | **コードが独自にプラットフォームの事実を主張している箇所が26件**（`PLATFORM.md` に項目が無いもの）。ダイナミックアイランドの寸法5件、Bonjour / ネットワーク3件、SF Symbols とアセット3件、サンドボックスとファイル4件、通知と署名2件、Keychain 1件、SwiftUI / AppKit 4件、Xcode ツールチェーン3件、外向け文書4件。**うち9件は `CONTEXT.md` §2 / §6 に実測の記録があり、残り17件は根拠がない。** 一覧は付録。**行番号は 2026-08-29 時点のもので、既にずれ始めている**（`HotKeyCenter.swift:53` には現在コメントが無い）。**人間の決定（2026-08-29）: B＋C — 正しさが依存している3組だけ調べ、残りは参照を付けるか「未検証」と明記する。****調査完了（[platform/0008](platform/0008-what-three-tests-rest-on.md)）: 3組すべてで「制約は本物だが限定が誤り」。1組目は実測で主張そのものが覆った** | [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) | K | **human** | major | done | `fix/what-the-tests-rest-on` |
| **POL-075** | **`docs/DEVELOPMENT.md` が、空になった `CONTEXT.md` §3 を指したまま「再調査しない」と言い続けている。** 指している ATS・ローカルネットワーク許可・Live Activity は、移送先の `PLATFORM.md` では**いずれも `未検証` に格下げされていた**（そして ATS は [platform/0005](platform/0005-local-network-privacy-and-platform-settings.md) で**このアプリに無関係**と判明した）。**[0038](decisions/0038-platform-facts-are-not-the-specs-job.md) の趣旨と正面から食い違い、今回の誤りが残った経路そのもの** | [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) / `DEVELOPMENT.md` | K | agent | **major** | done | `docs/what-a-contributor-needs` |
| **POL-076** | **`AGENTS.md` の署名と通知の記述が、実測より弱い。** `AGENTS.md:61-64` は "an unsigned build will not deliver them"（配信されないだけ、と読める）と書くが、`CONTEXT.md` §2 の実測は **ad-hoc 署名で `requestAuthorization` 自体が失敗し、権限は `notDetermined` のまま、設定にアプリが現れない**。**貢献者は「通知が来ない」を見ても `codesign -dv` を見に行く手がかりを持たない。** あわせて `AGENTS.md:89` が **「242 requirements」のまま**（正は 243。**二重に持った事実の片方だけが古くなった実例**） | `AGENTS.md` / `CONTEXT.md` §2 | K | agent | major | done | `docs/what-a-contributor-needs` |
| **POL-077** | **「SF Symbols のカタログは両プラットフォームで共通」という出典なしの主張の上に、テストの検査方法そのものが乗っている**（`SymbolNameTests.swift:22`）。`peerSymbolsOfBothPlatformsExist` は走らせた側の OS で「もう片方の名前」の実在を確かめる。**共通でなければ、このテストは「確かめたつもり」で通り続ける。** POL-027 と同じ、**always-true になりうる検査** | REQ-UIX-034 ほか | K | `platform-researcher` **調査完了（[platform/0006](platform/0006-sf-symbols-catalog-and-availability.md)）: 主張は真だった**（メタデータ10ファイルが SHA-256 一致）。**しかし検査が必要としている保証ではない。** 効く軸は**プラットフォームではなく OS バージョン**で、`symbolExists` は**検査ホストのカタログしか見られない**。**always-true ではないが、別の穴がある**（→ POL-081） | **major** | done | `fix/comments-that-outlived-their-premise` |
| **POL-078** | **`rename` についてのコードの主張が、条文より広い。** REQ-PLT-004 は「サンドボックス**外**（`/tmp` 等）**を跨ぐ**」だが、`LogWriter.swift:118-119` / `FileStateStore.swift:4` は「サンドボックス下では**ディレクトリを跨げば**失敗する」と読める。**`PLATFORM.md` ではこの項目は `未検証`** | REQ-PLT-004 | K | **human** | minor | done | `fix/what-we-actually-checked` |
| **POL-079** | **REQ-PLT-007 が「取り返しがつかない」ように読める。** TN3179 は「バックグラウンドでの拒否を**システムは記録しない**。後でフォアグラウンドで操作すれば、初回であるかのようにダイアログを出す」と明記している（[platform/0005](platform/0005-local-network-privacy-and-platform-settings.md)）。**条文の「黙って拒否される」は正しいが、回復可能であることが書かれていない。** また**この条項は iOS のもので、macOS には対応する記述が無い** | REQ-PLT-007 | K | agent | minor | done | `fix/axis-k-round-two`（SPEC v2.20） |
| **POL-080** | **シミュレータはローカルネットワークプライバシーを実装していない**（"Test your local network privacy behavior on a real device" — TN3179）。**`AGENTS.md` にも `DEVELOPMENT.md` にも書かれていない。** 貢献者がシミュレータで接続を試して「動く／動かない」を誤って結論づける | [platform/0005](platform/0005-local-network-privacy-and-platform-settings.md) / `AGENTS.md` | K | agent | minor | done | `docs/what-a-contributor-needs` |
| **POL-081** | **`symbolExists` は検査ホストのカタログしか見られない。** CI は macOS 26.5 で走るが、配備対象は **26.0**。**導入年 2025.1（＝26.1）のシンボルが 29件実在する**ため、そういう名前を足すと **CI は緑のまま、実機でアイコンが黙って消える**（iOS 固有ではない。macOS 26.0 でも同じ）。**実行せずに確かめる手段はある** — `CoreGlyphs.bundle` の `name_availability.plist` を読み、配備対象と突き合わせる。**人間の決定（2026-08-29）: 直さない。** いま名指しされている13個はすべて導入年 ≤ 2024 で実害がなく、**直すとテストが OS の非公開パスに依存して、貢献者の環境で落ちる。** 警告は POL-084 でコメントに入れた。**26.1 以降のシンボルを使うときに、ここを読むこと** | [platform/0006](platform/0006-sf-symbols-catalog-and-availability.md) | K | **human** | **major** | **現状維持** | — |
| **POL-082** | **`iphone.gen3` / `iphone.gen3.slash` は使用制限付きシンボル**（"may not be modified and may only be used to refer to Apple's iPhone"）。**Mdoro の用法は適合している**が、**OSS として公開する以上、制限付きの素材を使っていることは把握しておく必要がある**（軸 J・ライセンスと第三者素材にも関わる）。テストはこれを区別していない。**人間の決定（2026-08-29）: A — `docs/` に記録するだけ。** 軸 J（ライセンスと第三者素材）の材料とする。**利用者向けの文書に書くことではない** | [platform/0006](platform/0006-sf-symbols-catalog-and-availability.md) | K / J | **human** | minor | done | `fix/what-we-actually-checked` |
| **POL-083** | **`peerSymbolsOfBothPlatformsExist` は、直下の `connectionStatusSymbolsExist` と重複している。** 13個のうち3個は macOS 上で二度検査され、**固有に足しているのは実質 `laptopcomputer` / `laptopcomputer.slash` の2個だけ**。残る8個は無関係な名前をここに間借りさせたもの。**検査の意図そのものは正しく機能している** | [platform/0006](platform/0006-sf-symbols-catalog-and-availability.md) | K | agent | minor | open | — |
| **POL-084** | **`SymbolNameTests.swift:22` のコメントが、真だが的外れな根拠を述べている。** 「カタログは両プラットフォームで共通」は事実だが、**この検査が依拠すべきなのは OS バージョンの軸**である。POL-059 と同じ「コメントが誤った軸を教える」問題 | [platform/0006](platform/0006-sf-symbols-catalog-and-availability.md) | K | agent | minor | done | `fix/what-the-comments-claim` |
| **POL-085** | **検証役の指摘5件**（コメントの表現）。参照の付け方が揃っていない2箇所 / REQ-COL-022 の理由が半分（「地が可変でも成立する唯一の手段」が落ちた）/ `not on the start path` が両義的 / `activitySystemActionForegroundColor` に掛かる説明の範囲が文書化された効果より広い / 「同じ除外」が旧構図の名残。**内容と挙動は問題なしと判定済み** | [platform/0001](platform/0001-live-activity-lock-screen-background.md) / [0002](platform/0002-live-activity-background-start-and-suspend.md) | K | agent | minor | done | `fix/comments-that-outlived-their-premise` |
| **POL-086** | **`docs/CONTEXT.md` の PUNCHLIST 集計が実体とずれていた**（検証役が実測して指摘）。`review` の欄が表に無く、`open` の件数も本 PR 以前から1件ずれていた。**状態を書く場所が、状態を数え違えていた** | `CONTEXT.md` §6 | — | agent | minor | done | `fix/comments-that-outlived-their-premise` |
| **POL-087** | **末尾に改行の無いログファイルに追記すると、改行が1つ足される。** `LogFileEditor.swift:33,36` の `trailingNewline` は**書かれるだけで一度も読まれず**、77行目が無条件に `+ newline` する。**`preservesAllLines` は行の配列を比べるため、これを検出しない。** コメント（「最後に戻す」）は**コードが持っていない振る舞いを述べている**。**「`MdoroLog.md` へは挿入のみ」は「緩めない3つ」の1つ**であり、実害は小さくとも原則の側にある。**工程14a の翻訳役が見つけた** | 原則1 / REQ-LOG-004 | — | agent | **major** | done | `fix/three-that-touch-the-outside` |
| **POL-088** | **軸 F の入力**（工程14a・第1回の翻訳役が「不要では」と思ったが**削除せず残した**もの）。章番号だけを指す内容ゼロの1行が6箇所（`SessionType.swift:3,10` / `TimerAction.swift:3` / `PresetContext.swift:3` / `Tasks/TaskItem.swift:9` / `TimerContext.swift:3` / `Tasks/TaskContext.swift:11`）、**直下2行の言い換え**が `Tasks/TaskParser.swift` に2箇所、フィールド名の反復が `Effect.swift:18` ほか。**翻訳と削除を混ぜないため、この回では触っていない。****あわせて観点が1つ**: 日本語が1語で持つ限定（**全角/半角**・行頭/冒頭・以上/超）は、英語にすると消えることがある。第1回では `半角スペース` → `a space` で実際に落ちた（検証役が検出）。**もう1つ**: `Services/DiagnosticLog.swift:7` は [0018](decisions/0018-diagnostic-log-policy.md) の**禁止**を「現状そうなっている」と読める宣言形で書いている。**宣言形はブランチ全体で一貫しているのでこの回では直していないが、軸 F がその形を是とした場合でも、ここだけは単独でもう一度見ること**。**第3回の入力4件**: `MdoroClient.swift:113` と `NotificationScheduler.swift:35`（直下の逐語訳に近い）/ `Theme.swift:19` の `init(focusView:)` は**引数を使わず常に `.dark` を返す**（コメントではなく実装の話）/ `MdoroWidgetLiveActivity.swift:93` はファイル冒頭と内容が重なる。**第4回の入力6件**: `PersistenceTests` の「再起動を模して読み直す」/ `MdoroCoreTests` の `// B群`（2文字）/ 同 `ReviewFixTests` の `// 2.` `// 3.` `// 4.`（**`1.` が無く、番号列が既に壊れている**）/ `ProtocolTests` の REQ-PRT-004（テスト名と assertion の逐語）/ `TaskSelectionTests` の「ブロック ID があれば追従の出番がない」/ `DiagnosticTests` の「上限は 2 世代ぶん」 | [0032](decisions/0032-code-comments-are-english.md) / 軸 F | F | agent | minor | open | — |
| **POL-089** | **コメントの行幅に基準が無い。** `main` の最長はコメント162文字 / コード160文字、linter 設定なし。**決めるなら別工程で一括**（翻訳の回で再整形すると、訳の差分と整形の差分が混ざって読めなくなる）。**人間の決定（2026-08-29）: B — 決めない。** 原文の理由: **「場合によって文字数も変わってくるので、ここで定義することは難しい」。** 一律の上限を設けると、**それに合わせるための改行が意味の切れ目とずれる** | — | F | **human** | minor | **決定済み** | — |
| **POL-090** | **REQ-ERR-004 の条文と実装がずれている。** 条文（`SPEC.md:1538`）は「**3回失敗で通知**」だが、実装は `consecutiveFailures >= 3` で、**成功するたびに 0 に戻る**（`LogWriter.swift:200,206`）。**失敗・成功・失敗・成功・失敗では、条文なら通知し、コードは通知しない。** 利用者から見て「ログが書けていないことを知らされるか」が変わる。**工程14a 第2回の検証役が、訳を条文と突き合わせて見つけた** | REQ-ERR-004 / [0033](decisions/0033-unset-log-path-records-nothing.md) | — | **human** | **major** | done | `fix/failures-that-come-and-go` |
| **POL-091** | **訂正済みの前提を引いているコメントが、9箇所目として見つかった。** `LiveActivityController.swift:238` が「**拡張側では**時計合わせができない」と書いている（REQ-COM-009 / REQ-UIX-026）。**SPEC v2.20 が訂正したのはまさにこの主語で、「不可能なのは Live Activity であって、ウィジェット拡張ではない」。****挙動は正しい**（拡張側で時計合わせをしていない）。誤っているのは根拠の述べ方だけ。**POL-059 の8件にも POL-071 の一覧にも入っていなかった。工程14a 第3回の翻訳役が発見** | [platform/0004](platform/0004-live-activity-payload-size-and-network.md) / REQ-UIX-026 | K | agent | major | done | `fix/what-the-comments-claim` |
| **POL-092** | **コメントの数え方がコードと合っていない箇所が2件。** (1) `FocusView.swift:34`「**3つの塊**を離して置く」— **`Spacer` が区切るのは4つ**（4本の `Spacer(minLength: 0)` が `secondary` / 時計＋進行バー / `controls` / `exitHint` を区切る）。**当初この起票は理由を「`exitHint` が常時 `opacity 0` だから」と書いていたが、それは誤りだった** — `exitHint` は単タップとドラッグで**3秒間表示される**（`FocusView.swift:135,139-147` / `SPEC.md:295`）。**結論（4つ）は変わらない**（`opacity 0` のビューもレイアウト上の場所は占めるため）。**検証役が指摘**。(2) `MdoroWidgetLiveActivity.swift:51`「角の丸みに食われるので**四方**を逃がす」— **コードは3辺**（`.padding(.horizontal, 8)` ＋ `.padding(.bottom, 4)`。top に padding なし）。**どちらも翻訳では原文どおりにしてある** | — | F | agent | minor | done | `fix/what-the-comments-claim` |
| **POL-093** | **同じ主張が2つの要件IDに紐づいている。** 「休憩に延長はない」を `FocusView.swift:186` は **REQ-TIM-040**、`MainScreen.swift:158` は **REQ-TIM-044** に帰している。**SPEC 自身が2箇所で別々に帰属させている** — `SPEC.md:675` は REQ-TIM-044、**`SPEC.md:885`（REQ-UIX-011）は「延長は `WORK` 以外では非表示とする（**REQ-TIM-040 により**休憩には延長がないため）」**。**`FocusView` が実装しているのは REQ-UIX-011 なので、その REQ-TIM-040 は SPEC の帰属に従っている。****REQ-TIM-044 へ揃えると、コメントが実装している条文と食い違う。****当初この起票は SPEC の片面しか見ていなかった（検証役が指摘）**。**人間の決定（2026-08-29）: A — REQ-TIM-044 へ寄せる。** REQ-TIM-044 は「**休憩に対する延長操作は提供しない**」と明示的に述べており、REQ-TIM-040 は**含意しているだけ**。`SPEC.md:885`（REQ-UIX-011）の帰属を直し、**それに従って `FocusView` のコメントも揃える** | REQ-TIM-040 / REQ-TIM-044 | G | **human** | minor | done | `fix/what-we-actually-checked` |
| **POL-094** | **取り消された制約を、コメントが4箇所で復活させている。** `MainScreen.swift:233` / `MainWindowView.swift:244,276` / `ColorRole.swift:32` が「バナー表現（`-subtle` の地に `-line` の枠）は **`warning` に予約**」と書いているが、**`SPEC.md:186` は「旧条文は目的に照らして広すぎ、未接続（Clay）の帯まで禁じてしまっていた」として REQ-UIX-046 への参照に置き換えている。** 現行の REQ-COL-011（`SPEC.md:1068`）が禁じているのは**セッション状態へのバナーだけ**で、実装もそちら（`ColorRole.swift:37` の `allowsBannerTreatment = !isSessionRole`）。**このコメントを根拠に判断すると、SPEC が明示的に取り消した制約が戻る。** POL-091 と同じ類型。**翻訳の欠陥ではなく `main` 以前からある記述** | REQ-COL-011 / REQ-UIX-046 | K / G | agent | major | done | `fix/what-the-comments-claim` |
| **POL-095** | **REQ-ERR-009（SHOULD）が実装されていない疑い。** 条文（`SPEC.md:1546`）は「該当メッセージのみ破棄し、接続を維持する。**連続10回で再接続する**」だが、`MdoroClient.swift:140` の `handle(_:)` は**破棄するだけでカウンタを持たない。** 翻訳とは無関係の既存の実装。**工程14a 第3回の検証役が、訳を条文と突き合わせて見つけた**。**人間の決定（2026-08-29）: A — 実装する。** 実装は小さく、**相手がおかしくなったときに自力で戻る性質は、LAN 内で完結する設計では効く**。**REQ-PRT-005 との切り分けが要った** — `decodeServer` は「壊れている」を `throw`、「未知の種別」を `nil` で返す。**両方を数えると、将来の Mac が新しい種別を10個続けて送った時点で iPhone が再接続ループに入る** — REQ-PRT-005（MUST）が防ごうとしているものそのもの。**`throw` だけを数える** | REQ-ERR-009 | — | **human** | minor | done | `fix/ten-broken-messages` |
| **POL-096** | **改名の反映漏れ。** `TaskRobustnessTests.swift:92` のコメントが **`PomodoroLog.md`** と書いている。**工程9で `MdoroLog.md` に改名済み**（`TimerContext.defaultLogFileName` / SPEC 9.3 / REQ-LOG-001 / [0024](decisions/0024-rename-everything-to-mdoro.md)）。**工程14a 第4回の翻訳役が発見し、指示どおり直さずそのまま英訳した** | [0024](decisions/0024-rename-everything-to-mdoro.md) / REQ-LOG-001 | G | agent | minor | done | `fix/what-the-comments-claim` |
| **POL-097** | **`Tools/make_icon.swift` が出典なしでプラットフォームの事実を主張している** — 「メニューバーの高さは 24pt」。**[platform/0003](platform/0003-menu-bar-ground-and-status-item-color.md) が HIG から同じ数値を引用済み**なので、**事実は正しいが参照が付いていない。** [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) の追記（**参照付きなら事実を書いてよい**）に照らすと、参照を足せば済む | [platform/0003](platform/0003-menu-bar-ground-and-status-item-color.md) | K | agent | minor | done | `fix/what-the-comments-claim` |
| **POL-098** | **同じ要件を2つの英語で呼んでいる。** `MdoroCoreTests` のスイート表示名が `"Heads-up notification triggers"`、Sources 側は `pre-notification`（型名も `PreNotification`）。**どちらも英語なので工程14a の対象外だが、REQ-NTF-020〜023 を指す語が2つある。** 表示名は CI のログに出る | REQ-NTF-020 / [0032](decisions/0032-code-comments-are-english.md) | F | agent | minor | done | `fix/what-the-comments-claim` |
| **POL-099** | **コメントの数字がテストと合わない。** `ShortSessionTests.swift:60-61` は「壁時計で 90 秒でも、70 秒止まっていれば記録しない」と書くが、**テストは 100秒 / 停止70秒 / 正味30秒**（`t0` 開始 → `+20` 一時停止 → `+90` 再開 → `+100` 中断）。**同じテストの assertion メッセージ自身が `a net 30 seconds is under the threshold` と書いている。** 90/70 は差が20で、どちらとも合わない。**`main` 以前からある。工程14a 第4回の検証役が発見** | REQ-TIM-032 | F | agent | minor | done | `fix/what-the-comments-claim` |
| **POL-100** | **`.gitignore` のセクション見出し8行が日本語。** [0032](decisions/0032-code-comments-are-english.md) は「コードコメント」を対象としており、**設定ファイルのコメントは条文の外**。公開後に貢献者が読む可能性はある。**英語にするか、対象外と明記するか**を決める必要がある。**人間の決定（2026-08-29）: A — 英語にする。** 8行で済み、**貢献者が `.gitignore` を編集するときに読む** | [0032](decisions/0032-code-comments-are-english.md) | F | **human** | minor | done | `fix/what-we-actually-checked` |
| **POL-101** | **同じ誤りの「より読まれる側」が `MdoroCore` に残っていた。** `LiveActivityAttributes.swift:6` は POL-091 と同じ主語の誤り（「**拡張が**ネットワークに触れない」）、`:38` は v2.20 が訂正した限定のまま（「**動的データが** 4KB」）。**後者は `ContentState` のイニシャライザに付いており、その誤解が実装判断に直接効く場所。****実装役が「狭いほうを直して広いほうを残すのは目的と逆」と申告して発見** | [platform/0004](platform/0004-live-activity-payload-size-and-network.md) / REQ-UIX-025 / REQ-UIX-026 | K | agent | major | done | `fix/what-the-comments-claim` |
| **POL-102** | **条文が意図的に狭めた断定を、コメントが広いまま述べていた。** `DiscoveredServer.swift:23` の「there is **no API** to ask about the permission」。**v2.20 は「精確を期して『**公開** API』と書き換えた（非公開シンボルは SDK に存在する）」と改訂履歴に記している。** 参照も付いていなかった | REQ-PLT-008 / [platform/0005](platform/0005-local-network-privacy-and-platform-settings.md) | K | agent | minor | done | `fix/what-the-comments-claim` |
| **POL-103** | **要件IDを引かないコメントは、この軸では拾えない。** 群 A の走査は「訂正された要件IDを含む行」を起点にしたため、**要件IDを引かずにプラットフォームの事実だけを述べているコメントは網に掛からない。** それが POL-074 の26件であり、**別の軸で見る必要がある**（実装役の申告） | [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) / POL-074 | K | — | minor | open | — |
| **POL-104** | **診断ログに `recentFailures` を出すと、切り分けが一段速くなる。** `AppModel` の `diagnostics.write("log.write", …)` は `written` / `pending` / `file` / `why` を出しており、**間欠的に失敗しているのか継続的に失敗しているのかが後から読めない。** 整数値なので [0018](decisions/0018-diagnostic-log-policy.md) の「利用者由来の文字列を書かない」に抵触しない。**実装役の提案。空 flush を窓から外したことで価値が上がった** — `attemptedAWrite` が偽だった flush は診断ログに `written=0 / pending=0` としか残らず、**窓に入ったのか入らなかったのかが後から読めない** | [0018](decisions/0018-diagnostic-log-policy.md) / REQ-ERR-004 | — | agent | minor | open | — |
| **POL-105** | **`didNotify` の名前が実態と合わなくなった。** いまの意味は「まだ通知していない不調が立っているか」ではなく「**立っている不調について、もう伝えたか**」。**32,766通りの等価性検証まで済んだ箇所を改名する価値は薄いが**、次に読む人が `didNotify = reachedThreshold` の一行で止まりうる。**実装役の申告** | [0039](decisions/0039-failures-that-come-and-go-still-count.md) | F | agent | minor | open | — |
| **POL-106** | **Mac 側に同じ穴がある。** `MdoroServer.swift:129` に**まったく同じコメントと同じ `try?`** があり、カウンタを持たない。**ただし条文をそのまま当てはめられるかは自明ではない** — サーバーは「再接続」できず、できるのは接続を切ることだけで、それは REQ-COM-004 により iPhone 側の再接続を誘発する。**REQ-ERR-009 の「再接続する」の主語をどちらと読むかの判断が要る。** 両側でやるなら `BrokenMessageCounter` は REQ-PRT-001 の対象になり、`MdoroCore` へ移すのが筋 | REQ-ERR-009 / REQ-PRT-001 | — | **human** | minor | **決定済み** | **裁定（2026-09-02）**: 条文に「Mac は10回で接続を切る」を追記（SPEC v2.29）。**実装は通信3部作の後**。数える部品は MdoroCore へ |
| **POL-107** | **`scheduleReconnect()` が1回の切断で2度呼ばれ、バックオフが条文より1段速く伸びる。** `receive` の `error != nil` 経路と `stateUpdateHandler` の `.failed` / `.cancelled` 経路の**両方**が呼ぶため、`backoff.nextDelay()` が2段進む。**REQ-COM-004 は「初回1秒、上限30秒」だが、実際の初回は2秒。** `reconnectTask` は差し替えられるので接続そのものは1本で、実害はバックオフの伸び方だけ。**既存の挙動で、POL-095 が作ったものではない** | REQ-COM-004 | — | **human** | minor | **決定済み** | **裁定（2026-09-02）**: 直す。切断イベントを1回に畳む。単独 PR・3部作の後 |
| **POL-108** | **`handle` の配線そのものはテストできていない。** POL-095 で確かめたのは**数え方だけ**で、「デコード失敗が実際にカウンタを進め、10回目に `scheduleReconnect()` が呼ばれる」ことは未検証。`MdoroClient` は `NWConnection` を自分で生成し、`handle` は private で、再接続の観測点が `status` の変化しかない。**接続の生成をプロトコルで注入すれば結線までテストできるが、それは設計変更**（実装役の申告） | REQ-ERR-009 | — | **human** | minor | **決定済み** | **裁定（2026-09-02）**: 継ぎ目を作って配線をテストする（このリポジトリの5回目の継ぎ目）。単独 PR・3部作の後 |
| **POL-109** | **`AuthFailureCode.anotherClientConnected` はどこからも返らない。** `Pairing.swift:109-111` は、既に接続がある場合すべて `.needsUserApproval` を返す（REQ-SEC-004）。**列挙子・`ErrorCode(own: 64)`・iPhone 側の文言（`ConnectionViews.swift:141`）は存在するが、到達経路が無い。** 条文が意図しているのか、実装が REQ-SEC-004 に寄せた結果として不要になったのかの判断が要る。**POL-054 の実装役が発見** | REQ-SEC-004 / 10.2 | — | **human** | minor | **決定済み** | **裁定（2026-09-02）**: 列挙子・`ErrorCode(own: 64)`・iPhone 側の文言を消す。到達しないエラー処理を公開コードに残さない。単独 PR・3部作の後 |
| **POL-110** | **`deduplicated` が最新の Mac を捨てうる。実測で確認**（[platform/0008](platform/0008-what-three-tests-rest-on.md)）。「古いほうが番号が小さい」は成り立たない —— **`Name (2)` は番号を返上せず、後から起動した登録が空いた `Name` を取る。** 最大番号を残す規則は、この状態で**最新を隠す。** 他に3つの場面で誤る: **同名の別 Mac 2台**（片方を黙って落とす）/ **正当に `(2)` で終わる Mac 名**（本物の「Studio」と混ざる）/ **TXT にインスタンスを一意に指す値が無い**（名前の文字列以外に判定材料がない）。**利用者から見ると「一覧に出るのに繋がらない Mac」が残る**。**人間の決定（2026-08-29）: A — 重複の排除をやめ、見えたものを全部出す。**「繋がる Mac を隠す」ほうが「幽霊が数秒出る」より悪く、**LAN 越しの残存時間は測られていない。****人間の追加情報: 実際には2つどころか3つ重複したことがある（体験にもとづく）。****ただしこれは対症であり、根本は POL-113** | [platform/0008](platform/0008-what-three-tests-rest-on.md) / REQ-COM-001 | K | **human** | **major** | done | `fix/what-the-tests-rest-on` |
| **POL-111** | **`TestHost.isRunning` の支えが細い。** 検出は**未文書の環境変数 `XCTestConfigurationFilePath` 1本**に乗っており、しかも `XCTestCore` の `loadTestConfiguration` は **`XCTestConfigurationEncodedValueEnvironmentKey` を先に試す**（2番手）。**Xcode が encoded value 経路に切り替えたら、検出は黙って `false` を返し、ガードが無言で開く**（＝テストが本物の通知を出し、スリープ抑止を掛け、LAN に Bonjour を出す状態へ戻る）。**それを捕まえる app-hosted の `TestHostDetectionTests` は CI で走らない** —— CI は `swift test` を `Packages/MdoroCore` で回すだけ。**`TestHostTests` はガードがテキストとして存在することしか見ていない**。**人間の決定（2026-08-29）: A — 両方の変数を見る。** 1行で、実測された2番手の経路を塞げる。**CI で app-hosted のテストを走らせるか（B）は別の判断として残す** | [platform/0008](platform/0008-what-three-tests-rest-on.md) / POL-047 | K | **human** | **major** | done | `fix/what-the-tests-rest-on` |
| **POL-112** | **`TestHost` と `StringCatalogTests` のコメントが、正しい結論を誤った機序で説明している。** (1) `TestHost.swift:3-7`「`@testable import` には `BUNDLE_LOADER` が要る」→ **要求するのは `ENABLE_TESTABILITY`。`BUNDLE_LOADER` が要るのは取り込む先が App モジュールだから** (2) `:20-24`「XCTest が設定する」→ **設定するのは起動側** (3) `StringCatalogTests.swift:106-107`「`.xcstrings` は Xcode のエディタだけが書く」→ **Xcode のビルドと `xcstringstool sync` も書く** (4) `:7-9` の主張は正しいが、**このテストが捕まえるのは「カタログを更新せずに出した変更」** | [platform/0008](platform/0008-what-three-tests-rest-on.md) | K | agent | minor | done | `fix/what-the-tests-rest-on` |
| **POL-113** | **端末の同一性を、OS が書き換える表示名が担っている。POL-110 の根本。** ペアリングのトークンは **`TokenKeychain` が `serverName` をキーに保存**しており（`baseQuery(serverName)`）、その `serverName` は **Bonjour のサービス名** —— **mDNSResponder が衝突時に `Name (2)` `Name (3)` へ勝手に書き換えるもの**（[platform/0008](platform/0008-what-three-tests-rest-on.md)）。**帰結**: (1) 名前が変わると**別の鍵でトークンを探すことになり、ペアリング済みなのに未ペアリング扱いになる** (2) 観測した名前ごとに**トークンが溜まる** (3) **`ClientModel.forgetPairedMac()` は `pairedServerName` で消すので、名前がずれていると消し損ねる**（利用者が「Mac を削除」しても消えない）。**Mac 自身は、自分が何という名前で登録されたかを知らない**（`serviceRegistrationUpdateHandler` 未使用）。**TXT は `ws` と `v` だけで、インスタンスを一意に指す値が電波に乗っていない。****直すには通信仕様の変更が要り、両端を同時に直す必要がある**（POL-051 と同じ構図）。**観測されているのは (1) 同名が3つ並んだこと**（人間の体験）**だけである。****(2) と (3) はコードから導いた帰結で、確かめていない** —— とくに **(3) は、iPhone アプリの設定画面から「Mac を削除」を実際に押して確かめたわけではない**（人間が明示的に訂正。2026-08-29）。**関連を指摘したのが人間であり、失敗を観測したのではない**。**[0040](decisions/0040-identity-is-not-a-name.md) に統合**（2026-08-30）。**個別に直さない** —— POL-113 / 123 / 125 / 127 / 131 は**すべて同じ3箇所**（TXT・Keychain の鍵・Mac の保存形式）に触るため | REQ-SEC-002 / REQ-COM-001 / [platform/0008](platform/0008-what-three-tests-rest-on.md) | K | **human** | **major** | **決定済み** | [0040](decisions/0040-identity-is-not-a-name.md) |
| **POL-114** | **Bonjour の登録が漏れている。同名が並ぶ本当の原因はこれ**（2026-08-30 に実機で確認）。`MdoroMacApp.swift` の `model.start()` は **`WindowGroup` の中のビューに付いた `.task`** から呼ばれる。**`.task` はビューが現れるたびに走る**ので、**メインウィンドウを開き直すたびに `startServer()` が再実行される。** そして **`MdoroServer.start()` も `InfoHTTPServer.start()` も、`self.listener` を上書きするだけで前の listener を `cancel()` していない** —— **古い listener は生きたまま、Bonjour の広告も残る。** mDNSResponder がそれぞれに `(2)` `(3)` … を付ける。**利用者の機械で実測: `MdoroMac` プロセス2つに対し `_mdoro._tcp` の登録が5つ**（`Lychee`, `Lychee (2)`〜`(5)`、インターフェース 1/12/20/21/22 に出ている）。**ペアリングが完了しないのもこれ** —— iPhone が別プロセスの登録に当たると、そのプロセスはペアリング中でないので `pairingModeNotActive` を返し、画面には `Start pairing on your Mac` が出る（`ConnectionViews.swift:138`）。**POL-110 / POL-113 が扱っていた「同名の重複」は、大半がこの漏れの結果である。****利用者が実機で確認（2026-08-30）: 2つのプロセスを終了させて起動し直したところ、ペアリングが問題なく完了した。****観測されたのはこれだけである** —— 一覧に何件出たかは報告されていない。**修正時に確かめた結果、漏れていたのはネットワーク側だけだった** —— `startWatchingTaskFile` / `startTicking` / `updateHotKey` / `syncSideEffectsToState` は**すでに冪等**（それぞれ先に `cancel` / `stop` / `unregister` を呼ぶか、`nil` チェックで守られている）。**3層で畳んだ**: `AppModel.start()` を1回きりに（**各メソッドを冪等にするだけでは閉じない** —— 最終行が `Task { await startServer() }` で **await をまたぐため、同ターンの2回目も guard を通過できる**）／両サーバーの `start()` 冒頭で既存の `stop()` を呼ぶ／`startServer()` で古い `InfoHTTPServer` を畳んでから作る | REQ-COM-002 / REQ-COM-003 | — | agent | **major** | done | `fix/what-the-tests-rest-on` |
| **POL-115** | **REQ-COM-010（MUST）が実装されていない。3原則の3つ目に触れる。** 条文は「**残り時間の算出には単調増加時計（`ContinuousClock` / `mach_continuous_time`）を用い**、壁時計は `sessionEndAt` の生成・ログの時刻表記・論理日の判定にのみ用いる。**壁時計が単調時計に対し2秒以上乖離したら再同期し通知を再スケジュールする**」だが、**`ContinuousClock` / `mach_continuous_time` は製品コードに0件。** 両端とも `displayNow = Date()`（壁時計）で残り時間を出しており、**後半（乖離の検出と再同期）も無い。****利用者の報告（2026-08-30）**: 「開発開始から今までは iPhone のほうが 0.8s 程度遅かったが、いまは 0.8s 〜 −0.8s の範囲で変化し、iPhone が早いこともある」。**確かめたこと**: 時刻同期の計算式（REQ-COM-008）自体は条文どおりで、**Mac 側の処理遅延（t3−t2）は相殺される。** 往復 500ms 超は棄却されるので、**ネットワークの非対称性だけでは offset の誤差は ±0.25s を超えられない。****±0.8s はその範囲を超えている。****確かめていないこと**: 壁時計が補正された瞬間は観測していない（状況証拠）。**`timeSync.offset` はどこにも記録されておらず、推定値が振れているのか表示だけなのかが読めない** | REQ-COM-010 / 3原則 | — | **human** | **major** | open | — |
| **POL-116** | **多重起動を防ぐ仕組みが無い。** POL-114 を直すと「1プロセス＝1登録」になるが、**`MdoroMac` が2つ動いていれば登録は2つ出る。** 実測の「プロセス2・登録5」は、**片方が4回 `start()` した形と整合する。** ログイン時起動（[0016](decisions/0016-standard-settings-and-hotkeys.md)）と手動起動、Xcode のビルドとインストール済みの並存などの経路がある。**実装役の申告。**実機観察（2026-09-02）**: 2つ目のインスタンスを起動すると、**両方が同じ `identity.json` = 同じ `id` を電波に載せる**（1本目以降、同一性は id にあるため、多重起動は「別の Mac が2台」ではなく「同じ Mac が2回」になった）。利用者の観察では1つ目が接続すると2つ目も接続表示になった。id が単一性の根拠になった今、多重起動の害は増している** | REQ-COM-002 | — | **human** | minor | **決定済み** | **裁定（2026-09-02）**: 2つ目の起動は既存プロセスを手前に出して自分は終了する。`LSMultipleInstancesProhibited` が最小だが plist 変更は 0013 により人間の Xcode 操作になりうる —— コード側の検出で完結できるか実装時に判定。優先度は6件中最上位 |
| **POL-117** | **iPhone 側の `ClientModel.start()` も冪等ではない**（`ClientModel.swift:54`）。`browser.start()` と `startTicking()` は自分で畳むが、**`requestAuthorization` / `discardOrphansIfUnconfirmed()` / `restoreLastSnapshot()` は繰り返される。** iOS の `WindowGroup` では実害が出にくいが、**「片方のプラットフォームで踏んだ穴は、もう片方も見に行く」に該当する。** 実装役の申告 | POL-114 / REQ-PRT-001 | — | agent | minor | open | — |
| **POL-118** | **未設定のログ保存先が「失敗」として扱われ、キューに積まれ、フォルダを選んだ瞬間に過去分が一括で書き込まれる。条文と決定に3つ違反している**（軸 E・**blocker**）。REQ-LOG-002（**MUST**）は「未設定の間は**書き込みを試みず、キューにも積まない**」、[0033](decisions/0033-unset-log-path-records-nothing.md) は「**未設定は失敗ではなく未構成**」「再試行キューは**対象外**」。実装は (1) `enqueueLog` が**無条件に積む**（`AppModel.swift:741-745`）(2) `flushLogQueue` が**未設定を失敗として扱う** —— `logWriteFailed = true`、エラー文言、`log.blocked` を warn で記録（`:751-762`）(3) `setLogFolder` の末尾が **`flushLogQueue()`**（`:909`。コメントは REQ-LOG-005 を引くが 0033 は対象外としている）。**キューは `state.json` に永続化されるので再起動をまたいで溜まり続ける。****公開後は全利用者がこの状態から始まる** —— 未設定のまま数日使い、後からフォルダを選んだ瞬間に、**選んだ覚えのない過去数日分が一度に書き込まれる。****POL-020 は done だが、直したのは条文だけで実装は当時のまま**。**修正済み**: 門を **`LogWriteQueue.enqueue(_:to:)` の入口**に置いた（**既定値を付けず必須引数にしたので、呼び出し側が忘れられない**）。**`TimerEngine` には触れていない** —— 状態機械はログの保存先を知らない。**未設定は「失敗」から切り離し**、画面では記号・色・文面で区別（`folder.badge.questionmark` / `textSecondary`）。診断ログは **`log.blocked`（WARN）→ `log.notRecorded`（INFO）**。**旧実装が溜めたキューは、未設定で起動したときに破棄し `log.dropped`（WARN・件数のみ）を残す** | REQ-LOG-002 / [0033](decisions/0033-unset-log-path-records-nothing.md) | E | agent | **major** | done | `fix/an-unset-destination-is-not-a-failure` |
| **POL-119** | **「OS が書き込みを拒否する」が、README の薦める構成では成立しない。** 読み取り専用ブックマークが守るのは**そのブックマーク経由のアクセス**であって「`Task.md` というファイル」ではない。ログの保存先は**フォルダ単位で読み書き**が付く（[0015](decisions/0015-log-folder-scoped-access.md)）。**README 自身が「a log file next to it」と同一フォルダを標準構成として説明しており、その構成では `Task.md` はアプリが読み書きできるフォルダの中に入る。** 実際に守っているのは `LogWriter.validate` のパス比較 —— **コードの規律**。振る舞いは正しいが、**「構造で守っている」という理由付けが実態と違う**（[0002](decisions/0002-task-md-read-only.md)）。`SECURITY.md` の "the sandbox enforces it, not just the code" は**新しい README が引き写してはいけない一文**。**人間の決定（2026-08-30）: A — 文書を実態に合わせる。**「規律で守っている」は恥ではない —— `validate` は毎回呼ばれ、テストもある。**嘘なのは「OS が」の部分だけだった** | REQ-PLT-003 / [0002](decisions/0002-task-md-read-only.md) | E | **human** | major | done | `docs/discipline-not-the-sandbox` |
| **POL-120** | **`MdoroLog.md` の読み込みと差し替えの間に外部の編集が入ると、その編集が黙って消える。** `preservesAllLines` が見ているのは「**自分が読み込んだスナップショット**と、それに1行挿入した配列」の差だけで、**ディスク上の実体が読み込み後に変わったかを一切見ていない**（mtime も inode もサイズも再確認しない）。窓は数ミリ秒だが、**キューのフラッシュは1行ごとに読み直すので行数分だけ窓が開く。****POL-087 は「配列比較が見ていなかったバイト」、これは「配列比較が見ていない時間」。** 設定画面には注意書きがあるが（REQ-LOG-020）、**README には無い**。**人間の決定（2026-08-30）: A — 直す。****実装は「中身のバイトそのもの」を比べる** —— メタデータ（更新日時・サイズ・inode）では「**1刻みの中の、同じ長さの、その場の保存**」を取りこぼす。**推測ではなくテストで実証済み**（3つを全て保った編集を捕まえる検査があり、**3つが一致していることをテスト自身が assert する**）。競合したら**読み直してやり直す**（上限3回。**REQ-LOG-004 が再読込を命じている以上、失敗にすると条文の動作を1回しか試さないことになる**）。**窓は狭めただけで、なくせない** —— POSIX にファイルの compare-and-swap は無く、勧告ロックは利用者のエディタが要求しない。**コメントにも明記。****旧コードの `fileExists` 分岐も塞がった** —— 読んだ時点で「無い」ファイルが窓の中に現れると、丸ごと潰していた | REQ-LOG-004 / [0002](decisions/0002-task-md-read-only.md) | E | **human** | major | done | `fix/what-changed-under-us` |
| **POL-121** | **`SECURITY.md:24` が示す診断ログの場所が実在しない。** `~/Library/Logs/Mdoro` と書いているが、**サンドボックス有効なので実体は `~/Library/Containers/com.sohta.MdoroMac/Data/Library/Logs/Mdoro/mdoro.log`**（実測: 142,844バイト。`~/Library/Logs/Mdoro` は**この機械に存在しない**）。同じ誤りが [0018](decisions/0018-diagnostic-log-policy.md) §4 にもある。**アプリ本体は正しい**（設定画面が実パスを表示し "Show in Finder" もある）。**誤っているのは文書だけ** | [0018](decisions/0018-diagnostic-log-policy.md) | E | agent | major | open | — |
| **POL-122** | **LAN 上の通信が平文であることが、どの文書にも書かれていない。** `NWParameters.tcp` に TLS を積む経路がコードに無い。同じ LAN の第三者から見えるのは **(1) Markdown のタスク一覧すべて (2) `Task.md` とログフォルダの絶対パス (3) デバイストークンそのもの**。**`SECURITY.md` という名前の文書がこれに触れていない。** README の「Everything happens on your LAN」は、**LAN の中では守られていないことを言っていない**。**人間の決定（2026-08-30）: C — いま書く。TLS は公開後**（POL-113 と同じ層の変更なので一緒に設計する）。`SECURITY.md` に「What the local network can see」節、README に一行 | REQ-SEC-002 / `SECURITY.md` | E | **human** | major | done | `docs/discipline-not-the-sandbox` |
| **POL-123** | **発行したトークンを失効させる経路が存在しない。** `issuedTokens.insert` はあるが **`remove` はコードベース全体に無い。** iPhone の「Mac を削除」は**iPhone の Keychain を消すだけ**で、Mac の `issuedDeviceTokens` はそのまま。**端末を売却・紛失したとき、利用者に止める手段が無い**（`.plist` を手で消すしかない）。**実測: この機械の `issuedDeviceTokens` に3個溜まっている** —— **POL-113 の帰結 (2) が確認された。** そして **(3) は POL-113 の書き方より悪い** —— 「名前がずれていると消し損ねる」ではなく、**名前が一致していても Mac 側は消えない**。**人間の決定（2026-08-30）: A の方向で確定 —— Mac 側に失効 UI を足す。ただし通信まわりは修正が多いので、先にまとめて状況整理する機会を持つ**（POL-113 / 122 / 125 / 127 / 131 / 106 / 107 / 135 / 051 と同じ器で扱う）。**[0040](decisions/0040-identity-is-not-a-name.md) に統合**（2026-08-30）。**個別に直さない** —— POL-113 / 123 / 125 / 127 / 131 は**すべて同じ3箇所**（TXT・Keychain の鍵・Mac の保存形式）に触るため | REQ-SEC-002 / POL-113 | E | **human** | major | **done** | [0040](decisions/0040-identity-is-not-a-name.md)。PR #39 の失効 UI で解消 |
| **POL-124** | **機械に対する副作用が README のどこにも書かれていない。** **セッション実行中、Mac はスリープしない** —— プロセス内ではなく**機械全体のアサーション**で `pmset -g assertions` に出る。**設定で切れない**（`runState == .running` に固定で紐付く）。ログイン項目とグローバルホットキー4種も同様に記載が無い。**「タイマーアプリが何を要求するか」を先に知りたい読者に、一覧が無い** | REQ-PER-006 / [0016](decisions/0016-standard-settings-and-hotkeys.md) | E | agent | major | open | — |
| **POL-125** | **Mac の名前が LAN に広告され、無認証で誰でも取得できる。** Bonjour のサービス名も `/info` の `serverName` も `Host.current().localizedName` —— **個人名を含むことが多い文字列**が同じ LAN の全端末に見える。加えて **`/info` は無認証で `isPairingMode` まで返す** ので、**ペアリング中かどうかが外から観測できる**（6桁コードを試す側にとって、いつ試すべきかの手がかり）。README の Privacy 節は「device names are never written to **the diagnostic log**」とは言うが、**電波に乗ることに触れていない。** `ServerInfo.swift:6-7` のコメントは "carries no state and no settings at all" と言うが、**サーバー名は載っている**。**人間の決定（2026-08-30）: B は単独で今すぐ、A は通信まわりの整理でまとめて。****B の調査で分かったこと: `/info` は iPhone から一度も呼ばれていない**（参照はテストのみ）。**`isPairingMode` を外しても何も壊れない。** ただし **REQ-COM-002（MUST）が「ペアリングモードの有無」を明示的に列挙している**ので条文も直す。**[0040](decisions/0040-identity-is-not-a-name.md) に統合**（2026-08-30）。**個別に直さない** —— POL-113 / 123 / 125 / 127 / 131 は**すべて同じ3箇所**（TXT・Keychain の鍵・Mac の保存形式）に触るため | REQ-SEC-004 / REQ-COM-002 | E | **human** | major | **決定済み** | [0040](decisions/0040-identity-is-not-a-name.md) |
| **POL-126** | **README の「once, and nowhere else」（支援リンク）が事実に反する。** 実体は Mac と iPhone の設定画面に**2箇所**。**コードは [0021](decisions/0021-published-as-oss-named-mdoro.md) のとおりで正しい**（アプリごとに1つ）。誤っているのは README が「the app」と単数で書き、**「リポジトリ全体で1箇所」と読める**こと。**支援リンクの多寡は敏感に読まれる** | REQ-NFR-008 / [0021](decisions/0021-published-as-oss-named-mdoro.md) | E | agent | minor | open | — |
| **POL-127** | **Mac はデバイストークンを平文の UserDefaults に置いている。iPhone 側は同じことを危険として避けている。** `TokenKeychain` のコメントは「UserDefaults に置くとバックアップや設定の書き出しで持ち出せてしまう」と書き Keychain を選んでいるのに、**Mac の `DeviceTokenStore` は平文 plist**（実測3件）。**`SECURITY.md` の「What is stored」表は iPhone の Keychain だけを挙げ、Mac 側にトークンがあることを書いていない**。**人間の決定（2026-08-30）: C — 通信まわりの整理でまとめて。** POL-123 と同じ場所であり、**失効を足すなら置き場所も一度に決めるほうが安全**。**[0040](decisions/0040-identity-is-not-a-name.md) に統合**（2026-08-30）。**個別に直さない** —— POL-113 / 123 / 125 / 127 / 131 は**すべて同じ3箇所**（TXT・Keychain の鍵・Mac の保存形式）に触るため | REQ-SEC-002 / `SECURITY.md` | E | **human** | minor | **done** | [0040](decisions/0040-identity-is-not-a-name.md) |
| **POL-128** | **iPhone が保存する「last state snapshot」の中身が、`SECURITY.md` の説明より広い。** 保存されるのは `StateSnapshot` 全体 —— **`taskFilePath` と `logFolderPath`（Mac の絶対パス）、`task.items`（最大1000件のタスク文言）、`selectedTaskSnapshot`**。置き場所は iOS の UserDefaults で既定でバックアップに含まれる。**同じファイルの `TokenKeychain` が「UserDefaults はバックアップで持ち出される」を理由に Keychain を選んでいるのに、タスク名と絶対パスは UserDefaults に置いている。理由づけが一貫していない**。**人間の決定（2026-08-30）: C — 文書に書くのみ。****やっていること自体は目的に必要**（オフライン表示）。**問題は黙っていること** | `SECURITY.md` / [0018](decisions/0018-diagnostic-log-policy.md) | E | **human** | minor | doing | — |
| **POL-129** | **診断ログのローテーションは旧世代を削除しているが、決定とコメントは「消さない」と言っている。** `DiagnosticLogFile.swift:80-85` が `removeItem(at: previousURL)`。主張側は同ファイル `:4`「Nothing here deletes old lines.」、[0018](decisions/0018-diagnostic-log-policy.md) §2「古い行を削除する処理は持たない」。**0018 の趣旨（部分削除を持たない）は守られているが、字面は「削除しない」で、実際には2世代目が丸ごと消える。****README は正しい**（"capped at 2MB × 2 generations"）。**誤解を招くのはコメントと決定の文言のほう** —— **新しい README を書く人が 0018 を引き写すと README のほうが壊れる**。**人間の決定（2026-08-30）: 文言を書き直す。** 新しい README を書く人が [0018](decisions/0018-diagnostic-log-policy.md) を引き写すと、**README のほうが壊れる** | [0018](decisions/0018-diagnostic-log-policy.md) | E | **human** | minor | doing | — |
| **POL-130** | **macOS の通知本文にタスク名が載り、通知履歴としてアプリの外に残る。** `content.body = "\(taskName)\n…"`。通知センターに残り、画面共有や画面録画に写り、ロック画面のプレビュー設定によっては施錠中でも見える。**診断ログにタスク名を書かないと決めたのと同じ配慮が、通知には効いていない。** 機能としては妥当だが、**README の Privacy 節が診断ログの話しかしていないため、読者は「タスク名はどこにも出ない」と受け取りうる**。**人間の決定（2026-08-30）: C — 文書に書くのみ。** 通知にタスク名が出るのは**機能として妥当**で、消すと通知の価値が落ちる | REQ-NTF-001 / [0018](decisions/0018-diagnostic-log-policy.md) | E | **human** | minor | doing | — |
| **POL-131** | **Keychain の項目に `kSecAttrAccessible` を指定しておらず、コメントが挙げた理由の半分しか満たしていない。** 既定は `WhenUnlocked` で**バックアップに含まれ、別端末へ復元できる**。`...ThisDeviceOnly` なら復元されない。「設定のエクスポートで持ち出される」は防げているが「バックアップで持ち出される」は防げていない。**失効経路が無い（POL-123）ことと合わさると、復元された端末が無期限に接続できる。****確度は「疑い」** —— 既定値は静的に読めるが、復元の実挙動は動かさないと分からない。**人間の決定（2026-08-30）: C — 通信まわりの整理でまとめて**（POL-127 と同じ）。**[0040](decisions/0040-identity-is-not-a-name.md) に統合**（2026-08-30）。**個別に直さない** —— POL-113 / 123 / 125 / 127 / 131 は**すべて同じ3箇所**（TXT・Keychain の鍵・Mac の保存形式）に触るため | REQ-SEC-002 | E | **human** | minor | **決定済み** | [0040](decisions/0040-identity-is-not-a-name.md) |
| **POL-138** | **[0040](decisions/0040-identity-is-not-a-name.md) の実装。** (1) Mac が `id`（UUID）を持ち **TXT に載せる** (2) **名前を1つに統合**（Bonjour / `welcome` / Live Activity が同じ表示名。設定可・既定 `Mdoro`）(3) **サーバーはペアリングが在るときだけ立てる** (4) **接続表示はペアリングが在るときだけ** (5) **Mac のトークンを記録として Keychain へ**（値＋端末名＋発行日時）、iPhone は `ThisDeviceOnly` (6) **失効 UI**（設定に1行＋削除）(7) **`GET /info` を削除** (8) **プロトコル版を上げる** (9) **2台目を検出したら名前の変更を勧める一言**（`serviceRegistrationUpdateHandler`）。**既存のペアリングは1回やり直す**（移行コードは書かない） | [0040](decisions/0040-identity-is-not-a-name.md) | — | agent | **major** | **done** | 3本の PR（#37 / #38 / #39）で完了 |
| **POL-139** | **承認を経たペアリングが、必ず失敗する。利用者が実際に遭遇した症状の原因**（2026-08-30 に発見・確認）。**経路**: iPhone がコード付き `hello` を送る → `verify` が通り、**トークンを発行して `issuedTokens` に積み、`pairing = nil` にする** → 既に別クライアントが接続中なので `.needsUserApproval` を返す（`Pairing.swift:141-148`）→ 利用者が承認 → `resolvePendingApproval` が**同じ `hello`（コード付き・トークン無し）で再認証する**（`MdoroServer.swift:260`）→ **`pairing` は既に `nil` なので `.reject(.pairingModeNotActive)`** → iPhone に **`Start pairing on your Mac`** が出る。**利用者の報告と完全に一致する** —— コード入力後に接続されず、3回試しても変わらず、Mac は `Not connected` のまま。**しかも失敗するたびにトークンが1つ積まれる**（`issuedTokens.append` は拒否の前）—— **軸 E の監査が実測した「トークンが3個」と、利用者が「3回試した」ことが符合する**（因果の証明ではないが、強く整合する）。**トークンを持つ再接続の経路は正常**（`issuedTokens` から引けるため）。**壊れているのは、初回ペアリング中に別クライアントが接続している場合だけ。****POL-138 の1本目の実装役が発見** | REQ-SEC-004 / REQ-SEC-001 | — | agent | **major** | **done** | PR #38 `3e87a73` → PR #39 `c23d331`（replay 廃止）で解消 |
| **POL-140** | **`startServer()` の中で `/info` を畳む順番が変わり、失敗時に古い広告が残る経路ができた。** `feat/identity-and-what-is-stored` で `try await server.start(...)` が `infoServer?.stop()` より先になった。start が throw すると古い `infoServer` は立ったまま、**死んだ ws ポートを指す TXT を広告し続ける**。**現状は到達しない** —— `hasStarted` により `startServer()` は1プロセス1回。ただし `advertise()` の上のコメント（「起動に失敗したら何も広告されていない状態にする」）は `startServer` の中では成り立っていない。**同族（2回目の検証で追加）**: `stop()` が `websocketPortForInfo` を 0 に戻さないため、`stop()` 後に `displayName` が変わると `readvertise()` の guard が残留値で通過し、**リスナー無しの Mac が旧 ws ポートを指す TXT を再広告できる**。これも現状到達不能（`stop()` を呼ぶ本番コードが無い）。**同じ回で `stop()` に `websocketPortForInfo = 0` を足すこと。**検証役の指摘 | REQ-COM-003 | `AppModel.swift` | agent | minor | **done** | PR #38 で2穴とも解消（リスナー1本化・ポートリセット） |
| **POL-141** | **`TestHostTests` のソース走査の窓が構文ではなく文字数。** `AppModel(` で分割した各断片の `prefix(700)`（`notifications:` / `idleSleep:` は 400）を見るため、**窓が呼び出しの終わりを越えて次の呼び出しへ届く**。同じファイルで2つの `AppModel(...)` が窓幅以内に並び、後ろだけが引数を持てば前を見逃す。**現状該当は無く、ミューテーションでは正しく落ちた。**括弧の対応で切るか、呼び出し単位で走査すべき。検証役の指摘 | — | `TestHostTests.swift` | agent | minor | open | — |
| **POL-142** | **改名の再広告だけが失敗したとき、画面の文言が事実より重い。** `readvertise()` の失敗は既存の `Mdoro cannot listen for iPhone connections.` を再利用するが、**この場面では ws リスナーは立ったままで既存接続も生きている** —— 死んだのは広告の立て直しだけ。REQ-ERR-008 の精神（事実を隠さない）に照らしてずれる。条文違反ではない。今回の変更以前からの文言の再利用で、regression ではない。2回目の検証役の指摘 | REQ-ERR-008 | `AppModel.swift` | agent | minor | **done** | PR #38 で前提が消えた —— 改名の再広告は本当にリスナーを畳んで立て直すため、文言は事実と一致するようになった |
| **POL-143** | **iPhone は「Bonjour インスタンス名 + `.local`」でダイヤルしており、PR #37 の merge で main が接続不能になった**（2026-09-02 発見・確認）。`MdoroClient.openConnection` は `NWEndpoint.Host("\(name).local")` を組み立てる。**mDNS ホスト名（実測: `Lychee.local`）とインスタンス名は無関係**で、#37 以前はインスタンス名 = `Host.current().localizedName` ≒ コンピュータ名だったため**偶然一致して動いていた**。既定が `Mdoro` になった今、存在しない `Mdoro.local` へダイヤルする。**直し方**: 発見済みの `result.endpoint`（`.service`）へ直接 `NWConnection` を張る。2本目で広告が ws リスナー自身に載ったため、サービスの解決先ポート＝ws ポートとなり、この形が成立する。**2本目の実装役が発見** | REQ-COM-003 | `MdoroClient.swift` | agent | **blocker** | **done** | PR #38 `3e84ab5`（サービス直結ダイヤル）で解消。実機で接続確認済み（2026-09-02） |
| **POL-144** | **接続中に Mac が改名すると、iPhone は旧名の `.service` エンドポイントを握ったまま再接続ループに入る。** POL-143 の修正でダイヤルは発見済みサービスへの直結になり、**ポート変更には自動追随する**ようになったが、**改名（`displayName` 変更、または mDNSResponder の衝突改名）には追随しない** —— 旧名の登録は消え、解決失敗 → バックオフ再接続の無限ループ。`ClientModel` の自動接続は `found.count == 1 && status == .idle` のときだけ働くので、`reconnecting` の間は新しい発見結果で `target` を差し替えない。復帰にはアプリ再起動か手動選択。**対処案**: `serverId` が一致する発見結果で `target` を更新する（同一性は id にあるのだから、名前が変わっても追える）。旧実装より失敗が決定的になっただけで、regression ではない。**POL-143 の実装役の申し送り。**実機確認（2026-09-02）**: 接続中の改名で即 Reconnecting になり、アプリ再起動で1秒以内にシームレス復帰。予測どおり（再起動が復旧経路として機能する）** | REQ-COM-003 / REQ-COM-004 | `MdoroClient.swift` / `ClientModel.swift` | agent | minor | open | — |
| **POL-145** | **60秒タイムアウトで自動拒否された後も、承認バナーが画面に残り続ける。** タイムアウトは `MdoroServer` 内で完結し（`startApprovalTimeout` → `resolvePendingApproval(approved: false)`）、`AppModel.pendingConnectionRequest` を消す者がいない。接続要求は既に拒否済みなのに、バナー（自ら「Denied automatically after 60 seconds」と書いている）は残り、その後の Allow は `pendingApproval == nil` の guard で**黙って何もしない**。**baseline（`1e9743d`）から同じ構造で、2本目の regression ではない。**2本目の検証役の指摘。**付記**: `c23d331` でタイムアウト拒否が `resolveApproval` callback を通るようになったため、そこで `pendingConnectionRequest = nil` を足せば**1行で直る**構造になっている。**同族の変種**: `readvertise` → `server.start` の fold も `pendingApproval` を cancel するだけでバナーを消さない。同じ1行で閉まる位置 | REQ-SEC-004 | `MdoroServer.swift` / `AppModel.swift` | agent | minor | **done** | PR #39（callback 冒頭の1行 + fold 変種）で解消 |
| **POL-146** | **`resolveApproval` が `connectedClientName = nil` をトークン検証の前に行う（latent・現時点で到達不能）。** 承認後のトークン経路が `.reject(.unknownDeviceToken)` になった場合、server 側は pending を refuse するだけで**既存接続は生きたまま**なのに、Authenticator は「誰も接続していない」と信じる。以後、有効なトークンを持つ任意の端末の hello が **`.needsUserApproval` を経ずに `.accept`** され、既存接続が無断で蹴られる（REQ-SEC-004 違反）。**到達には「質問と回答の間にトークンが消える」経路が要り、それは3本目の失効 UI が作る。****3本目の実装で `connectedClientName = nil` を accept 確定後へ移すこと** —— 失効 UI と同じ便が条件。2本目の再検証役の指摘 | REQ-SEC-004 | `Pairing.swift:183-192` | agent | minor | **done** | PR #39 `8206457`（accept 確定後へ移動）で解消。検証役が4経路の遷移表で確認 |
| **POL-147** | **一度も立っていないサーバーについて `server.stop` が診断ログに残る。** 起動失敗中や identity が読めない Mac で最後の記録を削除すると、`stopServer()` が無条件に走って記録する。状態は壊れないが、ログを読む人が「立っていた」と誤読しうる。`pairingScreenClosed` 経由の既存構造と同型で regression ではない。3本目の検証役の指摘 | REQ-ERR-010 | `AppModel.swift` | agent | minor | open | — |
| **POL-148** | **承認バナーが出ている端末を失効しても、バナーは消えない。**「iPhone B wants to connect」の表示中に B の記録を削除しても、バナーは Allow かタイムアウトまで残る。Allow しても `unknownDeviceToken` で正しく拒否される（POL-146 の修正が受け止める）ので**誤って通ることはない**。消すべきかは利用者体験の判断。3本目の検証役の指摘 | REQ-SEC-004 | `AppModel.swift` | human | minor | open | — |
| **POL-149** | **存在しない要件ID `REQ-TIM-018` をコメントが根拠に引いている。** `MenuBarViews.swift:88`。SPEC の第4章は TIM-016 → 017 → 020 で 018/019 は欠番（全 grep で不在確認済み。`b036c3c` で持ち込まれた）。正しい碇は REQ-TIM-020。**付随の疑い**: 同コメントの「It can be taken back」は、スキップが REQ-LOG-018 で即ログ確定（挿入のみ・取り消し不可）である事実とずれて読める。軸 F 監査 | REQ-TIM-020 / REQ-LOG-018 | `MenuBarViews.swift:88` | agent | minor | open | — |
| **POL-150** | **埋められなかった節番号プレースホルダ「(9.x)」がコメントに残る。** `Pairing.swift:81` が失効画面を「9.x」と指すが、SPEC 第9章に該当節は無い（失効の条文は REQ-SEC-002）。参照先が永遠に見つからない。軸 F 監査 | REQ-SEC-002 | `Pairing.swift:81` | agent | minor | open | — |
| **POL-151** | **コメントの体裁2件（まとめ）。** (1) `LogFormatter.swift:59` の `REQ-LOG-010〜016` —— コード側コメントに残る日本語文字はこの `〜` 1文字だけ。en dash へ。(2) `MenuBarViews.swift:94` の REQ-UIX-007 引用が「1件なら出さないのが条文」と誤読させうる（1件時の扱いは REQ-PRS-013 の領分）。軸 F 監査 | 0032 / REQ-PRS-013 | `LogFormatter.swift` / `MenuBarViews.swift` | agent | cosmetic | open | — |
| **POL-152** | **私生活の写り込み3件（まとめ・軸 I）。** (1) `docs/platform/0007:83` の実測出力に `/Users/sohta`（`~` に置換しても証拠能力は落ちない）。(2) `docs/DEVELOPMENT.md:73` にこのマシン固有のシミュレータ UDID（直下のコマンドは `name=iPhone 17` で足りる）。(3) `IdentityTests.swift:256,285,294,302,321` のフィクスチャが `Soh's iPhone` / `Soh の Mac`（架空名で書ける）。スクリーンショット7枚は目視済み・EXIF/GPS 含め問題なし | — | docs / `IdentityTests.swift` | agent | minor | open | — |
| **POL-153** | **`AGENTS.md` にライセンスへの言及が無い。** 単体で読まれる前提の文書なのに、貢献物が MIT で公開されることを知る導線が無い。`Licensed under MIT (see LICENSE)` の1行で閉じる。軸 J 監査（LICENSE 自体は存在・整合・依存物ゼロ・コピー痕跡なし） | — | `AGENTS.md` | agent | minor | open | — |
| **POL-154** | **ローカルネットワーク許可を OFF にしても、何も起きなかった（実機・2026-09-02）。** Mac にも iPhone にも表示は出ず、タイマー操作も接続も従来どおり機能し、iPhone のタスクキル→再起動でも変化なし。**これは「検出の失敗」ではなく「拒否がまだ効いていない」可能性が高い** —— macOS/iOS のローカルネットワーク拒否は既存の接続・既存の登録には即時には効かず、新しい browse / 登録に効くと考えられる（未検証）。**未実施の決定的なテスト**: 許可 OFF のまま **Mac アプリを再起動**する。REQ-COM-003 の「立てない」経路と REQ-ERR-008 の文言が実際に画面に出るかは、これで初めて分かる。`docs/PLATFORM.md` に「OFF が既存状態に効く時点」の項目は無い（REQ-PLT-008 は検出 API のみ）。実機確認の報告より | REQ-ERR-008 / REQ-ERR-014 / REQ-PLT-008 | — | human | minor | **done** | 決定的テスト実施（2026-09-02）: 許可 OFF + Mac 再起動 → 不可視・無表示。**欠陥として POL-164 に引き継ぎ**、プラットフォームの事実は `platform/0009` に記録 |
| **POL-155** | **README のビルド手順が、DEVELOPMENT.md が禁じた操作そのものを指示している。** `README.md:121-122` は「Signing & Capabilities で Team を選べ」—— `docs/DEVELOPMENT.md:97-99` が「選ぶな（pbxproj に書き戻されて xcconfig より優先される）」と禁じた操作。2026-08-29 に xcconfig 方式へ移した理由が、README から入った貢献者の最初の PR で再発する。xcconfig 方式（`Signing.local.xcconfig`）に書き換えること。軸 H 監査 | — | `README.md` | agent | **major** | open | — |
| **POL-156** | **文書化された全ビルドコマンドが `xcbeautify` を前提にしているが、導入手順がどこにもない。** `DEVELOPMENT.md:68,80` / `AGENTS.md:48,54`。初回 clone の機体には無い第三者ツールで、`set -o pipefail` 付きなので `command not found` でパイプライン全体が失敗する。前提として1行書くか、任意と明記する。軸 H 監査 | — | `DEVELOPMENT.md` / `AGENTS.md` | agent | **major** | open | — |
| **POL-157** | **署名チーム未設定だと `MdoroMac` のテストが1件も走らずに落ちる（実測・2回再現）。** `DEVELOPMENT_TEAM=` で `xcodebuild test` → `Early unexpected exit ... while preparing to run tests`（exit 65）。ビルドは通る（AGENTS.md の「Without a team the apps still build and run locally」はビルドについては真）。iOS のテストはチーム無しで15件通るので Mac のテストホストだけの問題。ad-hoc 署名とテストホスト起動の相互作用と推定。**正規署名済みの MdoroMac が居る機体での実測なので、クリーン環境では挙動が違う可能性が残る**（human: 別アカウント/機体での再現確認）。軸 H 監査 | — | `PomodoroMac.xcodeproj` | agent+human | **major** | open | — |
| **POL-158** | **Mac 44件・iOS 15件のテストが、外部の貢献者から見えない。** DEVELOPMENT.md も AGENTS.md も CI も `swift test`（core）しか語らず、app ターゲットのテストを壊しても文書どおりの手順と CI の両方を素通りする。文書に1行足すのは agent、**CI に macOS ビルド+テストを足すかは human の判断**（macOS 26 ランナーのコスト）。軸 H 監査 | — | `DEVELOPMENT.md` / `AGENTS.md` / `.github/workflows/tests.yml` | agent+human | **major** | open | — |
| **POL-159** | **CI の `runs-on: macos-latest` が版数固定されていない。** 現時点では通っている（2026-09-02 に直近5 run の成功を確認 —— `latest` は macOS 26 を満たす）。ただし `latest` の指す先が変わった日に、全 PR が変更内容と無関係に落ちる/通る。版数指定への固定を検討。軸 H 監査 | — | `.github/workflows/tests.yml:13` | agent | minor | open | — |
| **POL-160** | **`.gitignore:25` の再生成コマンドが存在しない scheme 名 `PomodoroMac` を指す**（実在は `MdoroMac`。0024 の改名の反映漏れ）。軸 H 監査 | — | `.gitignore` | agent | minor | open | — |
| **POL-161** | **`DEVELOPMENT.md:23` の構成図が git 管理外の `buildServer.json` を無注記で載せている。** 初回 clone に存在せず、生成が要ること・任意であることが手順書から読めない。軸 H 監査 | — | `DEVELOPMENT.md` | agent | minor | open | — |
| **POL-162** | **README が「A free Apple ID works」と勧めながら、Personal Team では集中モード中に通知が届かない事実（REQ-NTF-005・実機確認済み）を書いていない。** 集中セッションのタイマーにとって、集中モード中こそ通知が要る場面。README の Requirements/Building 節に1行。軸 H 監査 | REQ-NTF-005 | `README.md` | agent | minor | open | — |
| **POL-163** | **`Tools/make_icon.swift` の私的 API（`_NSSVGImageRep`）依存が DEVELOPMENT.md から読めない。** 「外部ツールは要らない」とだけあり、将来の macOS で黙って壊れる可能性がスクリプト内コメントにしか無い。過去走査の表に同趣旨の記載があるが POL 番号は無かった（重複なら統合してよい）。軸 H 監査 | — | `DEVELOPMENT.md` / `Tools/make_icon.swift` | agent | cosmetic | open | — |
| **POL-164** | **ローカルネットワーク許可を拒否された Mac は、電波に出られないのに黙っている（実機確認・2026-09-02）。** 許可 OFF のまま再起動すると iPhone から見えなくなるが、**Mac にはエラーが1文字も出ない。** リスナーの bind は LAN 許可と無関係に成功するため、既存の失敗経路（bind 失敗 → `serverStartError`）を通らない。広告だけが黙って不可視になる。Decision 0035「失敗には届き先が要る」/ REQ-ERR-008 に反する。**検出手段の調査が先** —— macOS 側で広告の拒否を知る API があるか（`docs/platform/0009` §(b)。REQ-PLT-008 は iPhone 側の検出しか押さえていない）。検出できないなら「許可設定を確認せよ」の常設文言など次善策の判断が要る。実機確認の報告より | REQ-ERR-008 / REQ-PLT-008 | `AppModel.swift` / `MdoroServer.swift` | agent | **major** | open | — |
| **POL-165** | **コメントが `POL-nnn` を恒久の根拠に引く慣行をやめる（裁定・2026-09-02）。** 「PUNCHLIST は参照対象として相応しくない」—— 流動的な運用文書であり、外部貢献者は読まない前提（AGENTS.md 分離）。**全 `POL-nnn` コメント参照を REQ か `docs/decisions/` の碇に付け替える**（`AppModel.swift` の POL-034/114、`MdoroServer.swift` の POL-054/114、`Pairing.swift` の POL-139/146、`MdoroClient.swift` の POL-047/143 ほか）。commit メッセージの POL 参照は歴史の記録なので対象外。CLAUDE.md にも規律として1行記載済み。軸 F 監査 → 人間の裁定 | — | 全 Swift | agent | minor | open | — |
| **POL-166** | **裁定の記録（2026-09-02）: docs が日本語であることは公開して問題ない。**「作者は日本語話者である」という属性が伝わることは、**透明性のために譲る**と人間が決定。軸 I の監査が挙げた論点はこれで閉じた。作業は発生しない | — | — | human | — | **done** | 裁定のみ |
| **POL-167** | **「以前はこうだった」型の履歴コメントを「制約形」に書き換える（裁定・2026-09-02）。** 歴史の語り（This was... / used to...）を落とし、**現在形の不変条件 + 根拠（REQ / decisions/）**へ。実例が本質的な場合はコメントで語らず Decision Record を指す。代表例: `Pairing.swift:57-60,157-161` / `MdoroServer.swift:72-76` / `MdoroClient.swift:105-108` / `ClientModel.swift:159` ほか多数。**POL-165（POL 参照の付け替え）と同じスイープで行う**（触るファイルがほぼ同じ） | 0032 | 全 Swift | agent | minor | open | — |
| **POL-168** | **テストフィクスチャを多言語混成にする（裁定・2026-09-02）。**「開発言語を除き、英語以外は全て同列」という言語方針に対し、現状のフィクスチャは非英語サンプルが全部日本語で、日本語を特別視する形になっている。日本語・アクセント付きラテン・ハングル/中文・絵文字・RTL を混ぜ、コメントは「arbitrary user languages」と英語で書く。**マルチバイト・結合文字・RTL は壊れ方が違うので検証としても純増。**英語化は検証能力を落とすため却下済み。`LogTests` / `TaskParserTests` ほか約200行。POL-152(3)（`Soh の Mac`）もこのスイープで架空名に | REQ-TSK-010〜016 | テスト各所 | agent | minor | open | — |
| **POL-132** | **README のビルド手順が、`DEVELOPMENT.md` と `AGENTS.md` が禁じている操作を指示している。** README は「Select your team under Signing & Capabilities」と書くが、`DEVELOPMENT.md:97` は「**Xcode の Signing & Capabilities で Team を選ばないこと**」。従うと `DEVELOPMENT_TEAM` がターゲット側に書き戻され、**`project.pbxproj` に差分が出る**（[0013](decisions/0013-pbxproj-is-owned-by-xcode.md) が記録した問題の再発）。**README しか読まない貢献者は最初の PR で無関係な差分を持ってくる。****仕組みは既に整っていて、README だけが古い** | [0013](decisions/0013-pbxproj-is-owned-by-xcode.md) | E / H | agent | minor | open | — |
| **POL-133** | **ログの一時ファイルが利用者のフォルダに現れ、異常終了時は残る。** 書き込みのたびに `<ログフォルダ>/.MdoroLog.md.<UUID>.tmp` が作られる。正常系では rename で消え、失敗時も `try?` で削除するが、**その削除自体が失敗した場合とプロセスが落ちた場合は残留する。** ドット始まりなので Obsidian の一覧には出ないが、**利用者の Vault の中に見慣れないファイルが増える。****README は「a log file next to it」としか書いておらず、一時ファイルに触れていない。** 起動時に孤児を掃除する処理は無い。**人間の決定（2026-08-30）: A — 起動時に孤児を掃除する。** 原文の理由: **「わきまえた振る舞いに反する」** —— `CONTEXT.md` §1 の「弁える」を判断基準として使ったもの | REQ-LOG-004 / REQ-PLT-004 | E | **human** | minor | doing | — |
| **POL-134** | **メニューバーだけで使う利用者に、ログ保存先の未設定が見えない。** REQ-LOG-002 は「画面に示すこと」を要求し、POL-118 の修正はメインウィンドウと設定画面に出したが、**メニューバーには出していない。** REQ-UIX-001（メインウィンドウがすべての機能を提供する）に照らせば足りるが、**メニューバーだけで使う利用者には届かない。** REQ-UIX-030〜032 の表示密度に触る。**人間の決定（2026-08-30）: メニューバーにも iPhone にも出さない。README に書く。**原文の理由: **「これは頻繁に触る操作としては想定されていないので、メニューバーに表示すべき機能ではありません。記録を取る機能は補助的なものであり、iPhone 連携やタイマー操作、task 選択と比べて優先度は一段下がります」。****代わりに README へ「初期状態では保存先が決まっていない。記録が欲しい人は設定画面から設定する」と明記する**（工程15 の入力） | REQ-LOG-002 / REQ-UIX-031 | E | **human** | minor | **決定済み** | — |
| **POL-135** | **iPhone が「Mac が何も記録していない」ことを知る手段が無い。** ログの保存先は Mac 側の設定で、`ProtocolErrorCode.logWriteFailed` は**コマンド応答用で状態スナップショットには乗らない。** 仕様上そもそも配られない値である。**利用者から見ると、iPhone だけを見ている間は記録されていないことに気づけない**。**人間の決定（2026-08-30）: メニューバーにも iPhone にも出さない。README に書く。**原文の理由: **「これは頻繁に触る操作としては想定されていないので、メニューバーに表示すべき機能ではありません。記録を取る機能は補助的なものであり、iPhone 連携やタイマー操作、task 選択と比べて優先度は一段下がります」。****代わりに README へ「初期状態では保存先が決まっていない。記録が欲しい人は設定画面から設定する」と明記する**（工程15 の入力） | REQ-LOG-002 / 10.2 | E | **human** | minor | **決定済み** | — |
| **POL-136** | **`writeStartupDiagnostics()` を `start()` から呼ぶのをやめても、テストは通ってしまう。** `start()` はサーバーと Bonjour 登録を上げるためテストから呼べず、テストは `writeStartupDiagnostics()` を直接叩いている。**配線が切れても誰も気づかない。** 塞ぐなら `RepositorySources` による走査になるが、**実装役は「大げさ」と判断して入れていない** | POL-118 | F | agent | minor | open | — |
| **POL-137** | **ブックマーク解決の失敗が REQ-ERR-004 の3回カウントに入らない。** `flushLogQueue` の catch 節に落ちるため `logWriteFailed` は立つが、`LogWriteQueue.flush` を通らないので**失敗として数えられない。****保存先フォルダが消えた場合、画面には出続けるのに通知は永遠に出ない。** 既存の挙動で POL-118 が作ったものではないが、**[0039](decisions/0039-failures-that-come-and-go-still-count.md) の「飛び飛びの失敗を見逃さない」と同じ性質** | REQ-ERR-004 / [0039](decisions/0039-failures-that-come-and-go-still-count.md) | — | **human** | minor | **決定済み** | **裁定（2026-09-02）**: ブックマーク解決の失敗も REQ-ERR-004 のカウントに入れる。条文はそのまま。0039 の「飛び飛びの失敗を見逃さない」と同じ向き |
| **POL-015** | REQ-ERR-014 が OS 設定画面のパスを日本語で規定。英語化すると日本語ロケールの利用者の画面と一致しない。REQ-SEC-005 とも粒度が食い違う | REQ-ERR-014 / REQ-SEC-005 / 0.12節 | C | human | minor | done | `docs/spec-v2.10` |
| **POL-021** | 非スコープの「複数ユーザー対応」が、人の話か端末の話か読めない。第14章「1対1接続」は端末の話 | [0021](decisions/0021-published-as-oss-named-mdoro.md) / 第14章 | D | agent | minor | done | `docs/spec-v2.10` |
| **POL-022** | 「ユーザー」約30件 / 「利用者」約11件が混在。**一括置換は禁止**（macOS のユーザーアカウント等3件は対象外） | [0021](decisions/0021-published-as-oss-named-mdoro.md) / REQ-UIX-042 | D | agent | minor | done | `fix/final-audit-items` |
| **POL-023** | REQ-PLT-009 が製品要件と**検証手順**を1条文に混ぜている。前者は利用者、後者は貢献者に宛てられており宛先が違う | `CLAUDE.md`（手順は DEVELOPMENT.md） | — | agent | minor | done | `docs/spec-v2.10` |

## 付録: 実装から回収した語（POL-013 の入力）

**2026-08-28、repo-auditor 軸 C がコードから回収。** 第16章の表記欄はこれを正とする。

| 概念 | 実際の英語表記 | 出どころ |
| :---- | :---- | :---- |
| 集中表示ビュー | **画面に表題はない。** 遷移ボタンのラベルだけが `Full Screen` | `MainScreen.swift:57` |
| 周回 | 画面 `1 / 4`（**語を添えない**）/ 読み上げ `Loop 1 of 4` / ログ `Loop 1/4` / Live Activity コンパクト `1/4` | `SessionHeaderView.swift:35,38` ほか |
| 一時停止 / 再開 | ボタン `Pause` / `Resume`、状態表示 `Paused` | `MainWindowView.swift:110,115` |
| 有効なプリセット | ラベルは `Preset`。値は `名前 (25 / 5 / 15)` | `PresetBarView.swift:14` |
| 中断 | ボタン `Stop`、メニューバーは `Stop…` → `Confirm stop`、ログ `⏹ Stopped`、復帰確認 `Record as stopped` | `MainWindowView.swift:113` ほか |
| 予告通知 | 設定 `Heads-up (n / 2)`、**通知本文は `Ending soon` / `About N min left`** | `PresetEditorView.swift:152` |
| 未分類 | `(Uncategorized)`（半角括弧） | `TaskParser.swift:14` |
| 既定プリセット | `Standard` | `Preset.swift:85` |
| 通知音 | UI `Default` / `Glass` / `Submarine` / `Pop` / `Silent`、raw `default` / `chime` / `bell` / `wood` / `silent` | `Preset.swift:6-32` |

## 付録: 軸 K の洗い出し（POL-058 の出力・2026-08-29）

`platform-researcher` が `docs/SPEC.md`（v2.18）/ `docs/CONTEXT.md` §2 / `docs/PLATFORM.md` の `未検証` を通読し、
**プラットフォームの事実として書かれている主張を分類したもの。列挙であって調査ではない。一次情報には当たっていない。**
`根拠なし` は「**文書に根拠がない**」であって「誤っている」ではない。

**`docs/` 全体で `developer.apple.com` / `WWDC` を含む行は `docs/platform/` 配下にしか存在しない。**
`SPEC.md`・`CONTEXT.md`・`decisions/` が持つ一次情報への参照はゼロ。唯一の例外が REQ-UIX-027 で、
これは POL-057 の後始末として `PLATFORM.md` 経由で [platform/0001](platform/0001-live-activity-lock-screen-background.md) を指している。

### 区分ごとの件数

| 区分 | `SPEC.md` | `CONTEXT.md` §2 | `PLATFORM.md` 未検証 | 計 | （参考）`CONTEXT.md` §6 |
| :-- | --: | --: | --: | --: | --: |
| **出典あり** | **1** | 0 | 0 | **1** | 0 |
| **実測の記録あり** | 3 | 7 | 1 | **11** | 3 |
| **実測の主張のみ** | 2 | 5 | 1 | **8** | 0 |
| **根拠なし** | 38 | 3 | 5 | **46** | 1 |
| **事実ではない**（設計判断・運用規律） | 2 | 11 | 2 | **15** | 2 |
| 計 | 46 | 26 | 9 | **81** | 6 |

**出典があるのは REQ-UIX-027 の1件だけ。それは POL-057 で壊れた条文を直した結果であり、**
**壊れる前に出典があった条文は1つもない。**

**`実測の記録あり` 11件のうち、独立に再現された記述は1件もない（すべて n=1）。**
**`根拠なし` 46件のうち、記述自身が OS バージョンを特定しているのは4件だけ**
（ATS の「iOS 17 / macOS 14 以降」、`NSLocalNetworkUsageDescription` の「macOS 15 以降」、
ActivityKit の「iOS 16.1+」、「Xcode 26.3 以降」）。**残り42件は、どの OS についての記述なのかが読み取れない。**

### `docs/SPEC.md`

| 場所 | 主張の要約 | 区分 |
| :-- | :---- | :-- |
| `:73` 0.2 | ActivityKit は iOS 16.1+ | 根拠なし |
| `:364` 1.3 | macOS 15 でローカルネットワークプライバシーが導入された | 根拠なし |
| `:365` 1.3 | Apple が Network.framework を Bonjour+WebSocket の推奨構成としている | 根拠なし |
| `:366` 1.3 | 無償 Personal Team は7日ごとの再署名 / Live Activity は App ID をもう1つ消費する | 根拠なし |
| `:368` 1.3 | 事前スケジュール通知・Live Activity・スリープ抑止・メニューバー常駐はネイティブでしか実現できない | 根拠なし |
| `:461` REQ-COM-014 **MUST** | `DateComponents.timeZone` 未指定だと TZ 変更・DST で発火時刻がずれる | 根拠なし |
| `:483` 3.5 | ATS は IP 直接接続を既定で拒否（iOS 17 / macOS 14 以降）/ DHCP では `NSExceptionDomains` 回避不可 | 根拠なし |
| `:484` 3.5 | `NSBonjourServices` 未列挙だと探索が失敗する | 根拠なし |
| `:485` 3.5 | `NSLocalNetworkUsageDescription` は macOS も 15 以降必要。登録側にも許可が要る | 根拠なし |
| `:486` 3.5 | `NSSupportsLiveActivities = YES` が要る | 根拠なし |
| `:492-494` 3.5 | entitlement 3件がそれぞれの理由で要る | 根拠なし |
| `:499` REQ-PLT-002 **MUST** | Network.framework は登録・探索・接続を同一 FW で扱える | 根拠なし |
| `:500` REQ-PLT-003 **MUST** | `securityScopeAllowOnlyReadAccess` が書き込み禁止を OS レベルで担保する | 根拠なし |
| `:501` REQ-PLT-004 **MUST** | サンドボックス外を跨ぐ `rename` は失敗する | 根拠なし（実測は `CONTEXT.md` 側・日付なし） |
| `:502` REQ-PLT-005 **MUST** | `startAccessing…` / `stopAccessing…` は対で呼ぶ必要がある | 根拠なし |
| `:503` REQ-PLT-006 **MUST** | エディタは一時ファイル経由で置換する。記述子監視は inode 差し替えで無効化される | 実測の主張のみ（日付・版なし） |
| `:504` REQ-PLT-007 **MUST** | バックグラウンドで未決定のまま操作すると、ダイアログが出ないまま黙って拒否される | 根拠なし |
| `:505` REQ-PLT-008 **MUST** | 許可状態を問い合わせる API は**存在しない** / `-65570` / `.localNetworkDenied` | 根拠なし（→ POL-063） |
| `:506` REQ-PLT-009 | ad-hoc 署名では許可の同一性が保たれない / macOS では許可を未決定へ戻せない | 根拠なし |
| `:647` REQ-NTF-005 | 無償 Personal Team では `.timeSensitive` でも集中モード中に届かない | 実測の記録あり（2026-08-27・OS 版なし。因果は未検証） |
| `:648` REQ-NTF-006 | iOS にはシステムサウンドを名前で指す手段が無い | 実測の主張のみ（日付なし） |
| `:649` REQ-NTF-007 | 触覚のみの提示はロック中に実現できない | 根拠なし |
| `:656` 5.1 | ロック中・バックグラウンドでは WebSocket は OS によって停止される | 根拠なし（REQ-NTF-002 **MUST** の全根拠） |
| `:678` REQ-TSK-002 **MUST** | 監視は `DispatchSource` / FSEvents で行う | 事実ではない（手段の選択） |
| `:806` 8.2 | 純正 StandBy には任意アプリの常時全画面表示ができない | 根拠なし（集中表示ビューの出発点） |
| `:812` REQ-UIX-012 **MUST** | `isIdleTimerDisabled` で自動ロックを抑止でき、BG 移行時は解除が要る | 根拠なし |
| `:818` 8.3 | **(a) Live Activity はフォアグラウンドでしか開始できない (b) 更新も running の間だけ。BG 移行後まもなく suspend し WebSocket も切れる** | **根拠なし**（「Apple 公式で確認済み」の主張のみ・→ POL-060） |
| `:823` REQ-UIX-021 **MUST** | `Text(timerInterval:…)` はシステム側が自律的に更新する | 根拠なし |
| `:826` REQ-UIX-023 **MUST** | `staleDate` は「次に状態を確認できる保証がない時刻」である | 根拠なし（API の意味の解釈） |
| `:826` REQ-UIX-023 **MUST** | `isStale` の切り替わりは OS が決め、期限どおりでない | 実測の記録あり（`CONTEXT.md` 側・2026-08-27・n=1） |
| `:827` REQ-UIX-024 | `LiveActivityIntent.perform()` はアプリ本体のプロセスで走る / suspend で WebSocket は切れる | 根拠なし（後半は `:818` に依存） |
| `:828` REQ-UIX-025 **MUST** | 動的データは 4KB 以内 | 根拠なし（→ POL-064） |
| `:829` REQ-UIX-026 **MUST** | Live Activity 拡張からのネットワークアクセスは**サンドボックス上不可能** | 根拠なし（→ POL-063） |
| `:830` REQ-UIX-027 **MUST** | ロック画面の器の背景 / 前景色 / Always-On / DI の地 | **出典あり**（[platform/0001](platform/0001-live-activity-lock-screen-background.md)・**全体で唯一**） |
| `:831` REQ-UIX-028 **MUST** | 継続時間はアクティブ8時間 / 残留含め最大12時間 | 根拠なし（→ POL-064） |
| `:843` REQ-UIX-035 **MUST** | iPhone は背面に回れば接続が切れる（「3.5 のプラットフォーム制約」と参照） | 根拠なし＋**参照先が誤り**（→ POL-068） |
| `:1028` REQ-COL-022 **MUST** | メニューバーの地は可変であり、コントラストを保証できない | **根拠なし**（→ POL-061） |
| `:1029` REQ-COL-023 | 「コントラストを上げる」「透明度を下げる」設定に応答できる | 根拠なし（API 名の記載もなし） |
| `:1050` 8.6.1 | 残り時間は SF Rounded / medium / 等幅数字 | 事実ではない（設計判断） |
| `:1059` REQ-UIX-041 **MUST** | Live Activity とメニューバーは高さが固定で、字が伸びれば行が落ちる | 根拠なし |
| `:1209` REQ-CFG-004 **MUST** | ブックマークで再起動後もアクセス権を維持できる / `bookmarkDataIsStale` で再生成 | 根拠なし |
| `:1445` REQ-PER-006 | `ProcessInfo.beginActivity` でアイドルスリープを抑止できる。蓋・電源設定によるスリープは抑止できない | 根拠なし |
| `:1467` REQ-ERR-014 **MUST** | OS の設定画面パスは macOS/iOS ともに `… > Privacy & Security > Local Network` | 根拠なし（OS 版に依存する UI 文言） |
| `:1475` REQ-ERR-010 | `localizedDescription` はロケールで言語が変わり、ファイル名を含むことが多い | 根拠なし（[0034](decisions/0034-os-errors-are-recorded-as-codes.md) の判断根拠） |
| `:1501` 第14章 | 実機インストールには Developer Program か無料プロファイル（7日ごと再署名）が要る | 根拠なし |
| `:1501` 第14章 | 無償枠では Time Sensitive 通知が利用できない | 実測の記録あり（2026-08-27・REQ-NTF-005 と同一の観測） |

### `docs/CONTEXT.md` §2

**見出しは「6箇所」だが、実体は番号つき6項目＋小節19本。拾える主張は26件。**

| 場所 | 主張の要約 | 区分 |
| :-- | :---- | :-- |
| `:60` `:65` `:70` `:75` `:77` `:80` | 番号つき6項目（`committedAt` の冪等性、`nextSessionType`、遷移マトリクス、`FINISHED`、タスク名のスナップショット、設定変更） | すべて**事実ではない**（設計判断） |
| `:83` | ビューに `Timer.publish` を張ると発火せず表示が固まる | 実測の主張のみ（→ POL-066） |
| `:90` | ファイル単位ブックマークでは同一フォルダに一時ファイルを作れない | 実測の主張のみ（日付・OS なし） |
| `:98` | 拡張の deployment target が端末の iOS より新しいと、登録が黙って拒否される | 実測の記録あり（条件は明記・日付なし） |
| `:109` | 失敗を `try?` で握り潰さない | 事実ではない（運用規律） |
| `:120` | `xcodebuild … CODE_SIGNING_ALLOWED=NO` は既定の DerivedData へ書く | 実測の記録あり（2026-08-27・Xcode 版なし） |
| `:129` | `requestAuthorization` は ad-hoc 署名で失敗する / `add()` は成功に見えて配信されない | 実測の主張のみ。**「再調査しない」と明記されているのに日付も OS も手順もない** |
| `:138` | 前面にいる間は `willPresent` が無いと通知が出ない | 実測の記録あり（2026-08-27。**観測は Mac 1件で「iOS も」は一般化**） |
| `:147` | 通知音が鳴らない原因は OS 設定側にもありうる / `notificationSettings()` で読める | 根拠なし |
| `:150` | `Text(timerInterval:)` に `.fixedSize()` を付けるとレイアウトが破綻する | 実測の記録あり（2026-08-27） |
| `:159` | **ロック画面の Live Activity は高さが固定で、入らない行は黙って消える** | **根拠なし**（行の優先順位＝REQ-UIX-023 **MUST** がこの上に乗る） |
| `:166` | 未接続中のスナップショットを Live Activity へ流さない | 事実ではない（設計判断） |
| `:181` `:185` | Live Activity はプロセス終了後も残る / `Activity.activities` で拾い直す / **`end()` は OS 上にあるものを全部畳む** | **根拠なし**。末尾は API の意味と食い違う疑い（→ POL-065） |
| `:187` | ナビゲーションバーと標準コントロールは OS の外観設定に従う | 実測の記録あり（2026-08-27・条件記載あり） |
| `:199` | `isStale` の切り替わりは OS の都合で遅れる（90秒に対し4分後） | 実測の記録あり（2026-08-27・n=1・OS 版なし） |
| `:210` | `staleDate` は「保証の期限」であって経過時間ではない | 観測は実測の記録あり / **意味の解釈は根拠なし** |
| `:218` | `NWListener`/`NWConnection` のハンドラから `MainActor.assumeIsolated` を呼ぶとトラップする | 実測の主張のみ（日付なし） |
| `:225` | 存在しない SF Symbol 名 / アセット名は、エラーにならず何も描かれない | 実測の主張のみ（実例あり・日付なし） |
| `:236` `:244` `:251` | タスク名の使い分け / 色の5役 / 仕様書変更時の確認 | すべて**事実ではない**（設計判断・運用規律） |

**同種の記述が §6 にも6件ある**（`:596` `List(selection:)` と `.tint` ／ `:613` 内容が窓より高いと上を切る ／
`:618` `perform()` はアプリ本体で走る・`ActivityConfiguration` は `dynamicIsland:` 必須（**根拠なし・参照切れ**）／
`:631` 展開 DI の `.center` ／ `:645` 接続記号の向き ／ `:654` 拡張に登録してよいのは Live Activity だけ）。

### `docs/PLATFORM.md` の `未検証`

| # | 主張の要約 | 区分 |
| :-- | :---- | :-- |
| 1 | Live Activity はフォアグラウンドでしか開始できず、更新も running の間だけ | 根拠なし。**`SPEC.md:818` は同じ内容を「Apple 公式で確認済み」と書いており、両者が矛盾** |
| 2 | 通知を WebSocket に依存させず絶対時刻で事前スケジュールする | **事実ではない**（REQ-NTF-002 そのもの・→ POL-069） |
| 3 | ATS は IP 直接接続を既定で拒否。`NSAllowsLocalNetworking` 必須 | 根拠なし |
| 4 | 許可状態を問い合わせる API はない / `-65570` / 初回はフォアグラウンド | 根拠なし |
| 5 | 原子的書き込みは同一ディレクトリ内で `FileManager.replaceItemAt` を使う | 一部**事実ではない**（→ POL-069） |
| 6 | ファイル監視は親ディレクトリに張る / エディタは一時ファイル経由で保存する | 前半は事実ではない / 後半は実測の主張のみ |
| 7 | Xcode 26.3 以降には MCP サーバーがある（`xcrun mcpbridge`） | 根拠なし。**どの条文も依拠していない**（→ POL-069） |
| 8 | `MenuBarExtra` のラベルを毎秒更新しても安定する | **実測の記録あり**（2026-08-26 / Debug / 3時間 / CPU 0.1〜0.4% / RSS 増加なし / macOS 26。**全81項目で最も記録が整っている**） |
| 9 | 無償 Personal Team / 実機アプリは7日で失効 / Push・iCloud 不可 | 根拠なし |

### 洗い出しが確かめていないこと

1. **各主張の真偽。** 一次情報に当たっていない。**REQ-UIX-027 の例があるので、正しい確率も誤りの確率もどちらも決めつけていない**
2. **実測の再現性。** `実測の記録あり` はすべて n=1
3. **コード側。** `MdoroWidgetLiveActivity.swift` のように**条文と同じ誤前提をコードが引いている例**が [platform/0001](platform/0001-live-activity-lock-screen-background.md) で見つかっているが、**同種のものがコード中に他にあるかは見ていない**（→ POL-071）
4. **`AGENTS.md` と `docs/DEVELOPMENT.md`。** 対象外とした（→ POL-071）

---

## 付録: 軸 K のコード側走査（POL-071 の出力・2026-08-29）

`repo-auditor` が `Packages/MdoroCore/`（Sources 27本・Tests 21本）、`PomodoroMac/`（Mac 18本・iOS 10本・
Widget 2本・テスト5本）、`AGENTS.md`、`docs/DEVELOPMENT.md` を通読し、
**「Apple / iOS / macOS / Xcode がどう振る舞うか」を述べている記述**を分類したもの。**読み取りのみ。**

| 区分 | 件数 |
| :-- | --: |
| **既知の誤り**（調査で誤りと判明した前提を引いている） | **8** |
| **条文にない主張**（コードが独自に事実を主張。`PLATFORM.md` に項目が無い） | **26** |
| 条文と一致（条文自体の正しさは別問題） | 19 |
| 出典あり | 2 |
| 事実ではない（設計判断・自分の実装の説明） | 6 |

### 既知の誤り 8件（→ POL-059）

| # | 場所 | 記述 | 何が誤りか |
| :-- | :---- | :---- | :---- |
| K-1 | `PomodoroWidget/MdoroWidgetLiveActivity.swift:13` | `// REQ-UIX-027: 背景は壁紙なので…` | [0001](platform/0001-live-activity-lock-screen-background.md)。条文は v2.18 で訂正済み |
| K-2 | `MdoroCoreTests/ColorLiteralTests.swift:39-45` | "it is drawn over the reader's wallpaper" | 同上。**POL-059 は当初 widget の1件しか挙げていなかった** |
| K-3 | `MdoroCoreTests/ColorLiteralTests.swift:159-161` | "because it draws on the reader's wallpaper" | 同上。**「除外の理由を将来もう一度読ませる」テストに付いており、誤った理由が再読させる位置に固定されている** |
| K-4 | `MdoroCore/MenuBarMark.swift:4` | `// 色が使えないので状態は形だけで示す。` | [0003](platform/0003-menu-bar-ground-and-status-item-color.md)。**色は使える。**条文は v2.19 で訂正済み |
| K-5 | `PomodoroMac/Views/MenuBarViews.swift:5` | `// 地の明るさが変わりコントラストを保証できない。` | 同上。**SDK は逆に "This guarantees…" と明記。処方は正しいまま、理由だけが誤り** |
| K-6 | `PomodoroiOS/Client/NotificationScheduler.swift:6` | `// ロック中・背面では WebSocket が OS に止められるため…` | [0002](platform/0002-live-activity-background-start-and-suspend.md)。**誤りが2つ重なる** — 「ロック中」は条件名が違い、「WebSocket が切れる」は**不明**。v2.19 は根拠を「suspend 中はコードが走らない」に差し替え済み |
| K-7 | `PomodoroiOS/Client/LiveActivityController.swift:8-9` | `// 開始できるのはフォアグラウンドにある間だけ` / `// MUST に戻す実装を書かないこと。` | 同上。**留保が落ちている**うえ、**「MUST に戻すな」の根拠が、訂正された側の (a) に置かれている** |
| K-8 | `LiveActivityController.swift:81,152` / `PomodoroiOS/ClientModel.swift:42` | `// REQ-UIX-020: フォアグラウンドでないと開始できない。` ×3 | 同上（`MdoroiOSApp.swift:25` だけは留保付きで問題ない） |

### 条文にない主張 26件（→ POL-074）

**うち9件は `CONTEXT.md` §2 / §6 に実測の記録がある。残り17件は根拠がない。**

| 分類 | 件数 | 主なもの |
| :-- | --: | :---- |
| ダイナミックアイランドの寸法 | 5 | 端の2領域が外周まで届く／`.center` が幅を全部取る（§6 に実測）／高さが固定で行が消える／`.padding()` の 16 が二重になる（**数値**） |
| Bonjour・ネットワーク | 3 | ポート確定前に返すと TXT が 0 になる／**登録が消えず macOS が番号を付け直す。古いほうが番号が小さい**（`deduplicated` の正しさがこの順序に乗る）／`MainActor.assumeIsolated` がトラップする（§2 に実測） |
| SF Symbols・アセット | 3 | 存在しない名前は黙って描かれない（§2 に実測）／**「カタログは両プラットフォームで共通」（→ POL-077）**／テンプレート画像でないと地に追随しない |
| サンドボックス・ファイル | 4 | **ディレクトリを跨ぐ `rename` は失敗する（→ POL-078）**／コンテナ内はブックボマーク不要／ダイアログ由来の URL はスコープが開いている／`RegisterEventHotKey` はアクセシビリティ権限を要さない |
| 通知・署名 | 2 | 前面では委譲が無いと通知が出ない（§2 に実測）／**「署名のないビルド」— §2 の実測は `ad-hoc 署名` に限定しており、限定が落ちている** |
| Keychain | 1 | UserDefaults はバックアップで持ち出せる |
| SwiftUI・AppKit | 4 | 窓より高いと上を切る（§6）／**iOS 26 は隣り合うツールバー項目をまとめる**（バージョンを名指し）／`List(selection:)` は `.tint` で変わらない（§6）／`.link` は自前の色を受け付けない（3箇所に同文） |
| Xcode ツールチェーン | 3 | **`StringCatalogTests` の4つの前提**（`.stringsdata`、見つからないキーの返り、補間の型でキーが変わる、カタログは Xcode だけが書く）／**`TestHost` の2つの前提（POL-047 の全体がここに乗る）**／シーンは view が現れる前に置かれる |
| 外向け文書 | 4 | `AGENTS.md` の署名と通知（→ POL-076）／`AGENTS.md` の「`swift test` に macOS 26 が要る」／**`DEVELOPMENT.md` が空の §3 を指して「再調査しない」（→ POL-075）**／`_NSSVGImageRep`（**アンダースコアで始まる非公開の型**）に乗っていることが `DEVELOPMENT.md` から読めない |

### 走査が見なかったもの

- **軸 F（コメント規律）と軸 C（英語化）** — 別の軸なので触れていない
  （**`MdoroCore` と Mac / iOS のコメントの大半は日本語のまま。工程14a の対象**）
- `Info.plist` / `.xcconfig` / `.xcstrings` — Swift ではないため対象外と判断
- `docs/platform/0001`〜`0003` の**本文** — `PLATFORM.md` の要約と SPEC 改訂履歴で突き合わせた

---

## 付録: Mdoro がアプリの外に対して行うこと（軸 E の出力・2026-08-30）

**工程15（README の作り直し）の入力である。** `repo-auditor` がコードを読んで確かめた22経路。
**コメントや条文の主張ではなく、コードと実測にもとづく。**

**サンドボックスは有効**（`ENABLE_APP_SANDBOX = YES`）。したがって Mac の「Library」はすべて**コンテナ内**に解決される。

### 利用者が選んだ場所

| 何に触れるか | 読/書 | いつ | 何が保証されているか | 同意 |
| :---- | :---- | :---- | :---- | :---- |
| **`Task.md`**（任意のパス） | **読み取りのみ** | 起動時 / 親ディレクトリの変更検知（300ms デバウンス）/ iPhone からの `reloadTasks` / パス変更 | ブックマークを `securityScopeAllowOnlyReadAccess` で生成。**この経路経由の書き込みは OS が拒否する**（ただし POL-119） | ファイル選択ダイアログ |
| **`<フォルダ>/MdoroLog.md`** | **作成 / 挿入**（全文置換で実現） | セッション確定時（正味60秒以上）、キューのフラッシュ時 | `preservesAllLines` が挿入以外の変化を配列比較で拒否（ただし POL-120）。`LogWriter.validate` が毎回 `Task.md` と同一パスでないことを確認 | **フォルダ**選択ダイアログ（**読み書き**） |
| `<フォルダ>/.MdoroLog.md.<UUID>.tmp` | 作成 → rename で消滅 | 上と同時 | 失敗時は `try?` で削除。**プロセスが落ちれば残留する**（POL-133） | 利用者は選んでいない |
| 診断ログの書き出し先 | 作成 / 上書き | 設定 → Files → Export | — | 保存ダイアログ |

**`Task.md` への書き込み経路はコード上に存在しない。** 書き込み API を持つ型は
`LogWriter` / `FileStateStore` / `DiagnosticLogFile` の3つだけで、`TaskFileReader` は読み取り専用。

### アプリ自身の場所（利用者は選んでいない）

| 何に触れるか | 読/書 | 中身 |
| :---- | :---- | :---- |
| `~/Library/Containers/com.sohta.MdoroMac/Data/Library/Application Support/Mdoro/state.json` | 作成 / 上書き | **平文 JSON。`taskFilePath` と `logFolderPath` の絶対パス、タスク名のスナップショット、未書き込みのログ行** |
| 同 `state.json.unreadable-YYYYMMDD-HHmmss` | 作成（退避） | 壊れた状態ファイル。**消さない** |
| `~/Library/Containers/.../Library/Logs/Mdoro/mdoro.log` | 作成 / 追記 | 伏字済み。**実測で確認**（下記） |
| 同 `mdoro.1.log` | **上書き / 旧世代を削除** | 2MB 超で回転（POL-129） |
| `~/Library/Containers/.../Library/Preferences/com.sohta.MdoroMac.plist` | 作成 / 上書き | **平文のデバイストークンの配列**（実測3件・POL-127）、ブックマーク、ウィンドウ位置 |

### OS に対して要求すること（**README に記載が無い** — POL-124）

| 何 | いつ | 効果の範囲 |
| :---- | :---- | :---- |
| **アイドルスリープ抑止** | `runState == .running` の間ずっと | **プロセスではなく機械全体。** `pmset -g assertions` に出る。**設定で切れない** |
| ログイン項目への登録 | 設定で入にしたとき | System Settings に項目が現れる |
| グローバルホットキー4種 | 設定で割り当てたとき | **システム全域** |
| 通知の許可要求と投函 | 起動時 / セッション終了 / 事前通知 / 失敗 | **本文にタスク名が載る**（POL-130） |
| TCP リスナー2本（全インターフェース） | 起動時 | WebSocket と HTTP `/info`。ローカルネットワーク許可の対象 |
| **Bonjour への広告** | リスナー起動後 | **サービス名は Mac の名前**（POL-125）。TXT は `ws` と `v` のみ |
| **無認証の `GET /info`** | LAN 上の誰からでも | **Mac の名前** / プロトコル版 / **ペアリング中かどうか** / ポート |

### iPhone

| 何に触れるか | 中身 |
| :---- | :---- |
| **Keychain**（account = **Bonjour のサービス名**） | 64文字のデバイストークン。**`kSecAttrAccessible` 未指定**（POL-131） |
| **iOS の UserDefaults** | **`StateSnapshot` 全体** —— Mac の絶対パス2本と**タスク一覧そのもの**（最大1000件・POL-128） |
| 通知 / Live Activity | 本文とロック画面に**タスク名**（60文字に切る） |

### 通信路の性質（**どの文書にも書かれていない** — POL-122）

**WebSocket は平文である。** TLS は設定していない。LAN 上を流れるのは:

- **デバイストークンそのもの**
- **`Task.md` とログフォルダの絶対パス**
- **Markdown のタスク見出しと本文すべて**

**LAN の外へ出るものは1つも無い。** `URLSession` / `Process` / サブプロセスはコードベースに存在しない（全走査済み）。
`Activity.request` に `pushType` を渡していないので **APNs トークンも発行されない。**

### 約束が守られていると確認できたもの

- **`Task.md` の読み取り専用ブックマークは実際に使われている** —— `AppModel.setTaskFile` が `readOnlyBookmark` を呼ぶ。
  ログフォルダだけが `readWriteBookmark`
- **診断ログの伏字は実測で成立している** —— 稼働中の `mdoro.log`（142,844バイト / 1,600行）に対し、
  `taskFilePath`・`logFolderPath`・タスク名・ファイル名・ユーザー名・ホスト名を照合し、**いずれも1件も出現しなかった**
- **`docs/PRIVATE-LINKS.md` は `.gitignore` にあり、`git ls-files` にも履歴にも無い**
- **`docs/images/` の7枚すべてを開いて確認** —— タスク名は架空、パス・ホスト名・端末名・キャリア名・
  他アプリの通知の写り込みは**無い**

### 監査が見なかったもの

- `docs/SPEC.md` は全文ではなく該当条文のみ / `docs/CONTEXT.md` は §1・§2・§5・§6 のみ
- `MdoroServer.swift:140-341`（認証後のメッセージ処理。外部への副作用は `broadcast` のみと確認済み）
- `Views/` のレイアウト系 / テストコード全般 / `docs/platform/`
- **`logDailySummary`** —— `state.json` に永続化されるが**読む場所がコードに1つも無い。**
  REQ-LOG-014 / 015（見送り）に対応するフィールドと判断して除外した

---

## 決定済みの方針（人間の採否・2026-08-28）

| ID | 決定 | 記録 |
| :-- | :---- | :---- |
| **POL-020** | **未設定の間はログを記録しない。キューにも積まない。** 確定と周回加算は通常どおり。画面に未設定を示す。未設定は REQ-LOG-005 の失敗経路の対象外 | [0033](decisions/0033-unset-log-path-records-nothing.md) |
| **POL-018** | 1.3 の配布欄を「**ソースからのビルドのみ**」に書き換え、**OPEN-021 を解決済みにする** | [0021](decisions/0021-published-as-oss-named-mdoro.md) |
| **POL-009** | REQ-LOG-015 から**プラグイン名を外し、ツール中立に書き換える。** 条文は残す（MAY・見送りのまま） | [0023](decisions/0023-markdown-first-not-obsidian-first.md) |
| **POL-004** | 4.7 を **7.3 と同じ「集中と休憩を繰り返す手法」に統一する。** 仕様書から「ポモドーロ」が消える | [0021](decisions/0021-published-as-oss-named-mdoro.md) |

## 完了

| ID | 症状 | 軸 | PR |
| :-- | :---- | :-- | :-- |
| — | — | — | — |

## 却下・先送り

| ID | 症状 | 判断 | 理由 |
| :-- | :---- | :---- | :---- |
| **POL-051** | `taskList.parseError` は Mac が書いた文を iPhone がそのまま表示する（[0035](decisions/0035-a-failure-needs-somewhere-to-arrive.md) の「送る側が相手の画面の文言を決めない」と同じ構図） | **公開後に直す**（2026-08-29） | 文は1種類（`Could not read the task file`）で**実害がない**。直すなら `parseError` を文字列からコードへ変える形が筋だが、**通信仕様の変更であり両端末を同時に直す必要がある**（片方だけ変えない）。公開直前に触る種類の変更ではない。**食い違いが残ることを承知のうえで先送りする** |
| **POL-043** | Live Activity の開始失敗のコードを捨てている（iOS に診断ログが無い） | **現状維持** | 込み入った内容であり、起きる可能性も低い。**いまは機能と方針の堅牢性を優先する**（2026-08-28）。例外を広げると「画面にコードを出さない」原則が2箇所目で緩み、3箇所目の歯止めがなくなる。最も多い原因（許可がない）は画面の文が案内している |
