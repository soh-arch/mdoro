調査を完了しました。以下、報告です。

---

# レビュー・検証における「視点の割り当て」に関する調査報告

## 0. 到達状況の要約

**本文を実際に読んで確認できた一次資料**（PDF を取得しテキスト抽出）: Basili ら PBR 実験、Porter/Votta/Basili 1995、Porter ら 1997、Parnas & Weiss「Active Design Reviews」、IBM ODC v5.2 仕様書、NASA-GB-8719.13、Degani & Wiener NASA CR-177549、Brykczynski チェックリスト調査、Petersson ら capture-recapture、Thelin ら UBR 実験、Fagan 本人の回顧（Software Pioneers 収録）。

**到達できなかったもの**は §8 に列挙しました。特に **Fagan 1976 原論文そのもの**、**IEC 61882 本文**、**Pumfrey 学位論文本文**（スキャン画像で抽出不可）、**Ciolkowski のメタ分析**、**Regnell ら「Are the perspectives really different?」本文** には届いていません。

---

## 1. 視点を分けて割り当てると、発見率は本当に上がるのか

### 1-1. 上がるという実証

**Porter, Votta, Basili (1995), IEEE TSE 21(6):563-575**
出典 PDF: https://drum.lib.umd.edu/bitstreams/332d6328-bdce-4726-9102-e00bac748f9a/download

要求仕様に対して Ad Hoc / Checklist / Scenario（欠陥クラス別の手順書）を比較した対照実験。2回実施、各24名。結論部（V章直前）の原文4点：

> 1. The fault detection rate when using Scenarios was superior to that obtained with Ad Hoc or Checklist methods — an improvement of roughly 35%.
> 2. Scenarios helped reviewers focus on specific fault classes. Furthermore, in comparison to Ad Hoc or Checklist methods, the Scenario method did not compromise their ability to detect other classes of faults.
> 3. The Checklist method — the industry standard, was no more effective than the Ad Hoc detection method.
> 4. On the average, collection meetings contributed nothing to fault detection effectiveness.

**これがこの分野で最も強い「視点分割は効く」証拠**です。ただし同じ結論2の括弧内に、重要な但し書きがあります：

> (however, the scenarios appeared to be better suited to the fault profile of the WLMS than the CRUISE. This indicates that **poorly designed scenarios may lead to poor inspection performance**.)

つまり **「視点を分ければ上がる」のではなく「その成果物の欠陥分布に合った視点を分ければ上がる」**。視点の設計が外れれば効果は消えます。

さらに注目すべきは結論3です。**チェックリストは ad hoc（無手順）と有意差がなかった**。視点分割の効果は「手順があること」ではなく「役割ごとに異なる手順があること」に帰属しています。

---

**Basili ら (1996)「The Empirical Investigation of Perspective-Based Reading」, Empirical Software Engineering 1(2):133-164**
出典 PDF: https://www.cs.umd.edu/~mvz/handouts/emp_pbr.pdf

NASA/GSFC の professional developer を被験者にした PBR 実験。視点は **Designer / Tester / User** の3つ。各視点は単に「注意して読む」のではなく、**その視点固有の成果物を作らせる**のが要点です：

> the team member reading from the perspective of the tester would design a set of tests for a potential test plan and answer questions arising from the activities being performed. Similarly, the team member reading from the perspective of the developer would generate a high level design, and the team member representing the user would create a user's manual.

**チームの結果**（順列検定。3視点1人ずつの和集合を「チーム」としてシミュレート）:

| 実験/文書ドメイン | p値 |
| :--- | :--- |
| Pilot / Generic | 0.0660 |
| Pilot / NASA | **0.4340** |
| 1995 / Generic | 0.0007 |
| 1995 / NASA | 0.0390 |

要旨の主張は「Teams applying PBR are shown to achieve significantly better coverage of documents than teams that do not apply PBR.」で、4条件中3条件で支持されています。

### 1-2. 上がらないという実証（同じ論文の中にある）

**同じ論文の「個人」分析**では、結果はかなり弱くなります：

| 実験/文書ドメイン | 読み方の主効果 p値 | 備考 |
| :--- | :--- | :--- |
| Pilot / Generic | 0.2148（有意でない） | ただし平均では21%改善 |
| Pilot / NASA | **0.9629** | ほぼ完全に差なし |
| 1995 / Generic | 0.0019（有意） | PBR 32.14 vs 通常 24.64 = 30%改善 |
| 1995 / NASA | **0.4755** | 差なし |

原文（3.2.2）:

> The analysis, summarized in Table 3, failed to reveal a significant main effect both for the reading technique (p = 0.9629) and the document reviewed (p = 0.7109).

**4条件中3条件で個人レベルの効果は検出できていません。** しかも**効果が出なかったのは一貫して NASA ドメイン（実務に近い現実の文書）のほう**で、効果が出たのは汎用の練習用文書（ATM・自動販売機）でした。「本物の仕様書ほど効かなかった」というのは、この分野で繰り返し出てくる不都合な結果です。

### 1-3. 視点は本当に「直交」しているのか（重なりの実測）

同論文 3.3 節が、**視点別ベン図の実数**を出しています。これは私が見つけた中で最も直接的なデータです：

> ATM reviewers using the design perspective in the 1995 run found 11 defects in total: two were defects that no other perspective caught, three defects were also found by testers, one defect was also found by users, and **five defects were found by at least one person from each of the three perspectives**.

つまり **Designer 視点が見つけた11件のうち、その視点固有だったのは2件（18%）、3視点全部が見つけたものが5件（45%）**。重複がかなり大きい。

NASA_A 文書（1995）のベン図の数値は `0, 1, 1, 1, 0, 4, 8` で、8件が広く共有され、単独視点固有はほぼゼロです。

著者自身も節の冒頭で「perspectives did not overlap」が成立しているかは**今後の課題**だと明記しており、直交性は**仮定であって実証されていない**と読むのが正確です。

なお検索経由で、Regnell, Runeson, Thelin (2000)「Are the Perspectives Really Different?」(Empirical SE 5(4):331-356) が、**複製実験では3視点のうち2つがほぼ同じ欠陥集合を見つけ、しかもその文書こそ PBR がチェックリストに勝てなかった唯一のケースだった**と報告していることが確認できました。ただし**本文には到達できていません**（§8）。

### 1-4. 視点より「何を優先して読むか」のほうが効く可能性

**Thelin, Runeson, Wohlin (2003)「An Experimental Comparison of Usage-Based and Checklist-Based Reading」, IEEE TSE 29(8)**
出典 PDF: https://www.wohlin.eu/tse03.pdf

Usage-Based Reading（UBR）は、ユーザー視点の **use case を重要度順に並べて、重要なものから読ませる**手法。チェックリスト読みと比較して：

