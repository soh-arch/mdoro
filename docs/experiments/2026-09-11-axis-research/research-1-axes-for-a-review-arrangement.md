調査を終えました。以下、報告です。書き込みは一切していません（ダウンロードした PDF はスクラッチパッドのみ）。

---

# 調査報告: 「変更の種類 → 立てる軸」を仕組みとして持つ設計

## 0. 到達できた情報源／できなかった情報源

**全文に到達し、自分で本文を確認したもの**（PDF はローカルで抽出して原文を読みました）

| 資料 | URL |
| :---- | :---- |
| Parnas & Weiss, *Active Design Reviews: Principles and Practices* (ICSE 1985 / JSS 1987) | http://figforth.org.uk/library/p132-parnas.pdf |
| Porter, Votta, Basili, *Comparing Detection Methods for Software Requirements Inspections* (TSE 1995), UMD 版 PDF | https://drum.lib.umd.edu/bitstreams/332d6328-bdce-4726-9102-e00bac748f9a/download |
| Basili ほか, *The Empirical Investigation of Perspective-Based Reading* | https://www.cs.umd.edu/~mvz/handouts/emp_pbr.pdf |
| Degani & Wiener, *Human Factors of Flight-Deck Checklists: The Normal Checklist* (NASA CR-177549, 1990) | https://ntrs.nasa.gov/api/citations/19910017830/downloads/19910017830.pdf |
| Hatton, *Testing the Value of Checklists in Code Inspections*（著者自身の PDF） | https://www.leshatton.org/Documents/checklists_in_inspections.pdf |
| Rigby & Bird, *Convergent Contemporary Software Peer Review Practices* (FSE 2013) | https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/rigby2013convergent.pdf |
| Wurzel Gonçalves ほか, *Do explicit review strategies improve code review performance?* (EMSE 2022) | https://d-nb.info/1264662815/34 |
| Leveson & Thomas, *STPA Handbook* (2018) | http://psas.scripts.mit.edu/home/get_file.php?name=STPA_handbook.pdf |
| rust-lang/rust `triagebot.toml`（実物 1,870 行） | https://raw.githubusercontent.com/rust-lang/rust/master/triagebot.toml |

**Web ページとして到達できたもの**: Chromium の `code_reviews.md` / `code_review_owners.md` / `mojo.md` / `rule-of-2.md` / `ipc-reviews.md`、Google SRE Book 第27章と付録E、W3C Security & Privacy Questionnaire、Kubernetes KEP テンプレート、GitLab `database_review`、Microsoft Learn の STRIDE-per-Element。

**到達できなかったもの（推測で埋めていません）**

- **CACM の *Lessons from Building Static Analysis Tools at Google*** — `cacm.acm.org` が **HTTP 403**。10% 偽陽性の話は検索結果の要約経由でしか取れていません（**一次確認できず**）。
- **IEC 61882 (HAZOP) の公開サンプル PDF** — 取得はできたが**全ページが画像**でテキスト抽出不能。ガイドワード表を原文で確認できていません。
- **NEJM (Urbach 2014 / Pronovost 2006)** — `nejm.org` が **403**、`pubmed.ncbi.nlm.nih.gov` は Cookie 要求で本文が返らず。数値は検索結果の要約のみ（**一次確認できず**）。
- **Ciolkowski (2009) のメタ分析**、**Martin & Tsai の N-fold inspection (CACM 1990)**、**Porter らの後続リプリケーション (Springer)** — いずれも有料。要旨の二次記述のみ（**一次確認できず**）。
- **Gawande『The Checklist Manifesto』の「5〜9項目」「60〜90秒」** — 書籍本文に到達できず、要約サイトのみ（**一次確認できず**）。ただし後述のとおり **"killer items" の概念は NASA CR-177549 で一次確認できました**。
- **DO-178C の DAL 別目標数（A=71, D=26）** — ベンダーの解説ページのみ。規格本体は有料（**一次確認できず**）。

---

## 1. こういう表を実際に持っている実例と、その「粒度」

結論から言うと、**「軸を引く鍵（キー）」は少なくとも6種類**あり、実例はそのどれかに分類できます。ファイル種別だけで切っているところは、むしろ少数派です。

### 1-A. パスで引く／強制力あり（キー = ファイルパス）

**Chromium の OWNERS `per-file` 指令**
https://chromium.googlesource.com/chromium/src/+/HEAD/docs/code_reviews.md （"OWNERS file details"）

```
per-file *_messages*.h=set noparent
per-file *_messages*.h=file://ipc/SECURITY_OWNERS
```

パスパターンに対して「親の OWNERS を継承しない（`set noparent`）」「この名簿の人間だけが承認できる」を宣言する。`code_review_owners.md`（2021-03-24）では **Gerrit 側で強制され、コミッタでも迂回できない**と明記されています（https://chromium.googlesource.com/chromium/src/+/HEAD/docs/code_review_owners.md）。同ページは **「トップレベルの OWNERS は避け、葉ノードに置く」**（過負荷を防ぐため）とも述べています。

**GitHub CODEOWNERS**
https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
パスパターン → 所有者。ブランチ保護の "Require review from Code Owners" と組み合わせて必須化する。**粒度はパスのみ**で、「何を見るか」は表に書けない（誰を呼ぶか、だけ）。

