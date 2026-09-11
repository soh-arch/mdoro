# 軸はどこから来たか

`docs/ORCHESTRATION.md` §2 の床の表に、**2026-09-11 に4つの変更を入れた。**
この文書は、**その4つがどこから来て、何が反証で、どこまで自分で確かめたか**を残す。
**表そのものは `docs/ORCHESTRATION.md` にある。ここには置かない**（二重に持つと必ずずれる）。

起票は POL-214。

---

## 1. なぜ外に取りに行ったか

床の表には運用規則が1行ある —— **「この表は事故のたびに1行増やす。減らさない。」**

**これは、まだ踏んでいない筋には軸が立たない、という意味でもある。**

同じ運用が、外でも明言されている。Google の SRE Book、打ち上げチェックリストの章:

> "Every question's importance must be substantiated, ideally by a previous launch disaster."

**つまり Google にとって、事故駆動は「増やしすぎないためのゲート」である。網羅の仕組みではない。**
同じ章が、なぜゲートが要るのかも書いている:

> "In practice, there is a near-infinite number of questions to ask about any system, and it is easy for the checklist to grow to an unmanageable size."

> "In an effort to curb its growth, at one point, adding new questions to Google's launch checklist required approval from a vice president."

**増やさない側の理由は、無視されることではない。**Degani & Wiener が実測した失敗形は**勝手な間引き**である:

> "Therefore, a requirement to conduct a long and meticulous checklist for each flight may lead
> some to deviate from the prescribed procedures, performing only what he/she perceives as the
> critical items ("killer items" as some call them). … For example, one company's DC-9-50
> checklist (a short/medium range type aircraft) contained 81 check items for the ENGINE START,
> TAXI and TAKEOFF task-checklists."

**81項目にした結果、実施者は自分が重要だと思う項目だけを実施するようになった。**
**表が長くなると、使われなくなるのではなく、黙って間引かれる。**
**だから今回は、新しい行を1本に抑えた。**

**増やす側にも、増やさない側にも、外に前例がある。**そこで、調査役を2体出した
（読み取り専用・起票しない）。**採否はオーケストレーターが選び、人間が承認した。**

---

## 2. 採った4つ

### (1) 「してはならない」の行を立て、表の先頭に置いた

**この分野には専用の概念がある。**NASA Software Safety Guidebook（NASA-GB-8719.13）Appendix F.2:

> "To assure full coverage of all aspects of functional safety, it can be helpful to categorize
> system functions as two types: 1. Must work functions (MWFs) 2. Must not work functions (MNWFs)"

**「動かしてはいけない3原則」は、この語彙では MNWF リストである。**
別立てで書いてある理由が、外の分野で独立に定式化されていた。

**そして、警告が付いている:**

> "This criticality is usually expressed only in terms of the Must-Work nature of the system
> function, and often omits the Must-Not-Work functional criticality."

**「してはならない」の重大性は、仕様書から抜け落ちるのが常である。**

**足りていなかったのは、その先である:**

> "Must work and must not work functions often depend on the state of the system. Some functions
> can even change from one to the other as the system state changes. When designating an aspect
> of the system as must work or must not work, you also need to specify when these designations
> are valid."

**3原則そのものは無条件なので、ここは一見関係ない。だが状態依存の禁止は Mdoro にも実在する** ——
「設定変更が実行中のセッションの終了時刻を動かさない」は、**待機中は MWF、実行中は MNWF** である。
この形は、同じ文書の Appendix H.3（MSFC 由来の汎用安全要求）にそのまま載っている:

> "If an automated sequence is already running when a software inhibit associated with a hazardous
> command is activated, the sequence shall complete before the software inhibit is executed."

> "In the event that prerequisite conditions have not been met, the software shall reject the
> command and alert the crew, ground operators, or the controlling executive."

**2つ目は「拒否だけでなく通知まで一対で」と要求している。**版不一致で接続を拒む Mdoro の条文が、これに当たる。

