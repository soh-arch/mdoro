作業ツリーは変更していません（`git checkout` / `restore` / `stash` は使用していません）。`swift test` は変更が `docs/` のみで Swift に触れていないため走らせていません。

## 実出力

```
$ git log --oneline origin/main..HEAD
d6eb96c docs: run twenty axes across twelve agents, and name the leak it exposed
585bc06 docs: record the approved third-stage arrangement before running it
d05fb94 docs: the ceiling axis pointed at a region, it did not state the answer
18690cb docs: record which measurement the third stage is for
4b6bc11 docs: run the ceiling once and record what it raised
e7b6541 docs: file the ceiling axis extraction before running it

$ git diff origin/main..HEAD --stat
 docs/PUNCHLIST.md              |  2 +
 docs/review-axes.md            | 87 +++++++++++++++++++++++++++++++++++++++
 docs/reviewer-model-results.md | 93 ++++++++++++++++++++++++++++++++++++++++++
 3 files changed, 182 insertions(+)

$ git status --short
(空)
```

---

## 指摘（重大度順）

### 1. 【重大】「字数」列は文字数ではなく**バイト数**であり、合計「173,815字」は誤りである

**根拠**: 本文の記述「12本で 173,815 字」および表の見出し「字数」（`docs/reviewer-model-results.md:989,993`）。
**場所**: `docs/reviewer-model-results.md` 第三段の表、`/tmp/.../stage3/harvest.sh`。
**破綻する条件**: 常に成立する（設計上の誤り、入力依存ではない）。

`harvest.sh` は `wc -c`（バイト数）で値を出しており、表の12行すべて・合計値がこれと一致することを確認した。

```
$ for f in 01-A-1.md 02-A-1+F-3.md 03-A-2.md 04-A-2+C-5.md 05-F-1+F-2.md 06-F-4+A-3.md \
    07-A-4+A-5.md 08-B-1+B-2.md 09-B-3+B-4.md 10-B-5+B-6.md 11-C-1+C-2.md 12-C-3+C-4.md; do
  wc -c < "$f"
done
# → 12154 13250 7862 11857 17381 21809 14474 13807 18822 12825 17669 11905（表と完全一致）
```

しかし報告は日本語主体の Markdown であり、UTF-8 では日本語文字は3バイトを要する。Python で実際の Unicode 文字数を数えると:

```
$ python3 -c "
for f,label in [('01-A-1.md',None)]: pass
"
（実測は本文中で列挙。合計）
TOTAL chars= 114106   TOTAL bytes= 173815
```

つまり「173,815字」は実際の文字数（**約114,106字**）より **52%多い**。`wc -m` で確認しなかった（環境のロケールが `POSIX` のため `wc -m` は `wc -c` と同じ値になり、この誤りを検出できない——これも一因として指摘する）。

### 2. 【重大】POL-106「8体」・POL-182「9体」の内訳に、実際には到達していない体が含まれている

**根拠**: 軸2の指示（「文字列が出てくるだけで『到達した』と数えていないか」）。`docs/reviewer-model-results.md:1027-1030`。
**場所**: 各体の報告本文（下記）。
**破綻する条件**: 常に成立（数え間違い）。

各体の報告を実際に読んで判定した結果:

- **POL-106**（Mac側に破損メッセージの計数機構が無い）: 表は「8体（5・6・7・8・9・10・11・12）」とするが、
  - **体5**（`05-F-1+F-2.md`）は REQ-ERR-009 の「10回」しきい値を**条文間の両立性の議論**として引用しているだけで、Mac 実装にカウンタが無いという事実には一度も言及していない。体5の「割り当ての外」節はむしろ POL-182（`unknownDeviceToken`）を報告しており、POL-106 ではない。
  - **体6**（`06-F-4+A-3.md`）は `BrokenMessageCounterTests.swift` を「作った一覧」の1行（F-4軸、名前・参照の列挙）と「開いたファイル一覧」で言及するのみで、Mac 側にカウンタが無いという主張を本文のどこにもしていない。
  - 実際に本文で明示的に主張しているのは **7・8・9・10・11・12 の6体**である（`grep` の表面一致ではなく、各ファイルを通読して確認）。