### 1-B. パス → 「見るべき軸そのもの」を本文で渡す（キー = パス、値 = 散文の注意）

**rust-lang/rust の `triagebot.toml`** — これが今回いちばん近い実例でした。

- `[mentions."<path>"]` エントリが**実測 124 件**、うち **96 件が `message` を持つ**（`cc` だけのものが 28 件）。
- 値は「誰を呼ぶか」ではなく**「何が成り立っていないといけないか」**になっている:

```toml
[mentions."library/core/src/intrinsics/simd/mod.rs"]
message = """
Some changes occurred to the platform-builtins intrinsics. Make sure the
LLVM backend as well as portable-simd gets adapted for the changes.
"""

[mentions."src/bootstrap/src/core/build_steps/llvm.rs"]
message = "This PR changes how LLVM is built. Consider updating src/bootstrap/download-ci-llvm-stamp."

[mentions."tests/ui/stats/input-stats.stderr"]
message = "Changes to the size of AST and/or HIR nodes."

[mentions."Cargo.lock"]
message = "These commits modify the `Cargo.lock` file. Unintentional changes can be introduced when switching branches and rebasing PRs."

[mentions."tests/crashes"]
message = "This PR changes a file inside `tests/crashes`. If a crash was fixed, please move into the corresponding `ui` subdir and add 'Fixes #<issueNr>' to the PR description to autoclose the issue upon merge."
```

**粒度の観察**: パスは**ディレクトリ／単一ファイル／テストの期待値ファイル**まで混在している。そして軸の多くが **「この変更に伴って“別の場所”も直っているか」（同期漏れの検出）** である。`triagebot.toml` の軸は「品質」ではなく **「随伴物」** を見ている、というのが実例から読める最大の特徴です。

**Danger (JS/Ruby)** — https://danger.systems/js/ 。`danger.git.modified_files` の差分から任意のルールを書く汎用機構。典型ルールとして「package.json が変わったら lockfile も」「新コードが増えたらテストも」「changelog 項目」「`it.only` の混入」が挙げられている。これも **「随伴物」型の軸**です。

### 1-C. パス＋内容＋意味の複合で引く（キー = 3種類の混合）

**GitLab の Database Review** — https://docs.gitlab.com/development/database_review/
必須トリガが**3層**になっているのが特徴です。

1. **パス**: `db/`, `lib/gitlab/background_migration/`, `lib/gitlab/database/`
2. **コード内容**: `update`, `upsert`, `delete_all`, `destroy_all` などの ActiveRecord メソッドの使用、`count` / `distinct_count` / `sum` を使う metrics
3. **意味的条件**: 「明らかでない SQL を生成する変更」(*Changes that produce SQL queries that are beyond the obvious*)

そして軸（レビュアが見るもの）は「migration が可逆か（`#down` があるか）」「`db/structure.sql` に migration 由来以外の差分が混ざっていないか」「クエリプランが添付されているか」「データ分布に対する挙動」。
**ここは「3 の意味的条件」が肝で、機械では引けない条件をわざと表に残している。**機械で引ける2層で拾い切れない分を、人間が読む文章として置いている。

### 1-D. 「ファイルの種類」ではなく「設計要素の種別」で引く（キー = 要素の型）

ここが、**ファイル種別より一段抽象度の高い切り方**です。

**STRIDE-per-Element**（Microsoft、SDL）
https://learn.microsoft.com/en-us/archive/blogs/larryosterman/threat-modeling-again-stride-per-element

> "for each type of element, there is a limited set of STRIDE categories that apply to that element"
> "every dataflow in your document, has Tampering, Information Disclosure, and Denial of Service threats."

DFD の要素型（外部エンティティ / プロセス / データストア / データフロー）ごとに、立てるべき脅威カテゴリが**固定表**で決まる。著者はこの表の効用をこう書いています:

> "STRIDE/element allows people to produce competent threat models with relatively little training."

**HAZOP のガイドワード × パラメータ**（IEC 61882）
ガイドワード（NO/NONE, MORE, LESS, AS WELL AS, PART OF, REVERSE, OTHER THAN）を、各ノードの各設計パラメータに**総当たりで掛ける**ことで逸脱を生成する。
**注意**: 規格本体のサンプル PDF は画像で読めませんでした。ガイドワードの一覧は二次資料（https://pqri.org/wp-content/uploads/2015/08/pdf/HAZOP_Training_Guide.pdf など）でのみ確認しています。

**STPA の Unsafe Control Action 4類型**（一次確認済み、STPA Handbook 2.5 節相当）

> "There are four ways a control action can be unsafe (represented in the columns above): 1. Not providing the control action leads to a hazard. 2. Providing the control action leads to a hazard. 3. Providing a potentially safe control action but too early, too late, or in the wrong order 4. The control action lasts too long or is stopped too soon (for continuous control actions, not discrete ones)."

**制御アクション × 4類型 = 表**。ファイル種別でもリスク種別でもなく、**「系のどこに命令が流れているか」**で引いています。

### 1-E. 「文書の断面 × 読み手の専門」で引く（キー = 2次元）

**Parnas & Weiss, Active Design Reviews**（一次確認済み、Figure 3 "Correspondence Of Reviews And Reviewers"）