**先頭に置いた理由**は Degani & Wiener（NASA CR-177549）Appendix A のガイドライン (10):

> "The most critical items on the task-checklist should be listed as close as possible to the
> beginning of the task-checklist, in order to increase the likelihood of completing the task
> before interruptions may occur. We note that this guideline could be in conflict with Nos. (8)
> and (9) above. In most cases where this occurs, this guideline (10) should take precedence."

**衝突したときどちらが勝つかまで書いてある。**触った場所の並びより、重要度が勝つ。

**この行が他の行とわざと重なるのも、同じ文書の (11) による:**

> "Critical checklist items such as flaps/slats, aim, etc., that might be reset prior to takeoff
> due to new information should be duplicated between task-checklists."

**重複を、効率の側は損失として測る**（Porter 1995 の結論4 —— 会議は純増ゼロ）。
**安全の側は意図的に選ぶ。**結論が逆である。
**この分野はこれを「壊れたら何が失われるか」で決めている。**3原則は利用者の資産が壊れる場所なので、後者を採った。

### (2) 時刻と状態遷移に、事故を待たない4つの形を当てた

**(1) が「まだ起きていない事故」に効くのは、それが構造から生えるからである。**
同じ性質を持つ語彙が、独立に4つの分野から出てきた。

| 出どころ | 持っている軸 | そこにしか無いもの |
| :---- | :---- | :---- |
| STPA の Unsafe Control Action | 送らない／送ってはならないときに送る／誤ったタイミング・順序／早く止めすぎる・長く続けすぎる | **持続時間を独立した軸に持つ** |
| HAZOP の時間ガイドワード | Early / Late / **Before / After** | **絶対的な早遅と別に「他と比べた順序」を持つ** |
| MIL-STD-1629A の汎用故障モード | Premature operation ／ **Failure to cease operation at a prescribed time** | **「所定の時刻に停止しない」が独立した故障モード** |
| SHARD | Omission / Commission / Early / Late / Value | Value を持つ |

**「所定の時刻に停止しない」が独立した故障モードとして立っているのは、タイマーそのものである。**

**採ったのは4つの形だけで、総当たりは採らなかった**（下の「採らなかったもの」）。

### (3) 条文を書き直したときの随伴物を、`docs/SPEC.md` の行に足した

**これは既に踏んだ事故で、しかも表に行が無かった。**

2026-09-02、REQ-PRT-005 を書き直した際、**同じ誤解の写しが3層に残った** ——
消去法で説明していたコメント、その理由づけ、そして**テスト名とフィクスチャ名**。
`CLAUDE.md` はこれを規律として持っているが、**床の表の `docs/SPEC.md` の行には無かった。**
**「事故のたびに1行増やす」と書いてある表に、この事故の行が付いていなかった。**

外の実例は rust-lang/rust の `triagebot.toml` である。**パスごとの注意文を124件持ち、うち96件が
`message` を持つ**（調査役が実物を読んで数えた。私は数え直していない）。
値が「誰を呼ぶか」ではなく**「この変更に伴って、別の場所も直っているか」**になっている。

ODC も独立に同じ軸を持つ —— `Internal Document` が9つのトリガーの1つとして、
プロローグとコードコメントを名指しで含む。

### (4) 軸の書き方を「確認する」から「作って、問う」に寄せた

**今回いちばん証拠が強く、そして表を1行も増やさない。**

Parnas & Weiss, *Active Design Reviews*（1985）4.4 節:

> "The question is phrased in an active way ("Which assumptions tell you ... "), rather than
> "Is there an assumption that justifies the implementation of this function?" The passive
> phrasing would give the designer little assurance that the reviewer read, understood, and
> thought about the document. Using the passive phrasing makes it too easy to say "yes.""

**Porter, Votta, Basili（1995）が測ったのは、これに近いが、同じではない差である。**