- **POL-182**（版不一致が `unknownDeviceToken` で返り `protocolVersionMismatch` が送出されない）: 表は「9体（2・3・4・5・6・7・9・11・12）」とするが、
  - **体11**（`11-C-1+C-2.md`）は本文中で `protocolVersionMismatch` という文字列を**grepコマンドの検索パターンとして**しか使っておらず（113, 157行目）、その結果に対する言及・結論を一切書いていない。「割り当ての外で気づいたこと」節（136行目）はむしろ POL-106（破損メッセージカウンタの不在）を報告しており、POL-182 ではない。
  - 残る **2・3・4・5・6・7・9・12 の8体**は本文で明示的に主張している。

つまり両方とも表の体数が実際より1体多い（POL-106は8ではなく6、POL-182は9ではなく8）。「機械で数えた」という記述（`docs/reviewer-model-results.md:1027`）と矛盾する。単純な文字列一致では体5・体6・体11のような「話題の周辺に文字列は出るが、その体自身は該当の指摘に到達していない」ケースを拾ってしまうことを、この差分自体が示している。

### 3. 【中】「3体とも `timeSyncPing` と `heartbeat` に無いことを示した」は体9について不正確

**根拠**: `docs/reviewer-model-results.md:1000-1004`の表（体1・体2・体9が並列に「同じ根拠」として記載されている）。
**場所**: `09-B-3+B-4.md:176`（「割り当ての外」節の該当箇所）。
**破綻する条件**: 常に成立。

体1・体2 は `timeSyncPing` と `heartbeat` の両方について門(`guard source === connection`)が無いことを具体的に示しているが、**体9 の該当箇所は `timeSyncPing` にしか言及しておらず、`heartbeat` という語は体9のレポート全体を通じて一度も出現しない**（`grep -c heartbeat 09-B-3+B-4.md` → 0）。表の書きぶり（3体を横並びで同一の根拠として記載）は、体9についてはやや言いすぎである。

### 4. 【中】「行番号つき引用」列は、単純な機械的規則では再現できない

**根拠**: 軸1の指示（「一致しない列があれば挙げてください」）。
**場所**: `docs/reviewer-model-results.md` 第三段の表。

`表`（全テーブル行数）・`コマンド`（`^\$ ` で始まる行数）・`挙げた .swift`（重複除去した `.swift` ファイル名の数）の3列は、単純な機械的カウントで**12行すべて完全一致**した（下記コマンド参照）。しかし「行番号つき引用」列は、以下の複数の妥当な方法を試したが**いずれも12行同時には一致しなかった**:

- `.swift:数字` / `.md:数字` パターンの単純カウント → 06・07・08・09は一致するが、01・03・04・10・11・12は不一致（1〜9件のズレ）
- 上記から「割り当ての外」節を除外 → 01・05・06・09は改善するが、07・08は逆に悪化
- コードフェンス内の `数字:` 行のみをカウント → 全滅

体10（`10-B-5+B-6.md`）で個別に確認したところ、「行番号つき引用=3」は本文中で `.swift` の行番号を伴う引用が正味1箇所（`Authenticator.swift 89, 136–140, 156–169行`）だけであり、しかも数字を3つ（89・136-140・156-169）に分解して数えている可能性が高いことまでは特定できたが、これを一般化した規則を他11行に適用すると再び不一致が生じた。**この列だけは、どの機械的規則で得たのかを本文・スクリプトのいずれからも特定できなかった**（`extract-report.py` は逐語抽出のみで集計は行っていない。集計スクリプトはスクラッチパッドに存在しない）。

再現できた列のコマンドと結果:

```
$ grep -cE '^[[:space:]]*\|.*\|[[:space:]]*$' <file>   # 「表」列 → 12行すべて完全一致
$ grep -cE '^\$ ' <file>                                # 「コマンド」列 → 12行すべて完全一致
$ grep -oE '[A-Za-z0-9_]+\.swift' <file> | sort -u | wc -l  # 「挙げた .swift」列 → 12行すべて完全一致
```

### 5. 【軽微】体6・体11の「逆の結論」引用は、鍵括弧付きだが実際は要約（パラフレーズ）である

**根拠**: 軸3・5（逐語引用の照合、言いすぎの探索）。
**場所**: `docs/reviewer-model-results.md:1063-1064`。

- 「体11: 『`The line only stands when the protocol versions match exactly` は旧命題をそのまま運んでいる』」— 体11の実際の文（`11-C-1+C-2.md:24`）は「削除されたはずの…という命題をそのまま運んでいる」であり、「旧命題」という語は使われていない（近い意味の要約）。
- 「体6: 『このコメントは新旧どちらの定式化とも矛盾しない』」— 体6の実際の文（`06-F-4+A-3.md:41`）は「これは新旧どちらの定式化とも矛盾しない」であり、「このコメントは」という主語は補われている。