- class A（最重要）欠陥を**時間あたり約2倍**検出
- class A&B を時間あたり **70%多く**、総量で **51%多く**検出
- **class C（重要度の低い欠陥）ではチェックリストのほうが効率も効果も上**
- UBR は全欠陥の 13% を、CBR は 21% を見逃した

**「視点を分ける」よりも「重要な順に読む」ほうが、重大欠陥の発見では効いている**可能性を示す結果です。逆に言えば、視点分割は「軽微な欠陥まで含めた総数」では負けることがある。

### 1-5. 会議は効果に寄与していない

Porter 1995 の実測値（V章）:

- meeting gain rate（会議で初めて見つかった欠陥の率）: Votta の報告値は **3.9 ± 0.7%**
- meeting loss rate（個人が見つけたのに会議で報告されなかった率）: **6.8 ± 1.6%**（WLMS）、**7.7 ± 1.7%**（CRUISE）
- net meeting improvement: **-0.9 ± 2.2**（WLMS）、**1.2 ± 1.7**（CRUISE）

つまり **会議の利得は損失に食われて実質ゼロかマイナス**。Basili らも PBR 実験でこれを引いて「we present no conclusions about the effects of PBR team meetings in practice」として、そもそもチーム会議を行わず**名目チーム（個人結果の和集合）**で評価しています。

---

## 2. 何人・何視点が適正か

### 2-1. 人数を増やしても上がらない（最も強い実証）

**Porter, Siy, Mockus, Votta (1997)「An Experiment to Assess the Cost-Benefits of Code Inspections in Large Scale Software Development」, IEEE TSE 23(6):329-346**
出典 PDF: https://users.ece.utexas.edu/~perry/education/SE-Intro/porter-tse23.pdf

実際の商用開発の中で、1人／2人／4人 × 1セッション／2セッション × 修正あり／なし を組み合わせた長期実験。原文：

> The effect of increasing team size is suggested by comparing the effectiveness of all 1-session inspections (1sX1p, 1sX2p, and 1sX4p inspections). **There was no difference between two- and four-person inspections**

> **Increasing team size does not always improve per[formance]**

> 1) increasing the number of reviewers did not necessarily lead to increased defect discovery, 2) **splitting one large team into two smaller teams did not increase** [effectiveness]

> Since there is no difference between the intervals, team size alone did not affect interval.

**2人と4人で差がない。** これは「視点を足せば足すほどよい」という直感の、この分野で最も直接的な反証です。

### 2-2. 何人なら足りたかを「後から測る」手法

**Petersson, Thelin, Runeson, Wohlin (2004)「Capture-recapture in Software Inspections after 10 Years Research」, JSS**
出典 PDF: https://wohlin.eu/jss04-1.pdf

レビュー後に「まだ何件残っているか」を推定する方法。人数についての知見：

> From the accuracy point of view, the best would be to have a large number of reviewers. Some studies have shown that **at least four to five reviewers should participate in order to make the accuracy acceptable** (Briand et al., 2000; Miller, 1999). Hence, some investigations have been focused to improve the performance of estimations when having few reviewers. **To get any overlap there must be data from at least two reviewers.**

> For four reviewers and more, Mh-JK is the most preferable model ... **Mh-JK ... is non-robust in the case with two reviewers and produces underestimates.**

重要な非対称性があります：**欠陥を見つけるだけなら2人で足りる（§2-1）が、「あとどれだけ残っているか」を推定するには4〜5人要る。** 重なりがなければ残存推定ができないので、**重複は無駄ではなく測定器**である、という位置づけです。

### 2-3. 視点を細かくすると「問いを立て忘れた場所」が漏れる

**Parnas & Weiss (1985)「Active Design Reviews: Principles and Practices」, ICSE-8 / JSS 7(4):259-265**
出典 PDF: http://figforth.org.uk/library/p132-parnas.pdf

役割割り当ての元祖と言ってよい論文。重複と漏れのトレードオフについて、著者自身が明示的な緩和策を書いています：

> Because our reviews are very tightly focused, **we also ask a few people for overall reviews to decrease the chance that we overlook problems because we neglected to pose a question.**

**視点を絞ることの副作用は「問いを立て忘れた領域が誰の担当でもなくなること」であり、それを塞ぐために「軸なしの全体レビュー」を数人に別立てで頼む**、と。視点分割を採る場合、これは一緒に採らないと穴が開くタイプの対策です。

同論文の人数運用：

> In scheduling our reviews we try not to require any one reviewer to perform one kind of review for all sections of the document. ... **It is rare that one reviewer is able or asked to perform more than one kind of review.**

**1人1軸。** A-7E の Device Interface Module では、4種のレビュー（A: 仮定の妥当性 / B: 仮定の十分性 / C: 仮定と機能の整合 / D: アクセス関数の妥当性）に対し4種の reviewer（Device Expert / Device Programmer / Avionics Programmer / A-7 Requirements Expert）を割り当てています。

### 2-4. 「経験」は効かない

Basili ら PBR 実験 3.4 節：

> the relationship between PBR defect rates and experience is weak. **Reviewers with more experience do not perform better than reviewers with less experience.** On the contrary, it appears that some less-experienced reviewers have learned to apply PBR better.

相関係数は Spearman / Pearson どちらも **どのケースでも 35% を超えなかった**。役割年数を視点割り当ての根拠にする直感は、このデータでは支持されません。

（Parnas & Weiss はこれと整合する割り当てをしています。Avionics Programmer の資格要件に「**a lack of information on the specific devices may be advantageous**」＝その装置を知らないほうが有利だ、と書いている。純粋な論理整合チェック役には「知らないこと」が資産になる、という設計です。）

---

## 3. 状態機械／分散2ノード／時刻同期／プロトコル版に伝統的に当てられている視点

### 3-1. HAZOP の guide word

HAZOP は **「guide word + パラメータ = 逸脱」** という機械的な組み合わせで網羅を作る方式です。

基本 guide word（Primatech の解説、および IEC 61882 を引く PQRI 訓練資料の両方で一致）:

| guide word | 意味 |
| :--- | :--- |
| No / Not / None | 設計意図の完全な否定 |
| More | 量的増加 |
| Less | 量的減少 |
| As well as | 質的増加（余分なものが加わる） |
| Part of | 質的減少（一部が欠ける） |
| Reverse | 論理的逆 |
| Other than | 完全な置換 |

出典: https://www.primatech.com/technical/pt-notes/170-understanding-hazop-deviations （"Guideword + Parameter = Deviation" を明記）

**時間・順序の guide word** は、PQRI の HAZOP 訓練資料が IEC 61882 を引用して列挙しています：

> Some common HAZOP guide words include: No or not / Other than / More / **Early** / Less / **Late** / As well as / **Before** / Part of / **After** / Reverse (of intent)

出典: https://pqri.org/wp-content/uploads/2015/08/pdf/HAZOP_Training_Guide.pdf （p.4、"According to IEC Standard 61882" の記述あり）