> "The Scenarios are derived from the checklist by replacing individual Checklist items with
> procedures designed to implement them. As a result, Scenario responsibilities are distinct
> subsets of Checklist and Ad Hoc responsibilities."

**チェックリストの各項目を、それを実行する手続きに置き換えたもので、担当範囲はむしろ狭い。**
4つの結論を全文で引く:

> "1. The fault detection rate when using Scenarios was superior to that obtained with Ad Hoc or
> Checklist methods -- an improvement of roughly 35%.
> 2. Scenarios helped reviewers focus on specific fault classes. Furthermore, in comparison to
> Ad Hoc or Checklist methods, the Scenario method did not compromise their ability to detect
> other classes of faults. (however, the scenarios appeared to be better suited to the fault
> profile of the WLMS than the CRUISE. This indicates that poorly designed scenarios may lead
> to poor inspection performance.)
> 3. The Checklist method -- the industry standard, was no more effective than the Ad Hoc
> detection method.
> 4. On the average, collection meetings contributed nothing to fault detection effectiveness."

**結論3 が、この変更の理由である** —— **「1人に全部の軸を渡す」は、軸を渡さないのと差が無かった。**
効いたのは**軸があること**ではなく、**軸が手続きになっていること**である。

**結論2 の括弧は、著者自身の但し書きである。**「軸を手続きにすれば効く」ではない。
**外れた手続きは、成績を下げうる。**

**⚠ そして、この実験は書き方だけを操作していない。**同じ論文が「方法」をこう定義している:

> "we define a fault detection method to be a set of fault detection techniques coupled with an
> assignment of responsibilities to individual reviewers."

**手続きにすることと、レビュアごとに担当を分けることが、定義の時点でひとまとめになっている。**
**したがって 35% が支持するのは、この2つの組である。書き方だけではない。**
**(4) を単独で採ったわけではない、ということは残しておく。**
（分けることの側は、下の §5 の材料に続く。）

航空側も独立に同じ結論に達している。Degani & Wiener のガイドライン (4):

> "Checklist responses should portray the desired status or the value of the item being considered
> (not just "checked" or "set")."

**作った一覧を報告に貼らせるのは、証拠のためだけではない。**
Brykczynski が117のチェックリストを集めて分析した結果:

> "Only two of the checklists in this survey actually suggest that a check-mark be placed next to
> the checklist item. For the most part, there is little verification that a reviewer actually
> performed any analysis relating to a checklist item."

**117のうち115は、そもそも「見た」ことを確かめる仕組みを持たない。形骸化を検出できない設計である。**

**検出したい事象は具体的にある。**Basili らの PBR 実験で、経験のある被験者はこう言った ——
**"I reverted to what I normally do."**（調査役の報告による。私は原典で確認していない）
**軸を渡しても、力のある読み手は自分の流儀に戻る。一覧を貼らせれば、戻ったことが見える。**

**⚠ 反証。** Wurzel Gonçalves ほか（EMSE 2022）はプロの開発者を対象にした事前登録実験で、
**この効果を再現できていない**（著者自身が検出力不足を限界として明記している。調査役の報告による）。
**「手続きにすれば必ず効く」ではない。**

---

## 3. 採らなかったもの

**却下にも理由を1行残す**（`CLAUDE.md`）。

