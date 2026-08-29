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
| **POL-053** | **テストが本物の IOPM アサーションを取る。** `record()` でセッションを走らせると `IdleSleepGuard.begin()` が実機のスリープ抑止を掛ける。POL-047 と同じ「テストが利用者の環境に触る」類。通知と同じ継ぎ目に載せられる | `CONTEXT.md` §2 / POL-047 | — | agent | minor | open | — |
| **POL-054** | **接続拒否が診断ログに残らない。** `MdoroServer` は `DiagnosticLog` を持たない。「ペアリングできない」という issue で、**5回間違えたのか、トークンが失効したのか、別端末が繋がっていたのかが読めない** | REQ-ERR-010 / [0018](decisions/0018-diagnostic-log-policy.md) | — | agent | minor | open | — |
| **POL-055** | 空状態の注記の `##` だけコード体裁にならない（バッククォートで囲めば揃うが、カタログのキーが変わる） | REQ-TSK-016 | — | agent | minor | open | — |
| **POL-056** | 受け取る側が引く文言の出所が2種類（`ProtocolErrorCode.displayMessage` は `MdoroCore`、`AuthFailureCode` は `ConnectionViews` の `LocalizedStringKey`）。同じ 10.2 の役割なのに揃っていない | [0022](decisions/0022-english-only-ui.md) / 10.2 | — | agent | minor | open | — |
| **POL-057** | **REQ-UIX-027 が、確認されていないプラットフォームの事実を前提にしている。** 「背景が利用者の壁紙である」が事実か未確認のまま、固定値と半透明素材で組むことを MUST で要求している。**この条文は改訂履歴に一度も現れず、Live Activity の実装が2回書き直された後も突き合わされていない。** 同じ理由から引かれた REQ-COL-022（メニューバー）は「色を使わない」という別の答えに落ち着いている。**意匠の問題ではなく、条文が実態に則していない問題として扱う** | REQ-UIX-027 / REQ-COL-022 / `CONTEXT.md` §3 | — | **human** | major | done | `fix/final-audit-items` |
| **POL-058** | **軸 K の洗い出し。** 仕様書と `CONTEXT.md` §2 が主張しているプラットフォームの事実を列挙し、確度で分ける。**`PLATFORM.md` の `未検証` 8項目**（§3 から移送）も対象。条文が事実を抱えている箇所は `PLATFORM.md` への参照に置き換える。**結果は下の付録。81件のうち出典があったのは1件** | [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) | K | `platform-researcher` | major | done | `fix/final-audit-items` |
| **POL-059** | `MdoroWidgetLiveActivity.swift` のコメントが**誤った前提を引いている**（`// REQ-UIX-027: 背景は壁紙なので…`）。条文は v2.18 で訂正済み | [platform/0001](platform/0001-live-activity-lock-screen-background.md) | K | agent | minor | open | — |
| **POL-060** | **8.3 冒頭の「プラットフォーム制約（Apple 公式で確認済み）」に出典がない**（`SPEC.md:818`）。REQ-NTF-002（**MUST**）、REQ-UIX-020 / 022 の **MUST→SHOULD 格下げの唯一の理由**、REQ-UIX-024 の禁止、第14章の帰結がこの一文に乗る。さらに **[0009](decisions/0009-live-activity-scope.md) は出典欄に「仕様書 8.3 冒頭」、[0030](decisions/0030-live-activity-is-display-only.md) は「`CONTEXT.md` §3（一次情報で確認済み）」と書いており、その §3 は [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) で空になった。**「確認済み」という文字列だけが**4文書**を巡回していた（`CONTEXT.md:653` も §3 を指す）。**調査完了（[platform/0002](platform/0002-live-activity-background-start-and-suspend.md)）: (b) と suspend は文書化されていたが、「例外は APNs による push-to-start のみ」は誤り。サーバー不要の開始経路が2つある**（`LiveActivityIntent` / iOS 26 のスケジュール開始）。**REQ-NTF-002 の支えは崩れていない**（根拠が「WebSocket が切れる」から「suspend 中はコードが走らない」に変わる）。**人間の決定（2026-08-29）: 事実を条文から追い出し `PLATFORM.md` を参照する。挙動は変えない。** SPEC v2.19 で反映 | `SPEC.md:818` / [platform/0002](platform/0002-live-activity-background-start-and-suspend.md) | K | **human** | **major** | done | `fix/axis-k-platform-facts` |
| **POL-061** | **REQ-COL-022（MUST）「メニューバーの地は可変でコントラストを保証できない」に出典がない**（`SPEC.md:1028`）。REQ-UIX-030・REQ-UIX-035（ともに **MUST**）と [0031](decisions/0031-the-menu-bar-mark-shows-the-session.md) の「印を3枚に分ける」設計がこの上に乗る。**[0038](decisions/0038-platform-facts-are-not-the-specs-job.md) 自身が「同じ問題に2つの答えがあり、片方は検証されていなかった」と名指ししている。**直ったのは壁紙側（POL-057）で、**調査完了（[platform/0003](platform/0003-menu-bar-ground-and-status-item-color.md)）: 「地は可変」は正しい。しかし「コントラストを保証できない」は誤りで、`NSStatusBarButton.h` は テンプレート画像について "This guarantees that the button will look correct" と明記している。そして REQ-UIX-035 の「色を使えないため」も誤り** — `NSButton.contentTintColor` は テンプレート画像に色を載せる正規 API で、系統的な扱いと**併用**すると書かれている。禁止されているのは `statusItem.view` だけ。**ただし形状で区別すること自体には別の根拠がある**（`accessibilityDisplayShouldDifferentiateWithoutColor` の "shapes or glyphs"）。**人間の決定（2026-08-29）: 理由だけ差し替える。処方（テンプレート画像・印3枚）は変えない。** 根拠を `accessibilityDisplayShouldDifferentiateWithoutColor` に置き換えた。SPEC v2.19 で反映 | REQ-COL-022 / [platform/0003](platform/0003-menu-bar-ground-and-status-item-color.md) | K | **human** | **major** | done | `fix/axis-k-platform-facts` |
| **POL-062** | **3.5 の表8行すべてに出典がない**（`SPEC.md:483-494`）のに、REQ-PLT-001（**MUST**）が「いずれか1つでも欠けると接続が成立しない」と断定している。**同じ内容を `PLATFORM.md` は `未検証` としており、MUST の条文が未検証の事実に依拠している**（[0038](decisions/0038-platform-facts-are-not-the-specs-job.md) が禁じた形そのもの） | REQ-PLT-001 / 3.5 | K | **human** | major | open | — |
| **POL-063** | **否定的事実の上に立つ MUST が2件。** REQ-UIX-026「Live Activity 拡張からのネットワークアクセスはサンドボックス上**不可能**」、REQ-PLT-008「許可状態を問い合わせる API は**存在しない**」＋生の `-65570`（REQ-ERR-014 がこれに依拠）。**「不可能」「存在しない」は最も検証されにくい形の主張** | REQ-UIX-026 / REQ-PLT-008 | K | **human** | major | open | — |
| **POL-064** | **数値だけの MUST。** ~~REQ-UIX-028（8時間 / 計12時間）~~ は [platform/0002](platform/0002-live-activity-background-start-and-suspend.md) で**正しいと確認できた。残るは REQ-UIX-025（動的データ 4KB）のみ**。出典なし | REQ-UIX-025 | K | **human** | minor | open | — |
| **POL-065** | **`CONTEXT.md:185` の記述が API の性質と食い違う疑い。**「`end()` は OS 上にあるものを全部畳む」は `Activity.end(...)` の説明ではなく、**`Activity.activities` を回す自前の実装の説明**である可能性。**プラットフォームの事実の形をした、自分のコードの説明** | `CONTEXT.md` §2 | K | agent | minor | open | — |
| **POL-066** | **`CONTEXT.md:83`「ビューに Timer を置くと表示が止まる」が、原因未特定のまま一般則として書かれている。** `Timer.publish(...).autoconnect()` + `.onReceive` は通常機能する。**観測された文脈（`MenuBarExtra` のラベル）に固有かもしれない** | `CONTEXT.md` §2 | K | **human** | minor | open | — |
| **POL-067** | **空になった `§3` を根拠として指す参照が8箇所残っている。** `CONTEXT.md:483,647,653` / `SPEC.md:1580` / [0021](decisions/0021-published-as-oss-named-mdoro.md) / [0024](decisions/0024-rename-everything-to-mdoro.md) / [0030](decisions/0030-live-activity-is-display-only.md) / [0031](decisions/0031-the-menu-bar-mark-shows-the-session.md)。**行き先を `PLATFORM.md` へ張り替える**（[0038](decisions/0038-platform-facts-are-not-the-specs-job.md) 自身の §3 への言及は経緯なので残す）。**Live Activity に関わる3箇所は SPEC v2.19 で修復済み**（0009 / 0030 / `CONTEXT.md:661`）。**残り5箇所**（`CONTEXT.md:497` / `SPEC.md:1580` / 0021 / 0024 / 0031）は署名・通知・接続の話で、**それぞれの事実がまだ確認されていない** | [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) | K | agent | minor | open | — |
| **POL-068** | **REQ-UIX-035 の参照先が誤り**（`SPEC.md:843`）。「iPhone は背面に回れば接続が切れる（**3.5 のプラットフォーム制約**）」とあるが、**この主張は 3.5 になく 8.3 冒頭にある。** POL-060 への依存が1件、参照の誤りで見えなくなっている | REQ-UIX-035 | K | agent | minor | done | `fix/axis-k-platform-facts` |
| **POL-069** | **`PLATFORM.md` の `未検証` に設計判断が混ざっている。** 2（通知を事前スケジュールする＝**REQ-NTF-002 そのもの**）、5（`replaceItemAt` を使う）、6（親ディレクトリに張る）は手段の選択であって事実ではない。7（Xcode の MCP サーバー）は**どの条文も依拠していない**（索引に置く性質の項目ではない） | `PLATFORM.md` | K | agent | minor | open | — |
| **POL-070** | **OPEN-007 が未決のまま、条文は断定している。** OPEN-007（`SPEC.md:1579`）は「無償 Personal Team で Time Sensitive を有効化できるか」を未決とするが、REQ-NTF-005 と第14章は「利用できない」と断定済み。**capability の有効化と配信挙動は別事象** | OPEN-007 / REQ-NTF-005 | K | **human** | minor | open | — |
| **POL-071** | **同じ誤前提がコードと外向け文書に残っていないかを見ていない。** POL-059 で `MdoroWidgetLiveActivity.swift` に1件見つかったが、**軸 K の対象は `docs/` の3ファイルだけだった。** `AGENTS.md` は「事実は両方に書いてよい」という規約上、**同種の主張を二重に持っている可能性がある** | [0038](decisions/0038-platform-facts-are-not-the-specs-job.md) / `CLAUDE.md` | K | — | minor | open | — |
| **POL-072** | **iOS 26 に、サーバー不要で背面から Live Activity を開始する API がある**（`request(...alertConfiguration:start:)`）。**対象バージョンちょうどで入った。** 条文は「完全ローカル駆動と push-to-start は二者択一」という構図を前提にしているが、**その構図が一次情報と合っていない。** 第15章 FUT-013 の位置づけと、REQ-UIX-020 / 022 の格下げ理由に効く。**人間の決定（2026-08-29）: いまは採らない。** FUT-013 を「背面から開始・更新する3経路（うち2つはサーバー不要）」として書き直し、**採否を未決のまま残した**。スケジュール開始は開始時刻が事前に決まる場合の道具で、**利用者の操作で始まる Mdoro のセッションには現状あてはまらない** | [platform/0002](platform/0002-live-activity-background-start-and-suspend.md) / FUT-013 | K | **human** | major | done | `fix/axis-k-platform-facts` |
| **POL-073** | **`NSStatusBarButton` に `contentTintColor` が実際に効くかは静的に確認できない。** ヘッダが "Only applicable to borderless buttons" と限定しており、status bar button の `isBordered` の実値は実行しないと分からない。**軸 K で唯一、実測が要る点だった** | [platform/0003](platform/0003-menu-bar-ground-and-status-item-color.md) | K | — | minor | **不要** | — |
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