**Early / Late / Before / After が標準語彙として独立に存在する**ことが、時刻同期を持つ系にとってはそのまま使える点です。

### 3-2. SHARD ── HAZOP をソフトウェアのデータフローに移したもの

SHARD (Software Hazard Analysis and Resolution in Design) は、**コンポーネント間の情報の流れ1本ごとに** guide word を当てます。guide word は：

**Omission / Commission / Early / Late / Value**

出典（査読論文が Pumfrey 1999 を引いて明記）: https://www.frontiersin.org/journals/robotics-and-ai/articles/10.3389/frobt.2021.667316/full
原典: Pumfrey, D. J. (1999) *The Principled Design of Computer System Safety Analyses*, University of York, PhD thesis. https://etheses.whiterose.ac.uk/9797/

Value をさらに **Coarse（明らかに不正な値）/ Subtle（値域としては正当だが誤っている値）** に分ける記述が二次資料に複数ありますが、**一次資料では確認できていません**（§8）。

この Coarse/Subtle の区別は、仮に二次情報でも、Mdoro にとっては意味があります。`sessionEndAt` が 1970 年になっていれば Coarse で誰でも気づくが、**5分ずれているだけなら Subtle で誰も気づかない**。

### 3-3. STPA の Unsafe Control Action 4類型

**Leveson & Thomas (2018)「STPA Handbook」**
出典 PDF: https://www.flighttestsafety.org/images/STPA_Handbook.pdf

制御アクション1つごとに4つの問いを当てる：

1. 必要な制御アクションが**提供されない**
2. 提供**されてはならないときに提供される**
3. **誤ったタイミング、または誤った順序**で提供される
4. **早く止めすぎる／長く続けすぎる**

**4番目は「持続時間」を独立した軸として立てている**点が、タイマーを扱う系にとって特徴的です。HAZOP にも SHARD にも「duration」の語はなく、STPA だけが持っています。

### 3-4. ODC の欠陥トリガー ── 「プロトコル版」に直接当たる語がある

**IBM「Orthogonal Defect Classification v5.2 for Software Design and Code」(2013)**
出典 PDF: https://s3.us.cloud-object-storage.appdomain.cloud/res-files/70-ODC-5-2.pdf

Design Review / Code Inspection に割り当てられる**トリガーは9つ**で、組織はアクティビティを定義してよいがトリガーは定義し直してはならない、と明記されています：

> Note that although the organization defines their activities, **they do not define or redefine the triggers. The only triggers to choose from are those listed above.**

9つのトリガー（本文の定義から抜粋）：

| トリガー | 定義（原文抜粋） |
| :--- | :--- |
| **Design Conformance** | comparing the design element or code segment being inspected with its specification in the preceding stage(s) |
| **Logic/Flow** | uses knowledge of basic programming practices and standards to examine the flow of logic or data to ensure they are correct and complete |
| **Backward Compatibility** | identify an incompatibility between the function described by the design document or the code, and that of **earlier versions of the same product or component** |
| **Lateral Compatibility** | detects an incompatibility between ... the code, and the **other systems, products, services, components, or modules with which it must interface** |
| **Concurrency** | the serialization necessary for controlling a shared resource ... including the serialization of multiple functions, threads, processes |
| **Internal Document** | incorrect information, inconsistency, or incompleteness within internal documentation（プロローグ・コードコメント） |
| **Language Dependency** | language specific details of the implementation |
| **Side Effects** | foresee some system, product, function, or component behavior ... **outside of the scope of the component or function** with which the code under review is associated |
| **Rare Situation** | foresee some system behavior which is not considered or addressed by the documented design ... associated with **unusual configurations or usage** |

**Backward Compatibility と Lateral Compatibility が独立したトリガーとして立っている**のが重要です。これはまさに「プロトコルに版番号があり、非互換なら接続を拒否する」系に当たる、既製の視点です。

また ODC の **Defect Type** 側には **Timing/Serialization** が独立して存在します：

> **Timing/Serialization**: Necessary serialization of shared resource was missing, the wrong resource was serialized, or the wrong serialization technique was employed.

**Qualifier**（Missing / Incorrect / Extraneous）が defect type と直交して掛かる構造も特徴的です：

> **Missing**: The defect was due to an omission
> **Incorrect**: The defect was due to a commission
> **Extraneous**: The defect was due to something not relevant or pertinent

「欠落」「誤り」「余分」の3値を全 defect type に掛ける ── SHARD の Omission/Commission と同じ発想が、欠陥分類側からも独立に立ち上がっています。

### 3-5. 状態機械そのものに対する伝統的視点

- **Chow (1978)「Testing Software Design Modeled by Finite-State Machines」IEEE TSE SE-4(3):178-187** ── W-method。書誌のみ確認、本文 PDF はスキャン画像で抽出不可（§8）。要点は「**実装が仕様より余分な状態を持っている可能性**まで含めて検証する」こと。
  https://dl.acm.org/doi/abs/10.1109/Tse.1978.231496

- **Binder (2000)「Testing Object-Oriented Systems」の sneak path testing** ── 「その状態では起きないはずの遷移を、実際に起こそうとしてみる」テスト。二次資料で確認：「Sneak-path testing helps to examine the unspecified behavior of the system」。一次未確認（§8）。

- **MIL-STD-1629A の generic failure mode 一覧**（FMECA）── 検索スニペット経由で確認、一次未到達：Premature operation / Failure to operate at a prescribed time / Intermittent operation / **Failure to cease operation at a prescribed time** / Degraded output or operational capability。
  https://everyspec.com/MIL-STD/MIL-STD-1600-1699/MIL_STD_1629A_1556/

  「所定の時刻に動作を開始しない」「**所定の時刻に動作を停止しない**」が別々の故障モードとして立っているのは、タイマーそのものです。

- **NASA-GB-8719.13 の「Software causes」6分類**（Appendix F, Hazard Report の記入項目）── 本文で確認：
  > Software causes include: o Failure to detect a problem o Failure to perform a function o **Performing a function at the wrong time, out of sequence, or when the program is in the wrong state** o Performing the wrong function o Performing a function incompletely o Failure to pass along information or messages

  出典 PDF: https://standards.nasa.gov/sites/default/files/standards/NASA/Baseline/0/nasa-gb-871913.pdf

---

## 4. 「破ると外部の資産が壊れる」種類の要件に当てられている視点

ここが調査で最も収穫のあった領域です。この分野には**専用の概念が2つ**あります。

### 4-1. Must Not Work Function（MNWF）

**NASA-GB-8719.13, Appendix F.2** ── 本文から：

> To assure full coverage of all aspects of functional safety, it can be helpful to categorize system functions as two types: 1. Must work functions (MWFs) 2. **Must not work functions (MNWFs)**
> Must not work functions are aspects that should not occur, if the system is functioning correctly. In fact, if they do occur, they could lead to a hazardous situation or other undesired outcome.

決定的に重要なのは、この直後の一節です：