| レビュー | 担当する読み手 |
| :---- | :---- |
| A: Assumption Validity | Device Expert |
| B: Assumption Sufficiency | Device Programmer |
| C: Consistency Between Assumptions And Functions | Avionics Programmer |
| D: Access Function Adequacy | Device Programmer |

さらに「どの断面にも全種類のレビューが当たるように」割り当てる:

> "To assure complete coverage of the design document, reviewers are assigned so that each kind of review is performed for each section of the document."

**1985 年の時点で、今回の質問そのものの構造（軸 × 割り当て）が既に設計されています。**

### 1-F. リスク等級／工程段階で「軸の本数」を変える（キー = 等級）

- **Kubernetes PRR questionnaire** — https://github.com/kubernetes/enhancements/blob/master/keps/NNNN-kep-template/README.md
  節: Feature Enablement and Rollback / Rollout, Upgrade and Rollback Planning / Monitoring Requirements / Dependencies / Scalability / Troubleshooting。**`(R)` マークが付いた設問だけがそのマイルストンで必須**。alpha では Enablement/Rollback のみ、beta で Rollout・Monitoring・Dependencies・Scalability が加わり、GA で全部。
  設問例（逐語）: "How can this feature be enabled / disabled in a live cluster?" / "How can someone using this feature know that it is working for their instance?" / "How does this feature react if the API server and/or etcd is unavailable?"
- **DO-178C** — 保証レベル DAL A/B/C/D で満たすべき目標数が変わる（A=71, D=26 と紹介されるが**一次未確認**）。
- **Chromium Rule of 2** — https://chromium.googlesource.com/chromium/src/+/main/docs/security/rule-of-2.md 。「信用できない入力 / 安全でない言語 / 高権限」の**3つのうち2つまで**。軸ではなく**不変条件**の形で表を圧縮した例。3つ揃う CL は原則として承認しない。

### 粒度のまとめ

| 引く鍵 | 実例 | 強み | 弱み |
| :---- | :---- | :---- | :---- |
| パス | CODEOWNERS, Chromium OWNERS | 強制できる／争いが起きない | 「何を見るか」を書けない |
| パス → 散文の注意 | rust `triagebot.toml` | 軸そのものを渡せる | 強制力がない（無視できる） |
| パス＋内容＋意味 | GitLab DB review | 取りこぼしが少ない | 意味条件は人間頼み |
| 設計要素の型 | STRIDE-per-element, STPA | **事故が無くても軸が立つ** | 組合せ爆発（後述） |
| 文書断面 × 専門 | Parnas ADR | 網羅性が設計できる | 人数が要る |
| リスク等級・工程段階 | K8s PRR, DO-178C | **軸の総数を制御できる** | 等級判定が争点になる |

---

## 2. 軸が増えすぎて機能しなくなる問題

### 2-1. 実務でどう抑えているか（一次確認済み）

**Google SRE Book 第27章 "Reliable Product Launches at Scale"**
https://sre.google/sre-book/reliable-product-launches/

> "In practice, there is a near-infinite number of questions to ask about any system, and it is easy for the checklist to grow to an unmanageable size."
> "In an effort to curb its growth, at one point, adding new questions to Google's launch checklist required approval from a vice president."
> "The checklist needs continuous attention in order to remain relevant and up-to-date" — 定期的に誰かが全項目を通読して**陳腐化した項目を特定する**。

**つまり Google の答えは「追加のコストを上げる」＋「定期的に削る」**であって、上限値を決めることではありませんでした。

**Degani & Wiener, NASA CR-177549**（一次確認済み）

- 同じ B-757 で、**A社のグランドフェーズのチェックリストは 50 項目、B社は 13 項目**。同じ機体・同じ目的でこの差がある（3.1 節）。
- ある DC-9-50 のチェックリストは ENGINE START/TAXI/TAKEOFF で **81 項目**あり、乗員は「規定どおりにはやらず、自分が重要だと思う項目（"killer items"）だけをやる」状態になっていた（5節）。**長すぎる表の失敗形は「無視」ではなく「勝手な間引き」**である、という観察です。
- Appendix A ガイドライン (7): *"A long checklist should be subdivided to smaller task-checklists or chunks that can be associated with systems and functions within the cockpit."*
- ガイドライン (10): 最も重要な項目は**先頭に**置く（中断が入る前に終わるように）。
- **逆向きの失敗も報告されている**: 短すぎる checklist は暗記を誘い、実物を見なくなる — *"the minimal length (number of items) of the B-757 checklist used by this company made it also inviting to commit this checklist to memory."*（4節・事例）

**Google の静的解析（Tricorder）** — **一次確認できず**（CACM が 403）。検索結果の要約によれば「レビューに出す解析は実効偽陽性 10% 以下」「偽陽性率を決めるのはツール作者ではなく開発者」「"Not useful" ボタンで継続監視」。**この数字は二次情報である点に留意してください。**
関連して **Johnson ほか, ICSE 2013 "Why don't software developers use static analysis tools to find bugs?"** — 20名インタビュー。全員が有用だと考えているのに、**偽陽性と警告の提示方法**が使用の障壁になる、と結論。https://dl.acm.org/doi/10.5555/2486788.2486877 （本文は有料、要旨のみ確認）

**STRIDE の組合せ爆発の自認**（一次確認済み）

