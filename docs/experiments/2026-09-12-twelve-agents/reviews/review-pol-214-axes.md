Working tree is clean; I made no `git checkout`/`restore`/`stash` operations, so there is nothing to report on that front.

Below is the review. Swift was not run: **the diff touches only `docs/` (confirmed by `git diff --stat`), so `swift test` was not applicable and was not run.**

## 実行した検証コマンドと実出力

```
$ git fetch origin main
$ git log --oneline origin/main..HEAD
6b9e557 docs: add four review axes taken from outside the project
ead6835 docs: count the diff run against every attempt on material B
f90029d docs: the diff moves what is suspected, not what is checked
92fe232 docs: file POL-213 and POL-214 before testing where attention goes

$ git diff origin/main..HEAD --stat
 docs/ORCHESTRATION.md             |  21 ++-
 docs/PUNCHLIST.md                 |   2 +
 docs/review-axes.md               | 308 ++++++++++++++++++++++++++++++++++++++
 docs/reviewer-model-evaluation.md |  48 ++++++
 4 files changed, 377 insertions(+), 2 deletions(-)

$ git status --short
(空)
```

```
$ python3 Tools/axes-for.py origin/main
4 file(s) against origin/main

■ docs/PUNCHLIST.md
    - 重大度を台帳の似た行と比べる
    - 欄・状態語が凡例どおりか
      (docs/PUNCHLIST.md)

■ オーケストレーターが一次で書いた文章（種類を問わず）
    - 記録との突き合わせ。 要約が原典と一致するか、引用が逐語か、数えた数と書いた数が合うか
      (docs/ORCHESTRATION.md, docs/PUNCHLIST.md, docs/review-axes.md, docs/reviewer-model-evaluation.md)

── 天井 ──
立てる: 自分が一次で書いた文章（書いたなら）
「3原則に触るか」は自分で判断する。渡すのは差分だけ、聞くのは「何を確かめるべきか」だけ。
```
（この差分は Swift ファイルを含まないので、「してはならない」の行 / `TimerEngine.swift` 等は当たらない。想定どおり。）

---

## 指摘（重大度順）

### 1. major — `docs/ORCHESTRATION.md` の新規文が、`Tools/axes-for.py` で機械的に反証できる（軸3）

**根拠**: 軸3の指示（`axes-for.py` を実際に走らせて確認する）
**場所**: `docs/ORCHESTRATION.md:87`（「**先頭の行は、他の行とわざと重なる。** `TimerEngine.swift` を触れば2行が出る。」）

`Tools/axes-for.py` のロジックを直接呼び出して検証したところ、`TimerEngine.swift`（実体は `Packages/MdoroCore/Sources/MdoroCore/TimerEngine.swift`）は**3行**に当たる。

```python
rows -> ['**「してはならない」と書いてある場所** `TimerEngine.swift ...',
         '`Packages/MdoroCore/`',
         '`PomodoroMac/PomodoroMac/AppModel.swift`, `TimerEngine.swift`']
```

理由は、`TimerEngine.swift` が `Packages/MdoroCore/` 配下にあるため、既存の「`Packages/MdoroCore/`」行（末尾 `/` のプレフィックス一致）にも当たるからである。文中の「2行が出る」という記述は、`AppModel.swift` を例にとれば正しい（2行）が、直前で名指ししている `TimerEngine.swift` については誤りで、**ツール1回で反証できる**。

**破綻する条件**: 読者が「先頭の行が重なる例」として `TimerEngine.swift` を信じ、`axes-for.py` の出力を「2行のはず」と期待して読むと、実際の3行目（`Packages/MdoroCore/` 行）の意味を誤解する。実害は小さいが、根拠として名指しされた具体例が実測と食い違っている。

### 2. major — `docs/review-axes.md` §4 の表に載っていない引用が2件ある（軸1）

**根拠**: 軸1の指示
**場所**: `docs/review-axes.md:236-237, 239-241`（§5「数の問題」内の Porter, Siy, Mockus, Votta 1997 からの引用2件）

§4 の表の該当行は次の1行だけである。

```
| "no difference between two- and four-person inspections" | Porter, Siy, Mockus, Votta 1997 3.7 | 確認した |
```

しかし §5（§1〜§6の範囲内）には同じ論文からの引用がさらに2件、`> ` 形式で存在する。

```
> "There was no difference in overlap between 1sX2p and 1sX4p inspections and both distributions
> had a median of 0."