> **Must work and must not work functions often depend on the state of the system. Some functions can even change from one to the other as the system state changes.** When designating an aspect of the system as must work or must not work, **you also need to specify when these designations are valid.** Open furnace door is a must work when changing out a test sample, but it is a must not work when the experiment is operating and the furnace is at full temperature.

そして、実務上の失敗パターンが名指しされています：

> This criticality is usually expressed only in terms of the Must-Work nature of the system function, and **often omits the Must-Not-Work functional criticality.**

**「してはならないこと」の重大性は、仕様書から抜け落ちるのが常である**、と。これは「動かしてはいけない3原則」のような条文が、なぜ仕様書の本文から独立して別立てで書かれる必要があるのか、の理屈になります。

### 4-2. 「誤用の仮定」を明示的なリストとして書く（Parnas & Weiss）

Active Design Reviews の中核に、**レビュー可能性は文書構造で作る**という主張があります：

> A basic principle used in engineering is that **redundant information is needed to perform error checking.**
> **Two lists of assumptions are included for each module.** One is a list of basic assumptions about the module, i.e., information that designers of the module assume will never change. The second is **a list of assumptions that describe incorrect usage of the module, i.e., usage that the designers assume should not occur.**

つまり「正しい使い方の仮定」と「**起きてはならない使い方の仮定**」を別々のリストとして文書に置き、それを本文と突き合わせることで欠落・矛盾を検出する。

> Omitted access programs, parameters, undesired events, and program effects are examples of missing information that we can detect by including redundancies.

**冗長な明示が検査を可能にする**という主張です。「Task.md へは一切書き込まない」を条文として書いておくこと自体が、この意味では検査装置です。

### 4-3. 「前提条件を満たさなければ拒否して通知せよ」という条文型

NASA-GB-8719.13, Appendix H.3「Generic Software Safety Requirements From MSFC」（MSFC 由来の汎用安全要求チェックリスト）から、**Mdoro の性質に直接当たる条項**を本文から抜き出します：

> **Prerequisite conditions (e.g., correct mode, correct configuration, component availability, proper sequence, and parameters in range) for the safe execution of an identified hazardous command shall be met before execution. In the event that prerequisite conditions have not been met, the software shall reject the command and alert the crew, ground operators, or the controlling executive.**

> **If an automated sequence is already running when a software inhibit associated with a hazardous command is activated, the sequence shall complete before the software inhibit is executed.**

> **The state of software inhibits shall remain unchanged after the execution of an override.**

> **Software shall initialize, start, and restart replaceable units to a safe state.**

> **Software termination shall result in a safe system state.**

> **Software shall provide proper sequencing (including timing) of safety-critical commands.**

> For systems solely using software for hazard risk mitigation, software shall require **two independent command messages** for a commanded system action that could result in a critical or catastrophic hazard.

2番目と3番目の条項に注目してください。**「実行中のシーケンスに、後から入った設定変更を割り込ませない」「override を通しても inhibit の状態は変えない」**は、Mdoro の「設定変更が実行中のセッション終了時刻を動かさないこと」と**同じ形の条文**です。この分野ではこれが汎用チェックリスト項目として定式化されています。

### 4-4. 二人ルール（Two-person rule / Four-eyes principle）

不可逆な操作に対して伝統的に当てられている、もう一つの視点。単独の人物では実行できないようにする構造的統制です。核兵器運用（AFI 91-104）が典型例。ソフトウェアでは「戻せない操作（本番データへの復元、環境削除）」に適用する、という整理が見られます。
出典: https://en.wikipedia.org/wiki/Two-person_rule

一次資料には当たっていません（§8）。

---

## 5. チェックリストが形骸化する条件と、それを避ける設計

### 5-1. 形骸化の実証 ── 医療の大規模な否定結果

**肯定側**: Haynes ら (2009)「A Surgical Safety Checklist to Reduce Morbidity and Mortality in a Global Population」NEJM 360:491-499
死亡率 **1.5% → 0.8%**（P=0.003）、入院合併症 **11.0% → 7.0%**（P<0.001）。
https://www.nejm.org/doi/abs/10.1056/NEJMsa0810119

**否定側**: Urbach ら (2014)「Introduction of Surgical Safety Checklists in Ontario, Canada」NEJM
オンタリオ州101病院、導入前 109,341件 / 導入後 106,370件。
合併症 **3.86% → 3.82%**、30日死亡 **0.71% → 0.65%**、いずれも統計的に有意でない。**101病院のうち、死亡リスクの有意な低下を示した病院は一つもなかった**。
https://www.nejm.org/doi/full/10.1056/NEJMsa1308261

**同じチェックリストが、片方では効き、片方ではまったく効かなかった。** 事後の議論では「実施率の過大報告」「嫌々ながらの遵守」が原因として挙げられています（一次資料未確認）。

**この対比が示すのは、チェックリストの効果は項目の中身ではなく実施の質に支配されるということ**です。同じ紙が、運用が壊れれば数値としてゼロになる。

### 5-2. 形骸化する条件 ── ソフトウェア側の実測

**Brykczynski (1999)「A Survey of Software Inspection Checklists」ACM SIGSOFT SEN 24(1):82**
出典 PDF: https://www.uv.mx/personal/ermeneses/files/2018/02/Checklists-Inspeccion.pdf

24の出典から **117のチェックリストを実際に集めて分析**した論文。結論部：

> **None of the checklists should be used "as is."** Project staff should invest the effort necessary to analyze the types of errors being made and develop tailored checklists

> Many of the checklists are too lengthy to be used by a reviewer as part of an inspection process. **Half of the surveyed checklists included twenty or more checklist items.** Checklists should generally be limited to a page in length.

そして、最も鋭い観察：

> Only two of the checklists in this survey actually suggest that a check-mark be placed next to the checklist item. For the most part, **there is little verification that a reviewer actually performed any analysis relating to a checklist item.**

**117中115は、そもそも「見た」ことを確認する仕組みを持っていない。** 形骸化を検出できない設計になっている、ということです。

**避けるべき項目の4類型**（§3 "Checklist items to avoid"）:

1. **自動化できるもの** ── "Are nested IFs indented properly?" は pretty printer の仕事。"Are functions called with the correct number and type of parameters?" は lint の仕事
2. **時代遅れになったもの** ── "Is logic coded in the fewest and most efficient statements?" は「This approach led, in part, to the Year 2000 problem」
3. **entry/exit criterion に回すべきもの** ── 「It may be more effective to have a single person verify certain properties or actions rather than having an entire inspection team perform this check.」例: "Is the compilation listing free of fault messages?" は著者が確認し moderator が検証すべきで、チーム全員にやらせるものではない
4. **一般的すぎるもの** ── "Are software requirements clear and ambiguous?" / "The code is maintainable." / "Are the goals of the system defined?" は「too general for individual reviewers to use as a checklist item」