> "The STRIDE/element methodology ends up creating a fair number of threats, even a component with a relatively tiny diagram ... has *at least* 18 different threats"
> "many/most of those threats aren't meaningful threats"

生成的な表は**軸が自動で増える**。Microsoft の答えは「増やしたうえで、各脅威を意味があるか分析する工程を本体に据える」でした。**表を短くするのではなく、棄却を正式な作業として認めている。**

### 2-2. 「項目数と有効性の関係」の実証知見

**ここは正直に報告します: 「チェックリストの項目数 N と発見率」を直接測った実証研究は見つかりませんでした。** 見つかったのは「チェックリストの有無」と「運用の質」についての実証です。

- **Hatton (2008), IEEE Software 25(4)** — 3年間・**308回の検査**（産業技術者向けワークショップ）。チェックリスト有無で検定:
  > "there is no basis to reject that the number of faults found does not depend on the use of checklists"
  さらに **個人差が 10 倍**、個人の平均検出率 53%、2人チームで 76%。
  著者自身の留保（そのまま引用する価値があります）:
  > "It may well be that checklists are critically dependent on the way they are worded and/or on the way they are enforced and that the checklist used here is deficient in some regard."
  > "reasonably experienced engineers appear to use personalised 'internal' methods whether given checklists explicitly or not."
- **医療側の対比**（**一次未確認・二次情報**）: Pronovost 2006（**5項目**、ミシガン 105 ICU、感染率 2.7→0 /1000カテーテル日）は劇的な効果。一方 Urbach ほか 2014（オンタリオ州、WHO の **19項目**チェックリストを**義務化**）は「合併症 3.86%→3.82%、30日死亡 0.71%→0.65%、いずれも有意でない」。
  **「項目が多いと効かない」と読むこともできるが、両者は文脈（自発的な改善運動 vs 行政による義務化）も違う。**因果を項目数に帰属させる根拠は、今回の調査では得られませんでした。

**したがって、「N 項目を超えると効かない」という実証的な閾値は、私が到達した範囲には存在しません。** 5〜9項目・60〜90秒という数字は Gawande の書籍（Boeing の Boorman の経験則）由来で、**一次確認できていません**。

---

## 3. 「まだ事故が起きていない領域には軸が無い」問題

### 3-1. 事故駆動であることを明言している実例

**Google SRE Book 第27章**（一次確認済み）:
> "Every question's importance must be substantiated, ideally by a previous launch disaster."

**これは事故駆動の設計そのものです。** そして同じ章が「質問は無限にありうる」「VP 承認で増加を抑えた」とも言っている。つまり **Google は、事故駆動を「増やしすぎないためのゲート」として使っている**。網羅のための仕組みではない。

**Hatton の Figure 1**（一次確認済み）も同じ構図を明示しています。チェックリストは「古い系の failure を調べて fault を突き止め（diagnosis）、新しい系で同種の fault から failure を予測する（prediction）」ループの**予測側の機構**である、と定義したうえで、その効果が統計的に出なかった、という論文です。

### 3-2. 事故を待たずに軸を作る方法（＝生成的な表）

到達できた範囲で、**「過去の事故に依存しない軸の作り方」は3つの型に集約されました。**

1. **ガイドワード総当たり型（HAZOP）** — 「パラメータ × 逸脱語」で、誰も見たことのない逸脱を機械的に列挙する。
2. **要素型 × 脅威型（STRIDE-per-element）** — 「この型の要素には、この脅威が必ず当たる」。事故の履歴を参照しない。
3. **制御構造から導く（STPA）** — 制御アクションごとに UCA 4類型を当てる。Leveson の主張（一次確認済み）:
   > "In addition to component failures, STPA assumes that accidents can also be caused by unsafe interactions of system components, none of which may have failed."
   > "Decompositional analysis cannot identify these causes of accidents including human error, software requirements errors, and system design flaws."

**共通点**: いずれも **「軸のリスト」ではなく「軸を生む関数」を持っている。** 表の行は履歴ではなく、系の構造（要素型・パラメータ・制御線）から自動で生えてくる。これが事故駆動の限界に対する構造的な答えです。

### 3-3. 穴が残ることを前提にした補い方（これが一番実務的でした）

**Parnas & Weiss（一次確認済み、3節末尾）**:
> "Because our reviews are very tightly focused, we also ask a few people for **overall reviews** to decrease the chance that we overlook problems **because we neglected to pose a question**."

**軸を鋭くするほど、軸が無い領域の見落としが増える。だから「軸を持たない全体レビュー役」を少数併置する。** 1985年に、この問題が既に名指しで扱われています。

**W3C Security & Privacy Questionnaire** — https://www.w3.org/TR/security-privacy-questionnaire/
全22問の**最後の設問が**:
> "What should this questionnaire have asked?"

**質問票自身が、自分の欠落を回収する経路を最後の1行として持っている。** これはコストがほぼゼロで、表の更新を事故に依存させないための最小の仕掛けです。

**Degani & Wiener** の「陳腐化」側の対応: 新しい装備が入ったときの改訂は **「新項目を足すこと」ではなく「既存の並び順の中でどこに置くかを決めること」** だと強調しています（3.2.3 節）。**追加だけして順序を再設計しないのが劣化の主因**という指摘です。

