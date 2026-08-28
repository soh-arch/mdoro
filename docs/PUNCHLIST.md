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
| **状態** | `open` → `doing` → `review` → `done` / `rejected` / `deferred` |
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

---

## 進行中・未着手

**工程13b（仕様書の監査、軸 A / B / C / D）の結果を 2026-08-28 に起票。** 重大度順。
軸 E〜J（コードとリポジトリ）は工程14b で追加する。

| ID | 症状 | 根拠 | 軸 | レーン | 重大度 | 状態 | PR |
| :-- | :---- | :---- | :-- | :---- | :---- | :---- | :-- |
| **POL-010** | 条文が日本語の UI 文言そのものを規定している箇所が **19件**。REQ-UIX-038（MUST）と正面衝突 | REQ-UIX-038 / [0022](decisions/0022-english-only-ui.md) | C | human | blocker | open | — |
| **POL-011** | 10.3 の `notificationSound` が `chime` / `bell` / `wood`。**macOS に実在しない音**。0.12 の確定（`Glass` / `Submarine` / `Pop`）と食い違う。プロトコルの enum なので両端で食い違うと繋がらない | 0.12節 / REQ-NTF-006 / [0017](decisions/0017-system-notification-sounds.md) | C | human | blocker | open | — |
| **POL-001** | 表題が「システム要件定義・仕様書：**ポモドーロタイマー**」。公開リポジトリで最初に読まれる1行が旧名 | [0021](decisions/0021-published-as-oss-named-mdoro.md) / [0024](decisions/0024-rename-everything-to-mdoro.md) | A | agent | major | open | — |
| **POL-002** | 1.1「目的」が製品を「ポモドーロタイマー」と定義。**同じ節の2行下で 0021 を引きながら、0021 が避けると決めた語で自分を名乗っている** | [0021](decisions/0021-published-as-oss-named-mdoro.md) | A | agent | major | open | — |
| **POL-006** | 9.4 の背景が置き場所を **`Vault`** と呼ぶ。Obsidian の固有名詞。9.3 は `taskFilePath` / `logFolderPath` を持つだけで Vault という単位は存在しない | [0023](decisions/0023-markdown-first-not-obsidian-first.md) / 9.3 | B | agent | major | open | — |
| **POL-012** | 既定プリセット名「標準」が条文本体に **11件**。7.2 のログ例だけ `[Standard]`。**同じ仕様書に既定プリセット名が2つある** | 0.12節 / [0022](decisions/0022-english-only-ui.md) | C | agent | major | open | — |
| **POL-013** | 工程10 で確定した語 9件のうち、**条文から引けるのは2件だけ**。残りは改訂履歴 0.12 にしかない | [decisions/README.md](decisions/README.md)「反映」 | C | human | major | open | — |
| **POL-014** | Info.plist の usage description の言語がどの条文にも規定されていない。**利用者が最初に読むアプリの文章**なのに REQ-UIX-038 の列挙に含まれない | REQ-UIX-038 / REQ-PLT-001 | C | agent | major | open | — |
| **POL-016** | 1.1 の背景が「**個人開発**かつローカル環境での運用に特化」。同期競合を排除しているのは開発体制ではなく [0001](decisions/0001-mac-as-single-source-of-truth.md) | [0021](decisions/0021-published-as-oss-named-mdoro.md) / [0001](decisions/0001-mac-as-single-source-of-truth.md) | D | human | major | open | — |
| **POL-017** | 第14章の背景が「**個人利用**における」。「作者1人」とも「1人の利用者の2端末」とも読める | [0021](decisions/0021-published-as-oss-named-mdoro.md) / REQ-NFR-008 | D | human | major | open | — |
| **POL-018** | 1.3 の配布欄が「**TestFlight 配布を想定**」のまま。0021 は「ソースからのビルドのみ」と確定済み。OPEN-021 も未決のまま残っている | [0021](decisions/0021-published-as-oss-named-mdoro.md) | D | human | major | open | — |
| **POL-019** | 第14章が Time Sensitive 通知を「利用できない**可能性がある**」。REQ-NTF-005 は「成立しない」と実機確認済み。**配布がソースのみである以上、全利用者が該当する** | REQ-NTF-005 / [0021](decisions/0021-published-as-oss-named-mdoro.md) | D | agent | major | open | — |
| **POL-020** | **パス未設定のまま使い始めた状態の条文がない。** 既定値は「未設定」で全利用者がそこから始まるが、条文は「一度設定した後」を前提にしている。未設定のまま確定に至ったときキューに積むかが引けない | REQ-ERR-001 / REQ-LOG-002 / REQ-LOG-005 / 9.3 | D | human | major | open | — |
| **POL-003** | 3.1 の背景が作業1本を「ポモドーロ」と呼ぶ。他所はすべて「セッション」。用語集にない語 | 第16章 / 4.1 | A | agent | minor | open | — |
| **POL-004** | 4.7 が「ポモドーロ手法」、7.3 が「集中と休憩を繰り返す手法」。**同じ技法の呼び方が2つ。違反ではないので残す判断も成立する** | 7.3 の既存表現 | A | human | minor | open | — |
| **POL-005** | `CONTEXT.md` §1 の原則が `PomodoroLog.md` のまま。SPEC は `MdoroLog.md` に統一済み | [0024](decisions/0024-rename-everything-to-mdoro.md) | A | agent | minor | open | — |
| **POL-007** | REQ-TSK-015 が `[[...]]` と `#tag` を「Markdown 記法」と総称。REQ-LOG-013 は「Obsidian / Logseq **などが解釈する**」と書き分けている | REQ-LOG-013 / [0023](decisions/0023-markdown-first-not-obsidian-first.md) | B | agent | minor | open | — |
| **POL-008** | OPEN-018 の題が「**Obsidian 以外の**ツール固有記法」。Obsidian を基準点に置いている | [0023](decisions/0023-markdown-first-not-obsidian-first.md) / [0025](decisions/0025-standard-checkbox-syntax-only.md) | B | agent | minor | open | — |
| **POL-009** | REQ-LOG-015（Dataview / Tasks 形式での出力、MAY・見送り）が **Obsidian のプラグイン名を条文に持ったまま公開される**。監査役は「見送り済みは挙げない」規則により除外し、人間の判断に委ねた | [0023](decisions/0023-markdown-first-not-obsidian-first.md) / `CONTEXT.md` §6 | B | human | minor | open | — |
| **POL-015** | REQ-ERR-014 が OS 設定画面のパスを日本語で規定。英語化すると日本語ロケールの利用者の画面と一致しない。REQ-SEC-005 とも粒度が食い違う | REQ-ERR-014 / REQ-SEC-005 / 0.12節 | C | human | minor | open | — |
| **POL-021** | 非スコープの「複数ユーザー対応」が、人の話か端末の話か読めない。第14章「1対1接続」は端末の話 | [0021](decisions/0021-published-as-oss-named-mdoro.md) / 第14章 | D | agent | minor | open | — |
| **POL-022** | 「ユーザー」約30件 / 「利用者」約11件が混在。**一括置換は禁止**（macOS のユーザーアカウント等3件は対象外） | [0021](decisions/0021-published-as-oss-named-mdoro.md) / REQ-UIX-042 | D | agent | minor | open | — |
| **POL-023** | REQ-PLT-009 が製品要件と**検証手順**を1条文に混ぜている。前者は利用者、後者は貢献者に宛てられており宛先が違う | `CLAUDE.md`（手順は DEVELOPMENT.md） | D | agent | minor | open | — |

## 完了

| ID | 症状 | 軸 | PR |
| :-- | :---- | :-- | :-- |
| — | — | — | — |

## 却下・先送り

| ID | 症状 | 判断 | 理由 |
| :-- | :---- | :---- | :---- |
| — | — | — | — |