なお、よく言われる「項目は疑問形にせよ」という heuristic について、著者は **"This heuristic is rather dubious"** と一蹴しています（疑問形にしても中身は変わらない、という趣旨）。

### 5-3. Fagan 本人が、後年チェックリストを捨てた

**Fagan, M.E. (2002)「A History of Software Inspections」in *Software Pioneers*, Springer, pp.215-226**
出典 PDF: https://eden.dei.uc.pt/~mvieira/Fagan02.pdf

Fagan 自身の回顧から3点、いずれも重要です。

**(a) チェックリストを廃止した**

> The early inspection process included checklists of conditions to look for during preparation and the inspection meeting. Many of these checklists included items that could be found using tools and did not require the human brain. As the inspection process evolved, **we eliminated checklists and learned to concentrate human intelligence on finding those defects that testing with computers could only detect with a lot of effort, and to let computers find mechanical type defects.**

**「機械で決まることは機械に任せ、人間は機械が苦手なものだけを見る」** ── Brykczynski の「避けるべき類型1」と完全に一致しており、独立に同じ結論に到達しています。

**(b) 目的を1つ以上入れると効果が有意に落ちる**

> The objective of inspection is to find defects only, not to undertake the activities of reviews/walkthroughs. The reason for maintaining this exclusive objective for inspections is that **experimentation has shown that when review/walkthrough activities are included in the inspection or, indeed, even one more objective is included, there is significant degradation in the defect detection effectiveness of inspections.**

**「ひとつ目的を足しただけで有意に落ちる」**と明言しています。「直さない役」「1 PR = 1つの目的」という分離は、この主張と同じものです。

**(c) 欠陥の定義は exit criteria への参照である**

> A defect is defined as an instance in which the work product **fails to satisfy the exit criteria of the operation in which it was created**, including operational defects that could be reported by customers.

そして、inspection を導入する際に**最初にやったこと**：

> One of the first steps taken was the creation of **measurable exit criteria for all the operations in the development process.** Explicit, measurable, succinct exit criteria ... were the first building blocks needed to support the inspection process.

**チェックリストより先に、測定可能な exit criteria を作った。** 「欠陥」を「exit criteria への違反」と定義することで、検証役が主観に落ちるのを防いでいます。

**(d) 名前が形骸化することへの嘆き**

> Unfortunately, the terms inspection, and even Fagan Inspection, have become almost generalized to refer to things that do not produce the consistent and repeatable results that I consider necessary ... many organizations have had comparatively modest to poor results without understanding that their implementation of the process was incomplete.

### 5-4. 航空のチェックリスト設計原則 ── 最も体系的な一次資料

**Degani, A. & Wiener, E. L. (1990)「Human Factors of Flight-Deck Checklists: The Normal Checklist」NASA Contractor Report 177549**
出典 PDF: https://ntrs.nasa.gov/api/citations/19910017830/downloads/19910017830.pdf

Appendix A に**16のガイドライン**があります（本文から抜粋、番号は原文のまま）。ソフトウェアのレビューに転用しうるものを選びます：

> **(4) Checklist responses should portray the desired status or the value of the item being considered (not just "checked" or "set").**

「確認した」ではなく**望ましい状態または値を口に出させる**。Parnas の「能動的な問い方」と同じ構造です。

> **(6) The completion call of a task-checklist should be written as the last item on the checklist**, allowing all crew members to move mentally from the checklist to other activities with the assurance of all pilots that the task-checklist has been completed.

**完了宣言そのものをチェックリストの最終項目として書く。**

> **(7) A long checklist should be subdivided to smaller task-checklists or chunks** that can be associated with systems and functions

> **(8) Sequencing of checklist items should follow the "geographical" organization of the items in the cockpit, and be performed in a logical flow.**

> **(10) The most critical items on the task-checklist should be listed as close as possible to the beginning of the task-checklist, in order to increase the likelihood of completing the task before interruptions may occur.** We note that this guideline could be in conflict with Nos. (8) and (9) above. In most cases where this occurs, **this guideline (10) should take precedence.**

**重要項目は先頭に置く。地理的順序と衝突したら、重要度が勝つ。** 衝突する規則を並べて、優先順位まで書いているのが特徴です。

> **(11) Critical checklist items ... that might be reset prior to takeoff due to new information should be duplicated between task-checklists.**

**重要項目は意図的に重複させる。** §2 で見た「重複は無駄」という効率の議論と、真っ向から対立する原則です。安全側は重複を選んでいる。

> **(12) Checklists should be designed in such a way that they will not be tightly coupled with other tasks. Every effort should be made to provide buffers for recovery from failure, and a way to "take up the slack" if checklist completion does not keep pace with the external operation.**

**(1) では、チェックリストを規律問題の解決の場にしてはならない**とも明記されています（"Every effort should be made to avoid using the checklist as a 'site' for resolving discipline problems"）。

### 5-5. 形骸化の機序 ── 同報告書の本文

**期待とパターン照合が両刃の剣であること**：

> Summarizing, the combined effect of expectations, experience, and the pattern-analyzing mechanism is a double edged sword. On one side, this ability makes the user flexible and faster in responding to multiple conditions. On the other side, **it can lead the operator to make a disastrous mistake just because part of the information which was collected quickly or without sufficient attention appeared to match the ex[pectation]**

**長さが逸脱を生むこと**（実例つき）：

> Pilots who fly short flight segments perform the flight checklists as much as 3-10 times per day and as many as 10-30 times on a typical trip. Therefore, **a requirement to conduct a long and meticulous checklist for each flight may lead some to deviate from the prescribed procedures, performing only what he/she perceives as the critical items ("killer items" as some call them).** ... For example, one company's DC-9-50 checklist contained **81 check items** for the ENGINE START, TAXI and TAKEOFF task-checklists. Not surprisingly, pilots from this [company deviated]

**81項目にした結果、パイロットは自分が重要だと思う項目だけを実施するようになった。** 「頻度 × 長さ」が形骸化の条件である、という具体的な記述です。Mdoro のように毎回同じ検査を通す運用では、これは直接効きます。

**「順序が崩れると見逃しが通る」**（do-list 方式について）：

> due to the elimination of the configuration redundancy, **a mistake can easily pass unnoticed once the sequence is interrupted.**

### 5-6. Gawande の checklist 設計則（二次資料のみ）

- 項目数は **5〜9**（作業記憶の限界）
- ひとつの pause point で **60〜90秒**を超えると、チェックリスト自体が注意の妨害物になる
- **DO-CONFIRM**（記憶でやってから確認する）と **READ-DO**（読みながらやる）を区別する
- **killer items**（飛ばすと最も危険で、かつ実際に飛ばされがちな項目）に絞る
- 1ページに収める

出典（いずれも二次要約。原典 *The Checklist Manifesto* (2009) 本文は未確認）:
https://sive.rs/book/ChecklistManifesto / https://grahammann.net/book-notes/the-checklist-manifesto