---

## 4. 軸を割り当てる単位 —— 1人に全部 vs 1人1軸

**ここは実証知見が最も厚い領域でした。**

### 4-1. 1人1軸に分けると発見率が上がる（最も強い証拠）

**Porter, Votta, Basili (TSE 1995)**（一次確認済み、原文で数値を確認）

設計: 48名（院生）を16の3人チームに。Ad Hoc / Checklist / Scenario の3法。Scenario は **「各レビュアが別々の体系的手法で、別々の特定の欠陥クラスを探す」**。
結論（4節、逐語）:
> "1. The fault detection rate when using Scenarios was superior to that obtained with Ad Hoc or Checklist methods — an improvement of roughly 35%."
> "2. Scenarios helped reviewers focus on specific fault classes. Furthermore, in comparison to Ad Hoc or Checklist methods, the Scenario method did not compromise their ability to detect other classes of faults."
> "(3) Checklist reviewers were no more effective than Ad Hoc reviewers"
> "(4) Collection meetings produced no net improvement in the fault detection rate — meeting gains were offset by meeting losses."

**重要な3点**:
- **「1人に全部の軸を渡す」＝ Checklist は、軸を渡さない Ad Hoc と差が無かった。**
- **分担しても「担当外の欠陥を見落とす」ことは起きなかった。**（分業の典型的な懸念を、この実験は否定している）
- **収集会議（レビュー会）は純増ゼロ。** 会議で新たに見つかる分と、個人が見つけたのに会議で報告されず消える分が相殺した。

方法の定義も明快で、まさに今回の問いの言葉になっています:
> "we define a fault detection method to be a set of fault detection techniques **coupled with an assignment of responsibilities to individual reviewers**."

### 4-2. ただし効果は「チーム水準」で出る

**Basili ほか, PBR（NASA/GSFC の実務者対象）**（一次確認済み）:
> "Teams applying PBR are shown to achieve significantly better coverage of documents than teams that do not apply PBR."
> 個人水準について: "Although in most cases, reviewers using PBR found about the same number of defects as reviewers using their usual technique ... This is an unexpected result, since **the true benefit of PBR is expected to be seen at the level of teams which combine several different perspectives** for improved coverage."

**つまり「1人1軸」は、個人の成績を上げる技術ではなく、チームの被覆を上げる技術です。** 1体しか出さないなら、分割の利得はほとんど期待できない。

さらに、被験者の生の声が両極に割れた点も重要です（同論文、5節）:
> 経験が浅い人: "It really helps to have a perspective because it focuses my questions. **I get confused trying to wear all the hats!**"
> 経験がある人: "**I reverted to what I normally do.**"

**経験者は割り当てられた軸を捨てて自分の流儀に戻る。** Hatton の「経験者は明示的なチェックリストの有無にかかわらず個人的な内部手法を使う」という観察と一致します。

### 4-3. 人数を増やすほうの限界

**Rigby & Bird (FSE 2013)**（一次確認済み）
> "Convergent Practice 4: Two reviewers find an optimal number of defects"
> Microsoft の Bing/Office/SQL で招待人数の中央値は 3, 3, 4 だが、**実際に参加する人数の中央値は 2**。
> "we found that there was only a minimal increase in the number of comments about the change when more reviewers were active and there was no increase in the number of changesets submitted (i.e., the same number of 'rounds of reviewing')."

**人を足しても指摘は増えなかった。** Hatton の数値（個人 53% / 2人 76%）とも整合します。

**Parnas** も同じ制約を運用で表現しています:
> "In scheduling our reviews we try not to require any one reviewer to perform one kind of review for all sections of the document. We try to keep the time expended by an individual reviewer from being more than what is usually available for a design review. **It is rare that one reviewer is able or asked to perform more than one kind of review.**"

### 4-4. 反証側（正直に）

- **Ciolkowski (2009) のメタ分析**（**一次未確認**）: 12論文・21回の実験を集計し、要求文書では **PBR と ad hoc に有意差なし**、**PBR はチェックリストより劣った**と報告されている、という二次記述があります。https://ieeexplore.ieee.org/document/5316026/ （有料）
- **Wurzel Gonçalves ほか (EMSE 2022)**（一次確認済み）— プロ開発者に ad hoc / checklist / guided checklist（明示的レビュー戦略）を割り当てた事前登録実験:
  > "Overall, we cannot conclude that a strong relationship exists between guidance approaches using cognitive load reducing methods and code review effectiveness and efficiency."
  ただし著者は **参加者全体の成績が低すぎて有意差を検出する力が無かった**ことを限界として明記しています。

**総括**: 「1人1軸が効く」証拠（Porter 1995 の +35%）は強いが**単一実験**であり、後続の集計では再現が一貫していない。一方 **「1人に全部渡す＝チェックリスト」が ad hoc と差が無い**という所見は、Porter と Hatton の2本で独立に出ています。**確度の高い言明は「渡す軸を増やしても、渡し方が“列挙”のままなら効かない」のほうです。**

---

## 5. 軸の書き方 —— 「確認する」 vs 「成り立たない例を挙げよ」

**ここが今回いちばん収穫がありました。40年前に、まさにこの差が明示的に設計されています。**