| 採らなかったもの | 理由 |
| :---- | :---- |
| Perspective-Based Reading そのもの（Designer / Tester / User に視点を割る） | Basili の個人水準の効果は4条件中3条件で出ず、**出なかったのは一貫して実務に近い文書のほう**だった。Mdoro が扱うのはそちら側である |
| ODC の9トリガー・7 defect type を床に入れる | 語彙としては当たるが、**床は「触った場所 → 軸」でパスから引く表**であり、分類体系は引けない。天井に渡す語彙のほうが合う |
| HAZOP の7語を総当たりする | STRIDE が小さな図で18の脅威を生み、著者自身が「大半は意味がない」と認めた**同じ増殖**を起こす。時間・順序の4つだけを採った |
| チェックリストの項目数に上限を設ける | **調査役2体が探した範囲に、項目数と有効性の定量関係を直接測った研究が無かった。**「5〜9項目」「60〜90秒」はいずれも一次未確認である |
| GitLab 型の3層キー（パス＋コード内の記号＋意味的条件） | `Tools/axes-for.py` に第2のキー種別を足す実装が要る。**今回は道具を変えない。**有効なら次に回す |
| ODC の Backward / Lateral Compatibility を2行に分ける | Mdoro は版不一致で接続を拒否するので Backward 側が意図的に狭い。**今の1行で足りる** |
| 「減らさない」を撤回して定期的に削る（Google SRE の定期通読） | **床の行の多くは事故の記録でもあるので、削ると記録が消える。**⚠ **ただし今回足した4つの形は事故の記録ではないので、この理由はその行には効かない** —— **そこは空振りが続いたときに見直す対象である。**代わりに Degani の「追加のたびに並び順を決め直す」を採った |
| 二人ルール（two-person rule） | 一次資料に届いていない。かつ**merge は人間が行う**という既存の規律が同じ位置を占めている |

---

## 4. どこまで自分で確かめたか

**調査役の報告は、成果物で裏を取る**（`CLAUDE.md`）。
**この文書に逐語で引いた文は、原典の PDF をこの環境に取得し、私が本文で照合した。**
**表内のセルに置いた引用も含む**（§6 の3件は `> ` ではなく表の中にあるが、同じように照合してある）。

| 引用 | 出典 | 照合 |
| :---- | :---- | :---- |
| passive phrasing / "too easy to say "yes."" | Parnas & Weiss 4.4 | **確認した** |
| "we also ask a few people for overall reviews …" | Parnas & Weiss 3 | **確認した** |
| 結論1〜4（35% ／ Checklist は Ad Hoc と同等 ほか） | Porter, Votta, Basili 1995 IV | **確認した**（括弧の但し書きも含む） |
| "The Scenarios are derived from the checklist …" ／ "we define a fault detection method …" | Porter, Votta, Basili 1995 II | **確認した** |
| "no difference between two- and four-person inspections …" ／ 重なりの中央値が0 ／ "Our interpretation of these results …"（§5 の3件） | Porter, Siy, Mockus, Votta 1997 3.7・4 | **確認した** |
| MWF / MNWF の定義、"often omits …"、"specify when these designations are valid" | NASA-GB-8719.13 F.2 | **確認した** |
| "reject the command and alert …" ／ "the sequence shall complete before …" | NASA-GB-8719.13 H.3 | **確認した** |
| ガイドライン (4) (10) (11)（§2）、81項目の DC-9-50 と "killer items"（§1） | Degani & Wiener CR-177549 | **確認した** |
| "little verification that a reviewer actually performed any analysis" | Brykczynski 1999 2 | **確認した** |
| "even one more objective is included …" ／ "we eliminated checklists …" | Fagan 2002 | **確認した** |
| 事故駆動・near-infinite・VP 承認の3文 | Google SRE Book 27 | **確認した** |
| **STPA の Unsafe Control Action 4類型** | Leveson & Thomas, STPA Handbook | **⚠ 確認していない。**PDF は取得できたが本文が画像・字体埋め込みで、この環境の抽出器では文字が取れなかった。**調査役の報告のままである** |
| **HAZOP の時間ガイドワード（IEC 61882）** | IEC 61882:2016 | **⚠ 確認していない。**有料規格。調査役も原典に届かず、IEC 61882 を引用する二次資料から取っている |
| **MIL-STD-1629A の汎用故障モード** | MIL-STD-1629A | **⚠ 確認していない。**調査役も本文に届かず、検索結果の断片による |
| **SHARD の5語 ／ Value の Coarse・Subtle** | Pumfrey 1999 | **⚠ 確認していない。**学位論文 PDF はスキャン画像で抽出不能 |
| **rust-lang/rust の 124件・96件という数** | `triagebot.toml` | **⚠ 数え直していない。**調査役が実物を読んで数えた |
| **"I reverted to what I normally do."** | Basili ほか 1996 | **⚠ 確認していない** |
| **ODC の `Internal Document` トリガーがコメントを名指しで含むこと**（§2 (3)） | IBM ODC v5.2 | **⚠ 確認していない。**調査役の報告による |
| **Wurzel Gonçalves 2022 の再現失敗** | EMSE 2022 | **⚠ 確認していない** |