---

## 6. Mdoro の特徴に直接当たる視点の対応

「これを採用せよ」ではなく、**どの特徴にどの既成語彙が当たるか**の対応表です。選別は依頼者にお任せします。

### 6-1. 特徴 → 視点の対応

| Mdoro の特徴 | 当たる視点・語彙 | 出典 |
| :--- | :--- | :--- |
| **状態遷移の冪等性** | HAZOP `As well as`（余分に起きる）／SHARD `Commission`／ODC Qualifier `Extraneous`／STPA UCA-2「提供されてはならないときに提供される」 | Primatech / Pumfrey 1999 / ODC v5.2 / STPA Handbook |
| **終了状態からの脱出先** | Binder の **sneak path testing**（仕様にない遷移を実際に起こそうとする）／Chow W-method（実装が余分な状態を持つ可能性）／NASA MSFC「Software shall initialize, start, and restart ... to a safe state」「Software termination shall result in a safe system state」 | Binder 2000（二次）/ Chow 1978（書誌のみ）/ NASA-GB-8719.13 H.3 |
| **周回数の基準** | ODC Defect Type `Assignment/Initialization`（"The instance variables that capture the state of an object are not correctly initialized"）／HAZOP `More`/`Less`（量的増減）／ODC `Checking` | ODC v5.2 §4.2.1.1, §4.2.1.2 |
| **状態遷移表への副作用の混入** | ODC トリガー **`Side Effects`**（"foresee some behavior ... **outside of the scope of the component** with which the code under review is associated"）── ほぼそのままの定義 | ODC v5.2 §3.2.1.9 |
| **ログに書くタスク名の取得元** | HAZOP `Other than`（完全な置換＝出所が違う）／SHARD `Value: Subtle`（値域としては正当だが誤った値）／ODC `Relationship`（"The structure of code/data in one place assumes a certain structure of code/data in another"） | PQRI / Pumfrey 1999（二次）/ ODC v5.2 §4.2.1.7 |
| **設定変更が実行中セッションの終了時刻を動かさない** | NASA MSFC 汎用安全要求：「**If an automated sequence is already running when a software inhibit ... is activated, the sequence shall complete before the software inhibit is executed**」「**The state of software inhibits shall remain unchanged after the execution of an override**」 | NASA-GB-8719.13 Appendix H.3 |
| **Mac が正本 / iPhone は終了を確定してはならない** | **MNWF（Must Not Work Function）**。かつ「MWF/MNWF は状態依存で入れ替わる。**いつその指定が有効かも書け**」 | NASA-GB-8719.13 Appendix F.2 |
| **Task.md へ書き込まない／MdoroLog.md は挿入のみ** | Parnas & Weiss の **「誤用の仮定リスト」**（"a list of assumptions that describe **incorrect usage** of the module, i.e., usage that the designers assume should not occur"）＋ MNWF ＋ HAZOP `Other than`（書き先が違う）/ `Reverse`（追記のはずが上書き） | Parnas & Weiss 1985 / NASA-GB-8719.13 |
| **時刻は絶対時刻基準・残り秒数を同期しない** | HAZOP 時間 guide word **`Early` / `Late` / `Before` / `After`**（IEC 61882）／SHARD `Early`/`Late`／STPA UCA-3「誤ったタイミング・誤った順序」／MIL-STD-1629A「**failure to cease operation at a prescribed time**」 | PQRI（IEC 61882 引用）/ Pumfrey 1999 / STPA Handbook / MIL-STD-1629A（スニペット） |
| **単調時計と壁時計の使い分け** | STPA UCA-4「**早く止めすぎる／長く続けすぎる**」── 持続時間を独立軸として持つのは STPA だけ | STPA Handbook |
| **プロトコル版番号・非互換なら接続拒否** | ODC トリガー **`Backward Compatibility`**（"incompatibility ... with **earlier versions of the same product**"）と **`Lateral Compatibility`**（"incompatibility ... with the **other systems ... with which it must interface**"）── 2つ別々の視点として立っている | ODC v5.2 §3.2.1.3, §3.2.1.5 |
| **接続拒否という振る舞いそのもの** | NASA MSFC：「**In the event that prerequisite conditions have not been met, the software shall reject the command and alert** the crew, ground operators, or the controlling executive」── 拒否だけでなく**通知**までを一対で要求 | NASA-GB-8719.13 Appendix H.3 |
| **Mac / iPhone の2ノード** | ODC トリガー `Concurrency`／ODC Defect Type `Timing/Serialization`／SHARD は**フロー1本ごと**に guide word を当てる（WebSocket の各メッセージ種別が1本） | ODC v5.2 / Pumfrey 1999 |
| **共有ロジックを1パッケージに（二重実装しない）** | ODC `Relationship`（片方の構造がもう片方の構造を仮定する）／Parnas の information hiding と「仮定リスト」 | ODC v5.2 / Parnas & Weiss 1985 |
| **仕様書が唯一の正・要件IDを引く** | ODC トリガー `Design Conformance`（"comparing the ... code segment being inspected with **its specification in the preceding stage(s)**"）／Fagan の「defect = exit criteria への違反」 | ODC v5.2 §3.2.1.1 / Fagan 2002 |
| **コメントに根拠の要件IDを書く** | ODC トリガー `Internal Document`（"incorrect information, inconsistency, or incompleteness within internal documentation. **Prologues and code comments** represent some examples"）── 独立したトリガーとして存在する | ODC v5.2 §3.2.1.4 |
| **実装者に検証させない** | Parnas & Weiss（reviewer の characteristics を先に書き出す）／Porter 1995（視点分割 35%改善）／Fagan 2002（目的をひとつ足すだけで有意に劣化） | 各一次資料 |
| **check-docs.py と読解の分離** | Fagan 2002（**"we eliminated checklists ... and let computers find mechanical type defects"**）／Brykczynski「避けるべき類型1: 自動化できるもの」 | Fagan 2002 / Brykczynski 1999 |
| **「実装で壊しやすい6箇所」という一覧の存在** | ODC の思想そのもの（欠陥の意味情報からプロセスの signature を抽出する）／Brykczynski「**analyze the types of errors being made and develop tailored checklists**」 | Chillarege 1992 / Brykczynski 1999 |

### 6-2. この分野の知見が、Mdoro の現行運用に対して**逆向き**に働く点

依頼の趣旨に照らして、都合の悪い方向の対応も挙げておきます。

1. **「視点を増やす／人を増やす」は支持されない。** Porter 1997 の「2人と4人で差がない」は、この分野で最も再現性の高い否定結果のひとつです。役を増やす提案があった場合、この結果が反証材料になります。

2. **視点分割の効果は「現実の文書」で消えやすい。** Basili らの実験で効果が出なかったのは一貫して NASA ドメイン（実務文書）側でした。汎用の練習文書でのみ有意でした。