### 5-1. Parnas & Weiss, 4.4 節（一次確認済み、逐語）

> "The questionnaires are designed to make the reviewers **take an active stand** on issues and to use the documentation. An example is question C1, which requires the reviewer to use the document to find assumptions that justify the inclusion of each access program in the interface. The question is phrased in an **active** way (**"Which assumptions tell you ..."**), rather than **"Is there an assumption that justifies the implementation of this function?"** The **passive phrasing would give the designer little assurance that the reviewer read, understood, and thought about the document. Using the passive phrasing makes it too easy to say "yes."**"

実際の質問票（Figure 1, Review C）:
> C1 Which assumptions tell you that this function can be implemented as described?
> C2 Under what conditions may this function be applied? Which assumptions describe those conditions?
> C3 Is the behavior of this function, i.e., its effects on other functions, described in the assumptions?

同じ論文の 4.1 節相当:
> "It is also important to make the reviewer think hard about what he is reading rather than **skim it for obvious errors**. ... **The reviewers must be asked to provide justification for accepting or rejecting design decisions.**"

そして従来型レビューの欠陥リスト (7)(8):
> "(7) Reviewers are often asked to examine issues beyond their competence. They may be specialists in one aspect of the system, but they are asked to review the entire system."
> "(8) There is no systematic review procedure and **no prepared set of questions** to be asked about the design."

### 5-2. Porter らの実験は、この書き方の差を実際に測っている

Porter (1995) の設計は**この点で決定的**です（一次確認済み、逐語）:

> "The Scenarios are derived from the checklist by **replacing individual Checklist items with procedures designed to implement them.** As a result, Scenario responsibilities are distinct subsets of Checklist and Ad Hoc responsibilities."

**同じ内容が、書き方だけ変わっている**（範囲はむしろ Scenario のほうが狭い）。実物を並べると差が明白です。

Checklist 側（Appendix B、逐語）:
> "Are the goals of the system defined?"
> "Are the requirements clear and unambiguous?"
> "Have the software and hardware environments been specified?"

Scenario 側（Appendix C、逐語）:
> "**1. Identify all data objects mentioned in the overview** (e.g., hardware component, application variable, abbreviated term or function) (a) Are all data objects mentioned in the overview listed in the external interface section?
> **2. For each data object appearing in the external interface section determine the following information:** Object name: Class: ... Data type: ... Acceptable values: ...
> (d) **Can any data object definition be inconsistent** with the data object's type, acceptable values, failure value, etc.?"

および Incorrect Functionality Scenario:
> "**Develop an invariant for each system mode** (i.e. Under what conditions must the system exit or remain in a given mode)? (a) **Can the system** ..."

**構造**: 「(1) 作業をして中間成果物（一覧・表・不変条件）を作れ → (2) それに対して“〜でありうるか”を問え」。**"Can any ... be inconsistent" は、まさに「成り立たない入力を1つ挙げよ」型です。**

結果は前述のとおり **Scenario が +35%、Checklist は Ad Hoc と同等**。
**「確認する」と書いた表は、表が無いのと同じだった**、というのが、私が到達できた中で最も直接的な実証です。

### 5-3. 同じ原理の独立した現れ

**Degani & Wiener, Appendix A ガイドライン (4)**（一次確認済み、逐語）:
> "**Checklist responses should portray the desired status or the value of the item being considered (not just 'checked' or 'set').**"

**応答が情報を運ばなければならない。**「確認しました」は応答ではない、という航空側の同じ結論です。

**Chromium `docs/security/mojo.md`** — https://github.com/chromium/chromium/blob/main/docs/security/mojo.md
> "When receiving data from a less trusted process, treat the data as if it were **generated by a malicious adversary**."

**軸を「敵の立場を取れ」という形で書いている。** これは「確認せよ」ではなく、**反例を作る作業の指示**です。

**Chromium IPC review の3問** — https://chromium.googlesource.com/chromium/src/+/HEAD/docs/security/ipc-reviews.md
> "What are the endpoints of the changed IPCs?" / "What are the changes in capabilities being exposed over IPC?" / "**What breaks if an attacker provides malicious input?**"

**K8s PRR / W3C questionnaire** はどちらも **「はい/いいえで閉じない疑問文」**で統一されています（"How can someone using this feature know that it is working for their instance?" / "What information does this feature expose, and for what purposes?"）。W3C は運用上の注意として、**質問票そのものを仕様に貼るのではなく「答え」を出せ**と明記しています。

### 5-4. 反証側（正直に）

**Wurzel Gonçalves ほか (2022)** は、まさに「チェックリスト」と「明示的レビュー戦略（guided checklist）」を比較した事前登録実験で、**強い関係を確認できませんでした**（前掲）。示唆はあるが（単純な変更では guided checklist、複雑な変更では checklist が有利という傾向）、**「手続き化すれば必ず効く」とは言えません。** Hatton の留保（「表現と強制のされ方に決定的に依存しているかもしれない」）と併せて読むべきです。

---

## 6. 確認できたこと／確認できなかったことの整理

**確認できたこと（一次資料で逐語確認）**