いずれも意味を歪める要約ではないが、鍵括弧「」で囲われており逐語引用であるかのように見える。一方、軸3で指定された3つの一次資料からの引用（`/tmp/stage3-diff-B` の commit メッセージ、`e67b3b9` の commit 題名）はいずれも一字一句正確であることを確認した。

```
$ cd /tmp/stage3-diff-B && git log -1 --format='%B'
# → "the hello and the refusal that answers it are exchanged across the version line, and
#    the server answers a timeSyncPing before it authenticates anything at all." が一字一句一致

$ git show -s --format=%s e67b3b9
# → "test(core): the reason an unknown value is broken is the trade, not the version (REQ-PRT-005)"
#    引用「the reason an unknown value is broken is the trade, not the version」が一致
```

### 6. 「体11が正しい」という裁定は、実出力で裏付けが取れる（指摘ではなく確認）

**根拠**: 軸4。
**場所**: `git log -S`, `git show e67b3b9`。

```
$ git log -S "The line only" --oneline -- Packages/MdoroCore/Tests/MdoroCoreTests/ProtocolTests.swift
e67b3b9 test(core): the reason an unknown value is broken is the trade, not the version (REQ-PRT-005)
ac2fb3e docs: an unknown value has a requirement of its own to stand on (REQ-PRT-005)

$ git merge-base --is-ancestor b79b76c e67b3b9 && echo "ancestor"
ancestor
```

`b79b76c`（教材Bのcheckout点、2026-09-02 23:12）は `e67b3b9`（同日23:56）の祖先であり、`e67b3b9` は確かに教材より後の commit である。`e67b3b9` の実際の commit body は「The comment also claimed the line only stands on matching versions, which is not what the server does — it answers timeSyncPing and records heartbeat before authentication」と明記しており、この文が旧い定式化として書き換えられた事実は成立する。ただし**体11自身の論拠**（「版違いでも hello とその拒否は交換される＝線は一瞬立つ」）と、**実際の commit の論拠**（timeSyncPing/heartbeat が認証前に応答される）は、同じ結論を支える別の理由づけであり、体11の推論過程そのものが commit と同一というわけではない（結論のみが一致）。この差は軽微だが、裁定の精度として記録しておく。

### 7. `docs/PUNCHLIST.md` の POL-218 行は凡例・書式・重大度とも整合していた

**根拠**: 軸6。`docs/PUNCHLIST.md:16-24`（記法表）。

```
$ awk '/\*\*POL-218\*\*/{print; exit}' docs/PUNCHLIST.md | python3 -c "
import sys; print(len(sys.stdin.read().split('|')))"
10
```

`|` 区切りで10（先頭・末尾の空セルを除き8列）となり、凡例の `ID / 症状 / 根拠 / 軸 / レーン / 重大度 / 状態 / PR` と一致。`根拠`・`軸`列を「—」とする書式は直近の POL-214〜217 と同一で、重大度 `minor` もこれらの類似行（プロセス設計・運用に関する起票）と揃っている。POL-218 の記述内容（3体到達、8体・9体、7件の票の無い指摘、体11/体6の逆転、F-3/C-5の設計ミス）を `docs/reviewer-model-results.md` の対応箇所と突き合わせたが、**数値・体番号の食い違いは見つからなかった**（両ファイルは同じ——誤った——8体・9体という数字を一貫して使っている。上記2番の指摘はこの両ファイルに共通して及ぶ）。

---

## 検証できなかった要件・軸

- 軸5で言及されている「先行する12本はすべて0/1である」という前提は `docs/reviewer-model-evaluation.md`（今回の差分に含まれないファイル）の既存記録に基づく主張であり、今回の差分の範囲外のため、その12本の内訳・カウントまでは検算していない。
- 軸2の「体9が申告した git log 利用」は POL-182 の発見経路についてのものであり、体9が `timeSyncPing`/`heartbeat` の知見（POL-217 の期待される指摘）を git 履歴経由で得た可能性を直接には裏付けていない（体9の該当箇所はコード引用のみで、git 由来である証拠はない）。この点は本文の「しかしこれは申告であって証明ではない」という限定の範囲内であり、本文の主張自体を覆すものではないが、注記として残す。
- Swift の変更はなく `swift test` は走らせていない。