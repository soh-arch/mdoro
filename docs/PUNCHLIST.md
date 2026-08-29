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
| **POL-047** | **`xcodebuild test` が本物の `MdoroMac.app` をテストホストとして起動する。** 起動したアプリは通常どおり通知を配信し、ウィンドウを前面に出し、Bonjour を広告し、**利用者の `Task.md` を監視する。** プロダクトオーナーが実際に「数秒おきに通知が飛び交う」「ウィンドウが急に最前面に来る」を観測（2026-08-28）。**貢献者が回すたびに、その人の通知・LAN・ファイルに触れる** | 3原則1 / [0002](decisions/0002-task-md-read-only.md) / `CONTEXT.md` §2 | — | **human**（`TEST_HOST` はビルド設定。[0013](decisions/0013-pbxproj-is-owned-by-xcode.md)） | major | open | — |
| **POL-048** | `AppModel.reject(...)` の3箇所が `message` に英文の散文を入れており（`"No stableId"` 等）、**このファイルで唯一 `case(domain:code)` でない送信経路**になった。POL-041 が問題にした「同じファイル内で不統一」と同じ形 | [0034](decisions/0034-os-errors-are-recorded-as-codes.md) / 10.2 | — | agent | minor | done | `fix/catalog-and-wire-prose` |
| **POL-049** | ビューに `.primary` / `.secondary` が約25箇所。**色相リテラルではなく OS の意味色**なので走査の対象外にしてある。`theme.textSecondary` へ寄せるかは**見た目が変わる判断** | [0007](decisions/0007-oklch-color-system.md) / REQ-COL-001 | — | **human** | minor | open | — |
| **POL-050** | `MdoroServer` の接続拒否6文言が**どの画面にも届いていない**（`MdoroClient` は `payload.code` しか読まない）。`AuthFailureCode` が `case(domain:code)` の形になっていないことが、残っている不整合 | [0034](decisions/0034-os-errors-are-recorded-as-codes.md) / 10.2 | — | agent | minor | open | — |
| **POL-051** | `taskList.parseError` は **Mac が書いた文を iPhone がそのまま表示する**（`ConnectionViews.swift:216`）。[0035](decisions/0035-a-failure-needs-somewhere-to-arrive.md) の「送る側が相手の画面の文言を決めない」と同じ構図だが、**条文は `error.message` にしか及んでいない** | [0035](decisions/0035-a-failure-needs-somewhere-to-arrive.md) / 10.2 | — | **human** | minor | open | — |
| **POL-052** | `TaskListView` の空状態の注記だけ Markdown が描画されない（`SettingsView` の同種の注記はコード体裁で出る）。揃えるなら `LocalizedStringKey` にするだけ | REQ-TSK-016 / REQ-UIX-047 | — | agent | minor | open | — |
| **POL-015** | REQ-ERR-014 が OS 設定画面のパスを日本語で規定。英語化すると日本語ロケールの利用者の画面と一致しない。REQ-SEC-005 とも粒度が食い違う | REQ-ERR-014 / REQ-SEC-005 / 0.12節 | C | human | minor | done | `docs/spec-v2.10` |
| **POL-021** | 非スコープの「複数ユーザー対応」が、人の話か端末の話か読めない。第14章「1対1接続」は端末の話 | [0021](decisions/0021-published-as-oss-named-mdoro.md) / 第14章 | D | agent | minor | done | `docs/spec-v2.10` |
| **POL-022** | 「ユーザー」約30件 / 「利用者」約11件が混在。**一括置換は禁止**（macOS のユーザーアカウント等3件は対象外） | [0021](decisions/0021-published-as-oss-named-mdoro.md) / REQ-UIX-042 | D | agent | minor | open | — |
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
| **POL-043** | Live Activity の開始失敗のコードを捨てている（iOS に診断ログが無い） | **現状維持** | 込み入った内容であり、起きる可能性も低い。**いまは機能と方針の堅牢性を優先する**（2026-08-28）。例外を広げると「画面にコードを出さない」原則が2箇所目で緩み、3箇所目の歯止めがなくなる。最も多い原因（許可がない）は画面の文が案内している |