1. 「変更の種類 → 軸」の表は実在し、**引く鍵は6種類**（パス / パス＋散文 / パス＋内容＋意味 / 設計要素の型 / 文書断面×専門 / リスク等級）ある。
2. rust-lang/rust は **124 件のパス→注意文の表**を実運用している。値の大半は「随伴して直すべきもの」。
3. 軸の増殖は**普遍的な問題**で、実務の対策は「追加コストを上げる（VP 承認）」「定期通読で削る」「等級・段階で必須範囲を絞る」「分割する」。**項目数の実証的な閾値は見つからなかった。**
4. **長すぎる表の失敗形は「無視」ではなく「勝手な間引き」**（NASA、81項目の事例）。**短すぎる表も暗記されて実物を見なくさせる。**
5. 事故駆動は Google SRE が明言している運用であり、それを補う方法として **(a) 生成的な軸（HAZOP / STRIDE-per-element / STPA）、(b) 軸を持たない全体レビュー役の併置（Parnas）、(c) 質問票の最後に「何を聞くべきだったか」を置く（W3C）** が確認できた。
6. **1人1軸の分割は、Porter 1995 で +35%。同実験で「1人に全部渡す（Checklist）」は Ad Hoc と差が無かった。** 分割しても担当外の欠陥検出は落ちなかった。効果はチーム水準で出る（Basili）。人数は2人で頭打ち（Rigby & Bird、Hatton）。
7. **書き方の差は測られており、大きい。** "Which assumptions tell you…" 対 "Is there an assumption…"（Parnas）、チェックリスト項目を手続きに置き換えた Scenario（Porter）。NASA も「応答は状態や値を述べよ、'checked' では足りない」。

**確認できなかったこと**

- チェックリストの**項目数と有効性の定量関係**を直接測った研究（存在を否定はできないが、今回の探索範囲では見つからず）。
- Google Tricorder の 10% 偽陽性基準の**一次記述**（CACM 403）。
- Gawande の「5〜9項目 / 60〜90秒」の**一次記述**。
- IEC 61882 のガイドワード表の**原文**（サンプルが画像）。
- NEJM 2本（Pronovost / Urbach）の**原文**。
- Ciolkowski メタ分析、Martin & Tsai N-fold の**原文**（有料）。

---

# 付録: 私たちの表に足す価値がありそうな軸の候補

**以下はすべて提案です。採用されていない前提で書いています。起票していません。判断はオーケストレーターと人間にあります。**

### A. 表の構造についての提案

**A-1. 値を「誰を呼ぶか」ではなく「何が成り立つべきか」にする。**
rust の `triagebot.toml` の 96/124 件が `message` を持っていた事実は、パスだけの表（CODEOWNERS 型）では軸を運べない、ということの実例だと読めます。

**A-2. 軸の文言を「〜を確認する」から「〜が成り立たない入力を1つ挙げよ」に寄せる。**
Parnas（"makes it too easy to say yes"）と Porter（同内容を手続きに書き換えて +35%、列挙のままなら ad hoc と同等）の2本が支持しています。**ただし Gonçalves 2022 は再現に失敗しており、確実ではありません。**
書式としては Porter の Scenario 形式（**「一覧を作れ → その一覧に対して “〜でありうるか” を問え」**）が、そのまま雛形になります。

**A-3. 引く鍵を「ファイル種別」だけにしない。** GitLab の3層（パス / コード内の記号 / 意味的条件）が実例。第3層を機械化しないまま文章で残すのは、逃げではなく設計上の選択だと読めます。

**A-4. 軸の本数を「工程段階」で絞る。** K8s PRR の `(R)` マーカー（alpha/beta/GA で必須範囲が変わる）は、総量を抑えつつ削らずに済ませる仕組みです。

**A-5. 軸を持たない「全体レビュー」を1枠だけ常設する。** Parnas の明示的な対策。焦点を鋭くした分の穴を、これで埋めています。

**A-6. 検証役への指示書の末尾に「この軸の表は、何を聞くべきだったか」を1問足す。** W3C 第22問。コストはほぼゼロで、表の更新を事故待ちにしないための経路になります。

**A-7. 表に「棄却」を正式な工程として認める。** STRIDE が小さい図で 18 脅威を生み、「大半は意味がない」と認めたうえで分析工程を本体に据えているのと同じ扱い。軸が空振りしたとき、**空振りだったと1行残す**ことを表の運用に入れる（`docs/PUNCHLIST.md` の「却下にも理由を1行」と同じ規律）。

**A-8. 軸を足すときのコストを上げ、定期的に削る。** Google の VP 承認と定期通読。Mdoro の規模なら「軸の追加は Decision Record か要件ID を根拠に要求する」で同等の効果が得られるかもしれません。

**A-9. 追加のたびに「順序」を再設計する。** Degani の指摘（新装備の追加は項目追加ではなく配置の再決定）。最重要の軸を先頭に置く（ガイドライン 10）。

### B. 生成的な軸（事故が起きていなくても立つ軸）の候補

Mdoro の性質（Mac が正本 / iPhone は表示端末 / 絶対時刻 / ローカル通信 / 読み取り専用のユーザー資産）に **STPA の UCA 4類型と STRIDE-per-element の考え方をそのまま当てた場合**、次の形の軸が機械的に生えます。**いずれも未採用の候補です。**