3. **「重複は無駄」は安全工学では採られていない。** Degani ガイドライン(11) は重要項目の**意図的な重複**を要求します。効率側（Porter）と安全側（Degani）で結論が逆です。どちらを採るかは、対象が「壊れたら何が失われるか」で決めるべき問題として、この分野では扱われています。

4. **チェックリストは ad hoc と有意差がなかった**（Porter 1995 結論3）。「軸を1本渡す」ことと「チェックリストを渡す」ことは、実証上まったく別物として扱う必要があります。効いたのは前者だけです。

5. **視点を絞ると「問いを立て忘れた場所」が誰の担当でもなくなる。** Parnas & Weiss はこれを自覚していて、**軸なしの全体レビューを別立てで数人に頼む**という緩和策を明記しています。監査役に軸を1本ずつ渡す運用は、この穴を持っています。

---

## 7. 一次資料から直接引ける「そのまま使える語彙セット」

選別用に、視点の候補となる語彙を、出典つきで一覧にしておきます。

**HAZOP 基本（7語）**: No or not / More / Less / As well as / Part of / Reverse / Other than
**HAZOP 時間・順序（4語）**: Early / Late / Before / After
**SHARD（5語）**: Omission / Commission / Early / Late / Value
**STPA UCA（4類型）**: 提供されない / 提供されてはならないときに提供される / 誤ったタイミング・順序 / 早く止めすぎる・長く続けすぎる
**ODC レビュー用トリガー（9語）**: Design Conformance / Logic/Flow / Backward Compatibility / Lateral Compatibility / Concurrency / Internal Document / Language Dependency / Side Effects / Rare Situation
**ODC Defect Type（7語）**: Assignment/Initialization / Checking / Algorithm/Method / Function/Class/Object / Timing/Serialization / Interface/O-O Messages / Relationship
**ODC Qualifier（3語、上記に直交）**: Missing / Incorrect / Extraneous
**NASA ソフトウェア hazard cause（6分類）**: 問題を検出しない / 機能を実行しない / 誤った時刻・順序・状態で実行する / 誤った機能を実行する / 機能を不完全に実行する / 情報・メッセージを引き渡さない
**MIL-STD-1629A generic failure modes（5、スニペット経由）**: Premature operation / Failure to operate at a prescribed time / Intermittent operation / Failure to cease operation at a prescribed time / Degraded output

これらは**互いに独立に作られたが、大きく重なっています**。Omission/Commission（SHARD）＝ Missing/Incorrect（ODC）＝ UCA-1/UCA-2（STPA）＝ No/As well as（HAZOP）はほぼ同じ切り口です。独立に4回発見されたということは、この軸は強い、とも読めます。

逆に、**それぞれにしかない軸**：
- **STPA だけが持つ**: 持続時間（早く止めすぎる／長く続けすぎる）
- **ODC だけが持つ**: 版の互換性（Backward / Lateral）、内部文書（コメント）、Side Effects（担当範囲の外側への影響）、Rare Situation
- **HAZOP だけが持つ**: Before / After（絶対的な早遅ではなく、他と比べた順序）
- **MIL-STD-1629A だけが持つ**: Intermittent（断続）

---

## 8. 到達できなかったもの

正直に列挙します。

| 資料 | 状態 |
| :--- | :--- |
| **Fagan, M.E. (1976) 原論文**（IBM Systems Journal 15(3):182-211） | **本文未到達。** DOI ページ https://dl.acm.org/doi/10.1147/sj.153.0182 は有料。大学サイト4箇所を試行し全て 403/404。「検査 38 defects/KLOC vs 単体テスト 8/KLOC、検査が全体の82%を発見」という数値は**検索結果の要約のみ**で、原典で確認していません。代わりに Fagan 本人の2002年の回顧（*Software Pioneers* 収録）を全文取得し、そこからの引用に限定しました |
| **IEC 61882:2016 本文** | **未到達。** 有料規格。iteh.ai / ANSI / SIS のプレビュー PDF 3点を取得したがいずれも画像のみでテキスト抽出不可。guide word の一覧は、IEC 61882 を明示的に引用する二次資料（PQRI 訓練資料、Primatech）から取りました |
| **Pumfrey (1999) 学位論文本文** | **未到達。** PDF は取得できたが（16.9MB）**スキャン画像でテキストなし**。SHARD の guide word 5語は、Pumfrey 1999 を明記して引用している査読論文（Frontiers in Robotics and AI, 2021）から確認 |
| **SHARD の Value を Coarse / Subtle に細分する記述** | **一次未確認。** 複数の二次資料に現れるが、原典で裏が取れていません |
| **Regnell, Runeson, Thelin (2000)「Are the Perspectives Really Different?」本文** | **未到達。** Springer 有料。「複製実験では3視点中2つがほぼ同じ欠陥集合を見つけ、その文書こそ PBR がチェックリストに勝てなかった唯一のケース」という要旨は検索結果経由のみ |
| **Ciolkowski (2009) PBR メタ分析** | **未到達。** ACM DL が 403。「要求文書では PBR と ad hoc に有意差なし」という要約が検索結果に出たが、原典未確認 |
| **Votta (1993)「Does every inspection need a meeting?」本文** | **未到達。** ただし Porter 1995 が本文中で meeting gain rate 3.9±0.7% として引用しており、そちらは一次で確認済み |
| **Chow (1978) W-method 本文** | **未到達。** ETH のコピーを取得したがスキャン画像。書誌情報のみ |
| **Binder (2000)「Testing Object-Oriented Systems」** | **未到達。** 書籍。sneak path testing の説明は二次資料のみ |
| **BS 7925-2 / ISO/IEC/IEEE 29119-4 本文** | **未到達。** testingstandards.co.uk は DNS 解決不能（サイト消滅と思われる）。ISO/IEEE は有料 |
| **MIL-STD-1629A 本文** | **部分的に未到達。** elsmar.com / NASA KSC のリンクはいずれも実体なし or 503。generic failure mode の一覧は検索スニペットが標準本文を引用したもの。everyspec.com のインデックスページは生存: https://everyspec.com/MIL-STD/MIL-STD-1600-1699/MIL_STD_1629A_1556/ |
| **Reese & Leveson「Software Deviation Analysis」(ICSE 1997)** | **未到達。** http://sunnyday.mit.edu/papers/sda.pdf および ACM DL 版ともにテキスト抽出不可。概要（deviation = 実際の値と期待値の差、guide word から出力の逸脱に至るシナリオを自動探索）は検索結果のみ |
| **Gawande『The Checklist Manifesto』本文** | **未確認。** 5〜9項目、60〜90秒、DO-CONFIRM / READ-DO、killer items はすべて二次要約から |
| **Gilb & Graham (1993)『Software Inspection』本文** | **未確認。**「最適チェック速度は300 non-commentary words の論理1ページ／時間 ± 0.9ページ」は二次資料から |
| **Martin & Tsai (1990) N-fold inspection の重複実測値** | **未到達。** CACM 33:225-232。「N個の独立チームで複製する」という方式の存在は確認できたが、**チーム間の重複率の実数**は取れていません。§2 の「重複と漏れのトレードオフ」にとって最も欲しかったデータです |
| **二人ルール（Two-person rule）の一次資料** | **未確認。** AFI 91-104 等の原典に当たっていません |
| **Urbach 2014 の「なぜ効かなかったか」の分析** | **未確認。** 実施率の過大報告・形式的遵守という説明は二次資料の記述 |