**⚠ 上の表は2種類の「確かめていない」を混ぜている。**
**原典に届いていない**（STPA・IEC 61882・MIL-STD・Pumfrey・Basili 1996・Gonçalves 2022）のと、
**原典には届いたが自分で数え直していない**（rust の `triagebot.toml` の 124件・96件）のは、別である。

**前者に乗っているのは (2) だけである。**
4つの形そのものは4分野で重なっており、**どれか1つの出典が崩れても形は残る**が、
**「STPA だけが持続時間を持つ」という主張は、届いていない資料に依存している。**
**後者に乗っているのは (3) だが、(3) の主たる根拠は外の実例ではなく、このリポジトリが実際に踏んだ事故である。**

---

## 5. 数の問題（検証役を何体出すか）

**まだ決めていない。**ここは材料だけ置く。

**Porter 1997 の正確な形は「増やしても無駄」ではない:**

> "There was no difference between two- and four-person inspections, but both performed better
> than one-person inspections."

**1体は足りない。2体で頭打ちになる。**そして同じ論文が、なぜかも測っている:

> "There was no difference in overlap between 1sX2p and 1sX4p inspections and both distributions
> had a median of 0."

> "Our interpretation of these results is that larger teams don't improve inspection performance
> because meeting gains do not increase as the number of reviewers increases, and because larger
> teams may suppress a[wareness] …"

**⚠ この実験は、視点を割り当てずに人を足している。**Porter 1995 の +35% は**割り当てたほうの測定**である。
**同じ研究グループが、両方を主張している。矛盾ではない。**

**逆向きの材料が2つある:**

- **「異なる軸」を名乗っても、実際には重なる。**Basili らのベン図では、Designer 視点が見つけた11件のうち
  **その視点固有だったのは2件、3視点すべてが見つけたものが5件**だった。
  **著者自身が、視点の直交性は仮定であって今後の課題だと書いている**（調査役の報告による。一次未確認）
- **ただし重なりは無駄ではない。** capture-recapture は**重なりが無ければ残存数を推定できない。**
  「2人で最低限、4〜5人で精度が許容水準」（同上）。
  **多く出すことの根拠は「もっと見つけるため」ではなく「あと何が残っているか言えるようにするため」にある**

---

## 6. 既に持っていたもの

**調査の収穫の一部は、Mdoro が独立に到達していた場所と重なった。変更はしていない。**

| Mdoro の規律 | 外での定式化 |
| :---- | :---- |
| **1 PR = 1つの目的** ／ 役は**直さない** | Fagan 本人（2002）: "experimentation has shown that when review/walkthrough activities are included in the inspection or, indeed, even one more objective is included, there is significant degradation in the defect detection effectiveness of inspections." |
| **`Tools/check-docs.py` と読解の分離** | Fagan（2002）: "As the inspection process evolved, we eliminated checklists and learned to concentrate human intelligence on finding those defects that testing with computers could only detect with a lot of effort, and to let computers find mechanical type defects." |
| **天井**（軸を渡さず「何を確かめるべきか」だけを聞く） | Parnas & Weiss: "Because our reviews are very tightly focused, we also ask a few people for overall reviews to decrease the chance that we overlook problems because we neglected to pose a question." |