- **制御アクション × 4類型**: Mac→iPhone に流れる各コマンド／状態遷移について「(1) 送らない (2) 送る (3) 早すぎる・遅すぎる・順序が逆 (4) 継続しすぎる・止まりすぎる」の4通りを問う。3原則の2（iPhone がセッション終了を確定してはならない）と3（絶対時刻）に対しては、**(3) の「順序が逆」** が既存の軸で明示的に拾えているか、という問いが立ちます。
- **要素型 × 影響**: 「プロセス間を渡るデータ」型の要素（WebSocket の JSON）には、Chromium mojo と同じく **「相手が壊れている前提で読め」** という軸が自動で当たる。LAN 内前提でも、要素型から生える軸としては消えません。
- **ガイドワード × パラメータ**: `sessionEndAt` に対して NO / MORE / LESS / REVERSE / OTHER THAN を当てる、という総当たり。事故の履歴を要しません。

### C. 「随伴物」型の軸の候補

rust と Danger の実例に照らすと、この種の軸は**事故が起きる前に書ける**うえ、機械で引けます。Mdoro で対応しそうな形（**未検証・未採用**）:

- 共有コードを触ったとき → Mac 側と iPhone 側の**両方**が追随しているか（REQ-PRT-001 の趣旨）
- 条文を書き直したとき → **テスト名・フィクスチャ名・コメントの理由づけ**まで追随しているか（`CLAUDE.md` に既にある規律を、表の行として機械的に引けるようにする）
- ビルド設定に触れないはずの変更で `.xcodeproj` に差分が出ていないか（[0013](docs/decisions/0013-pbxproj-is-owned-by-xcode.md) の趣旨）
- `xcodebuild` を含む変更 → `-destination` が付いているか

### D. 割り当てについての提案

- **役を1体しか出さないなら、軸の分割の利得はほぼ期待できない**（Basili: 効果はチーム水準）。分割を入れるなら、**独立コンテキストの検証役を2体、別々の軸で**という形が、証拠に沿った最小構成です。
- **3体目以降は指摘が増えない可能性が高い**（Rigby & Bird、Hatton）。増やすより軸を変えるほうが効く見込み。
- **軸を渡しても、能力の高い読み手は自分の流儀に戻る**（Basili の "I reverted to what I normally do."、Hatton の "personalised internal methods"）。**指示書で「この軸で読んだ証跡（作った一覧・挙げた反例）を報告に貼れ」と要求すると、戻りを検出できる**（Parnas の「質問票への記入そのものが、読んだ証拠になる」という設計と同じ狙い）。
- **収集会議（役の報告をまとめる工程）は純増ゼロだった**という Porter の結果は、統合よりも**個々の報告の質**に投資すべき、と読めます。ただしこれは1985〜95年の対面インスペクションの話で、現在のオーケストレーション体制にそのまま当たるかは未検証です。

---

**主要出典一覧**

- Parnas & Weiss, Active Design Reviews — http://figforth.org.uk/library/p132-parnas.pdf （4.3 Classifying Reviewers / 4.4 Designing The Questionnaires / Figure 1, 2, 3）
- Porter, Votta, Basili, TSE 1995 — https://drum.lib.umd.edu/bitstreams/332d6328-bdce-4726-9102-e00bac748f9a/download （Abstract / II.A Detection Methods / IV. Summary / Appendix I–III）
- Basili ほか, Empirical Investigation of PBR — https://www.cs.umd.edu/~mvz/handouts/emp_pbr.pdf （Abstract / 5 / 6. Conclusions）
- Hatton, Testing the Value of Checklists in Code Inspections — https://www.leshatton.org/Documents/checklists_in_inspections.pdf （Abstract / 1.2 / 3. Conclusions）
- Rigby & Bird, FSE 2013 — https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/rigby2013convergent.pdf （Convergent Practice 4, Figure 5）
- Wurzel Gonçalves ほか, EMSE 2022 — https://d-nb.info/1264662815/34 （Abstract / 5.1 RQ1）
- Degani & Wiener, NASA CR-177549 — https://ntrs.nasa.gov/api/citations/19910017830/downloads/19910017830.pdf （3.1 / 5 / Appendix A）
- Leveson & Thomas, STPA Handbook — http://psas.scripts.mit.edu/home/get_file.php?name=STPA_handbook.pdf （Ch.1 Introduction / UCA の4類型）
- Google SRE Book Ch.27 + Appendix E — https://sre.google/sre-book/reliable-product-launches/ , https://sre.google/sre-book/launch-checklist/
- Chromium: code_reviews.md / code_review_owners.md / mojo.md / rule-of-2.md / ipc-reviews.md — https://chromium.googlesource.com/chromium/src/+/HEAD/docs/
- STRIDE-per-Element — https://learn.microsoft.com/en-us/archive/blogs/larryosterman/threat-modeling-again-stride-per-element
- W3C Self-Review Questionnaire — https://www.w3.org/TR/security-privacy-questionnaire/
- Kubernetes KEP テンプレート（PRR questionnaire） — https://github.com/kubernetes/enhancements/blob/master/keps/NNNN-kep-template/README.md
- GitLab Database Review — https://docs.gitlab.com/development/database_review/
- rust-lang/rust triagebot.toml — https://raw.githubusercontent.com/rust-lang/rust/master/triagebot.toml
- GitHub CODEOWNERS — https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
- Danger JS — https://danger.systems/js/