> "Our interpretation of these results is that larger teams don't improve inspection performance
> because meeting gains do not increase as the number of reviewers increases, and because larger
> teams may suppress a[wareness] …"
```

この2件は §4 の表のどの行にも対応していない。**表に載っていない逐語引用**である。

### 3. major — §4 の表が「確認した」と言っている出典の一部が、本文のどこにも現れない（軸1）

**根拠**: 軸1の指示
**場所**: `docs/review-axes.md:207`

```
| ガイドライン (4) (10) (11)、81項目の DC-9-50、"killer items" | Degani & Wiener CR-177549 | 確認した |
```

このうち「ガイドライン (4) (10) (11)」に対応する引用は本文（§2の(1)と(4)）に実在するが、**「81項目の DC-9-50」と「"killer items"」は、この表の行以外どこにも出てこない**（`grep -in "killer\|dc-9\|dc9\|81項目"` で本文中の出現は表の行そのものしかヒットしなかった）。「確認した」と主張している出典のうち、本文で語られていない部分がある。

### 4. minor（疑い）— §4 で「確認した」とされる2件が、本文では「> 」引用ではなく §6 のテーブル内引用としてしか現れない（軸1・軸2の境界）

**根拠**: 軸1の指示（「> 」引用の突き合わせ）
**場所**: `docs/review-axes.md:202`（"we also ask a few people for overall reviews …" → 実際の引用は §6 表内 `docs/review-axes.md:265`）、`docs/review-axes.md:209`（"even one more objective is included …" / "we eliminated checklists …" → 実際の引用は §6 表内 `docs/review-axes.md:263-264`）

これら2件は本文自体には存在する（消えているわけではない）が、**`> ` のブロック引用としては存在せず**、§6 のテーブルセル内の地の文として置かれている。軸1が「> 」引用の突き合わせを明示的に求めているため、この2行は「§4 が確認したとする引用が、§1〜§6の『> 』引用一覧のどれとも一致しない」形になっている。実害は小さいが、突き合わせの形式的な不整合として報告する。

### 5. major（疑い）— §2(4) の因果主張が、直後の文と食い違う（軸2）

**根拠**: 軸2の指示（因果の向きの検証）
**場所**: `docs/review-axes.md:132-133`

```
**Porter, Votta, Basili（1995）は、この差だけを操作した実験である。**
Scenario は「チェックリストの各項目を、それを実行する手続きに置き換えたもの」で、
**担当範囲はむしろ狭い。**
```

直前で引用されているのは Parnas & Weiss の「能動的な問い方 vs 受動的な問い方」の違いである。「この差**だけ**を操作した実験」という強い断定（「だけ」＝唯一の操作変数）の直後に、実際の操作は「チェックリスト項目を手続きに置き換えた」という**別の変換**だと説明しており、これは能動/受動の言い回しの差そのものとは異なる操作である。「だけ」という強い言い切りが、直後の記述自体によって崩されている疑いがある。

### 6. major（疑い）— §6 の「常に併置している」が、直前で引用した1文からは支持されない（軸2）

**根拠**: 軸2の指示（強さの語「常に」の検証）
**場所**: `docs/review-axes.md:265, 268`

引用（Parnas & Weiss、§6 表内）:
```
"Because our reviews are very tightly focused, we also ask a few people for overall reviews
to decrease the chance that we overlook problems because we neglected to pose a question."
```

直後の地の文（同ページ）:
```
**ただし天井は4つの条件に当たるときだけ立つ。Parnas は鋭い軸を使うときは常に併置している。**
```

引用は「私たちの検証は非常に絞り込まれているので、少数人には俯瞰レビューも頼む」という**1回の実践の記述**であり、「鋭い軸を使うときは**常に**併置している」という不変則の主張を単独では支持しない。「常に」という強い普遍化が、引用1文だけから導けるかは疑わしい。

### 7. minor（疑い）— §5 の「(2)だけが一次未確認の資料に乗っている」という主張が、§4 の表自身の記載と整合しない疑い

**根拠**: 軸2 / 軸1 の突き合わせ
**場所**: `docs/review-axes.md:219`

```
**採った4つのうち、(2) だけが一次未確認の資料に乗っている。**
```

しかし §4 の表では、(3) の根拠である `rust-lang/rust の 124件・96件という数` も「⚠ 数え直していない。調査役が実物を読んで数えた」と注記されている。「一次未確認」（原典に届いていない）と「数え直していない」（原典には届いたが自分で再検証していない）は異なるカテゴリだと読めなくもないが、文中でこの区別は明示されておらず、「(2)だけが」という限定が正確かどうかは読み手には判別しづらい。**再現できない疑いとして明記する。**

### 8. minor（疑い）— §5 の「(3) 条文を書き直したときの随伴物」根拠が、ODC の主張を裏取りなしで並べている

**根拠**: 軸1（本文に現れる出典が§4に無い）
**場所**: `docs/review-axes.md:118-119`

```
ODC も独立に同じ軸を持つ —— `Internal Document` が9つのトリガーの1つとして、
プロローグとコードコメントを名指しで含む。
```

この ODC についての主張は §4 の「確かめた／確かめていない」表のどの行にも対応していない（ODC は表に一切登場しない）。英文の逐語引用ではないため軸1の「> 引用」チェックの対象外ではあるが、§4 の「どこまで自分で確かめたか」という趣旨からすると、この主張の確度も本来は表に載るべき対象に見える。**表に載っていない一次資料への言及**として付記する。

### 9. 軸4（PUNCHLIST の POL-213 / POL-214）——形式面の逸脱は見つからなかった

`awk -F'|'` で列数を数えたところ、POL-213・POL-214 とも他の行と同じ8列（先頭・末尾の空セルを含め `NF=10`）で構成されており、凡例（ID / 症状 / 根拠 / 軸 / レーン / 重大度 / 状態 / PR）の順序と一致していた。重大度は両方とも `minor` で、親票（POL-197 / POL-211 / POL-212、いずれも `minor`）と揃っている。逸脱は見つからなかった。

### 10. 軸5（ORCHESTRATION.md の新記述と CLAUDE.md / review-axes.md の整合）——文書内の緊張関係（疑い）

**根拠**: 軸5の指示
**場所**: `docs/ORCHESTRATION.md:83-85` と `docs/review-axes.md:189`

`ORCHESTRATION.md` の既存規則:
```
**この表は事故のたびに1行増やす。** 減らさない。
**ただし、事故を待たない行もある** —— 上の4つの形（送らない・送ってはならないときに送る・順序・持続）は、
**まだ起きていない事故にも当たる**。**事故駆動だけで育てると、踏んでいない筋には軸が立たない。**
```

これは「行が増えるのは事故がきっかけの場合だけである」という元の文の素直な読みに、明示的な例外（事故を待たない行）を「ただし」で継ぎ足す形になっている。一方、`docs/review-axes.md` の「採らなかったもの」表（§3）では、定期削除案を却下する理由として次のように書かれている。

```
| 「減らさない」を撤回して定期的に削る（Google SRE の定期通読） | **床の行は事故の記録でもあるので、削ると記録が消える。**...
```

この却下理由は「床の行＝事故の記録」であることを根拠にしているが、今回追加した(2)由来の4つの形（`ORCHESTRATION.md` の新しい行の一部）は、そもそも「まだ起きていない事故にも当たる」ものとして導入されており、事故の記録ではない。「床の行は事故の記録でもある」という汎用の正当化が、その正当化を書いた同じ変更が追加した行そのものには当てはまらない、という緊張がある。矛盾とまで言い切れるかは解釈次第だが、**同一の変更の中で、片方は「事故記録だから消せない」、もう片方は「事故を待たずに足した」と述べており、整合性の説明が本文中で完結していない疑いがある**。

---

## 検証できなかった／範囲外にしたこと

- `swift test` は実行していない。理由: 差分が `docs/` のみで Swift ファイルへの変更が無いため（`git diff --stat` で確認済み）。
- `docs/reviewer-model-evaluation.md` の48行の追加は、指示された5本の軸のいずれにも直接含まれていないため、内容の突き合わせは行っていない（軸1〜5の対象は明示的に `review-axes.md` / `ORCHESTRATION.md` / `PUNCHLIST.md` に限定されているため）。
- STPA / HAZOP / MIL-STD-1629A / SHARD / Pumfrey / Basili 1996 / Wurzel Gonçalves 2022 の原典照合は、`docs/review-axes.md` 自身が「確認していない」と明記している範囲であり、私もこの環境から原典PDFを取得していないため独立に裏取りしていない（文書の自己申告どおりに扱った）。

## 関連ファイルパス

- `/home/user/mdoro/docs/review-axes.md`
- `/home/user/mdoro/docs/ORCHESTRATION.md`
- `/home/user/mdoro/docs/PUNCHLIST.md`
- `/home/user/mdoro/docs/reviewer-model-evaluation.md`
- `/home/user/mdoro/Tools/axes-for.py`

**提案・懸念・新たな選択肢は、採用されていない前提で書いています。指摘の採否・起票の要否はオーケストレーターの判断です。**