**3つ目は、調査役2体が独立に「足すべきだ」と挙げてきたものである。既にあった。**
**ただし天井は4つの条件に当たるときだけ立つ。**
**引用が言っているのは、Parnas たちが自分たちの体制でそうしていた、ということである**
（"Because our reviews are very tightly focused, we also ask a few people for overall reviews"）。
**「鋭い軸を使うときは常にそうせよ」という規則までは、この1文からは出ない。**
**発動条件を広げるかどうかは、天井の軸出しと一緒に見る。ここでは決めていない。**

---

## 7. 出典

**本文を取得して照合したもの**

- Parnas, D. L. & Weiss, D. M. (1985) *Active Design Reviews: Principles and Practices*, ICSE-8 ——
  http://figforth.org.uk/library/p132-parnas.pdf
- Porter, A. A., Votta, L. G., Basili, V. R. (1995) *Comparing Detection Methods for Software
  Requirements Inspections: A Replicated Experiment*, IEEE TSE 21(6) ——
  https://drum.lib.umd.edu/bitstreams/332d6328-bdce-4726-9102-e00bac748f9a/download
- Porter, A. A., Siy, H., Mockus, A., Votta, L. G. (1997) *An Experiment to Assess the Cost-Benefits
  of Code Inspections in Large Scale Software Development*, IEEE TSE 23(6) ——
  https://users.ece.utexas.edu/~perry/education/SE-Intro/porter-tse23.pdf
- NASA (2004) *NASA Software Safety Guidebook*, NASA-GB-8719.13 ——
  https://standards.nasa.gov/sites/default/files/standards/NASA/Baseline/0/nasa-gb-871913.pdf
- Degani, A. & Wiener, E. L. (1990) *Human Factors of Flight-Deck Checklists: The Normal Checklist*,
  NASA CR-177549 —— https://ntrs.nasa.gov/api/citations/19910017830/downloads/19910017830.pdf
- Brykczynski, B. (1999) *A Survey of Software Inspection Checklists*, ACM SIGSOFT SEN 24(1) ——
  https://www.uv.mx/personal/ermeneses/files/2018/02/Checklists-Inspeccion.pdf
- Fagan, M. E. (2002) *A History of Software Inspections*, in *Software Pioneers* ——
  https://eden.dei.uc.pt/~mvieira/Fagan02.pdf
- Google SRE Book, ch.27 *Reliable Product Launches at Scale* ——
  https://sre.google/sre-book/reliable-product-launches/

**調査役の報告のままで、私が原典に届いていないもの**

- Leveson, N. & Thomas, J. (2018) *STPA Handbook* —— http://psas.scripts.mit.edu/home/get_file.php?name=STPA_handbook.pdf
- IEC 61882:2016 *Hazard and operability studies* —— https://webstore.iec.ch/en/publication/24321
- Pumfrey, D. J. (1999) *The Principled Design of Computer System Safety Analyses* —— https://etheses.whiterose.ac.uk/9797/
- Basili, V. R. ほか (1996) *The Empirical Investigation of Perspective-Based Reading*, EMSE 1(2) ——
  https://www.cs.umd.edu/~mvz/handouts/emp_pbr.pdf
- Wurzel Gonçalves, P. ほか (2022) *Do explicit review strategies improve code review performance?*,
  EMSE —— https://d-nb.info/1264662815/34
- Petersson, H. ほか (2004) *Capture-recapture in Software Inspections after 10 Years Research*, JSS ——
  https://wohlin.eu/jss04-1.pdf
- MIL-STD-1629A (1980) —— https://everyspec.com/MIL-STD/MIL-STD-1600-1699/MIL_STD_1629A_1556/
- rust-lang/rust `triagebot.toml` —— https://raw.githubusercontent.com/rust-lang/rust/master/triagebot.toml

---

## 8. 天井を一度走らせた（POL-217・2026-09-11）

**天井は手順であって表ではない** ——「差分と成果物を渡し、指摘は求めず、**何を確かめるべきかだけ**を答えさせる」。
**この手順には、走らせた記録が1本も無かった。**