---

## 9. 出典一覧（本文で実際に読んで引用したもの）

**視点分割・インスペクション**
- Basili, Green, Laitenberger, Lanubile, Shull, Sørumgård, Zelkowitz (1996)「The Empirical Investigation of Perspective-Based Reading」*Empirical Software Engineering* 1(2):133-164 — https://www.cs.umd.edu/~mvz/handouts/emp_pbr.pdf
- Porter, Votta, Basili (1995)「Comparing Detection Methods for Software Requirements Inspections: A Replicated Experiment」*IEEE TSE* 21(6):563-575 — https://drum.lib.umd.edu/bitstreams/332d6328-bdce-4726-9102-e00bac748f9a/download
- Porter, Siy, Mockus, Votta (1997)「An Experiment to Assess the Cost-Benefits of Code Inspections in Large Scale Software Development」*IEEE TSE* 23(6):329-346 — https://users.ece.utexas.edu/~perry/education/SE-Intro/porter-tse23.pdf
- Parnas & Weiss (1985)「Active Design Reviews: Principles and Practices」ICSE-8 / *JSS* 7(4):259-265 — http://figforth.org.uk/library/p132-parnas.pdf （DTIC 版: https://apps.dtic.mil/sti/html/tr/ADA163188/index.html）
- Fagan (2002)「A History of Software Inspections」in *Software Pioneers*, Springer, pp.215-226 — https://eden.dei.uc.pt/~mvieira/Fagan02.pdf
- Thelin, Runeson, Wohlin (2003)「An Experimental Comparison of Usage-Based and Checklist-Based Reading」*IEEE TSE* 29(8) — https://www.wohlin.eu/tse03.pdf
- Petersson, Thelin, Runeson, Wohlin (2004)「Capture-recapture in Software Inspections after 10 Years Research」*JSS* — https://wohlin.eu/jss04-1.pdf
- PBR ラボパッケージ（UMD） — http://www.cs.umd.edu/projects/SoftEng/ESEG/manual/pbr_package/manual.html

**欠陥分類**
- IBM「Orthogonal Defect Classification v5.2 for Software Design and Code」(2013) — https://s3.us.cloud-object-storage.appdomain.cloud/res-files/70-ODC-5-2.pdf
- Chillarege ら (1992)「Orthogonal Defect Classification — A Concept for In-Process Measurements」*IEEE TSE* 18(11) — https://ieeexplore.ieee.org/document/177364/ （書誌のみ）

**HAZOP / SHARD / STPA / FMEA**
- Primatech「Understanding HAZOP Deviations」— https://www.primatech.com/technical/pt-notes/170-understanding-hazop-deviations
- PQRI「Hazard & Operability Analysis (HAZOP) Training Guide」（IEC 61882 を引用）— https://pqri.org/wp-content/uploads/2015/08/pdf/HAZOP_Training_Guide.pdf
- IEC 61882:2016 — https://webstore.iec.ch/en/publication/24321 （未到達）
- Pumfrey (1999) 学位論文 — https://etheses.whiterose.ac.uk/9797/ （本文抽出不可）／SHARD guide word の確認は https://www.frontiersin.org/journals/robotics-and-ai/articles/10.3389/frobt.2021.667316/full
- Leveson & Thomas (2018)「STPA Handbook」— https://www.flighttestsafety.org/images/STPA_Handbook.pdf
- MIL-STD-1629A (1980) — https://everyspec.com/MIL-STD/MIL-STD-1600-1699/MIL_STD_1629A_1556/

**安全要求 / must-not-work**
- NASA-GB-8719.13「NASA Software Safety Guidebook」(2004) — https://standards.nasa.gov/sites/default/files/standards/NASA/Baseline/0/nasa-gb-871913.pdf （Appendix F.2 = MWF/MNWF、Appendix H.3 = MSFC 汎用安全要求）

**チェックリスト工学**
- Degani & Wiener (1990)「Human Factors of Flight-Deck Checklists: The Normal Checklist」NASA CR-177549 — https://ntrs.nasa.gov/api/citations/19910017830/downloads/19910017830.pdf （Appendix A = 16 のガイドライン）
- Brykczynski (1999)「A Survey of Software Inspection Checklists」*ACM SIGSOFT SEN* 24(1):82 — https://www.uv.mx/personal/ermeneses/files/2018/02/Checklists-Inspeccion.pdf
- Haynes ら (2009)「A Surgical Safety Checklist to Reduce Morbidity and Mortality in a Global Population」*NEJM* 360:491-499 — https://www.nejm.org/doi/abs/10.1056/NEJMsa0810119
- Urbach ら (2014)「Introduction of Surgical Safety Checklists in Ontario, Canada」*NEJM* — https://www.nejm.org/doi/full/10.1056/NEJMsa1308261

**テスト設計**
- Chow (1978)「Testing Software Design Modeled by Finite-State Machines」*IEEE TSE* SE-4(3):178-187 — https://dl.acm.org/doi/abs/10.1109/Tse.1978.231496 （書誌のみ）
- Elmendorf (1973)「Cause-Effect Graphs in Functional Testing」IBM TR-00.2487 — 書誌のみ（二次資料経由）
- ISO/IEC/IEEE 29119-4:2021 — https://www.iso.org/standard/79430.html （有料・未到達）

---

## 10. 最後に

依頼の趣旨どおり、**採用されていない前提**で書きました。選別のための材料として、特に注意を向けていただきたい3点だけ挙げます。

1. **この分野の最も強い肯定結果（Porter 1995 の35%改善）と最も強い否定結果（Porter 1997 の2人=4人）は、同じ研究グループが出しています。** 「視点を分けるのは効く／人を増やすのは効かない」は、矛盾ではなく同時に主張されている、というのが正確な読み方です。

2. **Fagan 本人が、後年チェックリストを捨て、目的をひとつに絞ることを最重要としている**（「ひとつ目的を足しただけで有意に劣化する」）。この2点は、Mdoro の現行運用がすでに独立に到達している場所とかなり重なります。

3. **「破ると外部の資産が壊れる要件」については、この分野は MNWF という専用の概念を持っており、しかも「MNWF は仕様書から抜け落ちるのが常だ」「状態依存で MWF と入れ替わるので、いつ有効かも書け」という警告まで一次資料に明記されています。** 「動かしてはいけない3原則」という別立ての条文は、この分野の語彙では MNWF リストにあたります。