**当てたのは教材B の差分**（REQ-PRT-005 の1条）。**同じ対象に12本の記録があり、比較できる唯一の点である。**
**モデルは Opus**（人間の指示）。**渡したのは3つだけ** —— 改訂履歴を落とした差分、第0章を落とした仕様書（1,273行）、
`docs/` を外した checkout。**床の軸は渡していない**（手順の定めるところ）。**本数も指定していない。**

### 出た数

| | 本数 |
| :---- | --: |
| **床**（`docs/SPEC.md` の行） | **4** |
| **天井**（Opus） | **16**（A群5・B群6・C群5） |

**「床より天井を多めに」という指示は、目標として渡さずに満たされた。**

### 2本が、既知の2件を名指しした

**A-1** —— 版の違う2台が交換しうるメッセージを一覧にさせ、こう問う:

> その一覧は `hello` とその拒否の**2本だけ**か。認証前・接続確定前に応答してしまう種別（時刻同期・生存確認など）が1本でもあれば、「唯一やり取りするのは」は事実として成立しない。

**これは教材B の期待される指摘そのものである。**`b79b76c` の `docs/SPEC.md` 第0章にはこうある:

> **版の違う2台がやり取りする唯一の場面は `hello` とその拒否**であり（認証前でも `timeSyncPing` には応答が返る）

**12本が誰も出せなかったものに、軸出しの側が届いた。**
**ただし「出した」のではなく「確かめる先を指した」のである。**A-1 は答えを述べていない。

**A-2** —— 交換しうるメッセージのフィールドを、値域が閉じているか開いているかで表にさせ、こう問う:

> **Mac 側が受け取る側**に、閉じた値域のフィールドは1つでも存在するか。存在しないなら、追記文が「そこで未知の値を受け取っても」と想定している事象は、その方向では**実装上そもそも発生しえない**。

**これは12本目（差分を渡した回）が実際に出し、検証して真だった指摘と同じものである。**

### ⚠ A群は、私が渡したヒントの形をしている

**指示文に、私はこう書いた:**

> また、**条文の理由づけが、実装上ありえない事象を根拠にしていた**という型の欠陥も過去にありました。

**これは `CLAUDE.md` に記録がある一般的な失敗の型であって、この条文について言ったのではない。**
**それでも、A群5本はすべてこの型の展開である。**

**手順は「自分が立てた軸は渡さない」と定めている。**私が渡したのは軸ではなく**失敗の型**だが、
**返ってきたものがその型の形をしている以上、同じ注意が当たる。**
**A-1・A-2 を「Opus が独力で見つけた」と読んではならない。**

**分離するには、ヒントを外して同じ条件でもう1本走らせるしかない。走らせていない。**

### 第三段に対する含み

**A-1 をそのまま検証役に渡すと、渡した側が答えの在り処を教えたことになる。**
**測れるものが変わる** —— 「体制が欠陥を見つけられるか」ではなく、
**「指された先を、根拠を引いて確かめられるか」**になる。

**後者は、第二段が測れなかったものである**（§11 の訂正 ——「分かれ目は『読むか』ではなく『読んだものを根拠として引くか』だった。この教材は後者を測る設計になっていない」）。
**つまり、これは劣化ではなく別の測定である。どちらを測るかは決めていない。**

### 走らせた側の申告

**Opus は `/home/user/mdoro/` を一切開いていないと申告し、開いたファイルを全部列挙した**
（`grep` / `ls` だけで触れたものも別枠で挙げている）。
**これは申告であって証明ではない。**サブエージェントは実際には読める（POL-210）。

**Opus 自身の懸念**（採用されていない前提で書かれたもの）: A-1・A-2・B-1・B-4 は実装を1箇所見れば真偽が決まる形なので、
**実出力を報告に貼らせないと「確認した」で終わる種類の軸である。**
—— これは §2 (4) で床に入れた規律と同じことを、独立に言っている。
