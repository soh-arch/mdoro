# 0043. 公開する履歴に、私用のメールアドレスを載せない

- **状態**: accepted
- **日付**: 2026-09-16（人間の裁定）
- **反映**: まだ。**手順はこのレコードの「進め方」にある**（POL-272）

## 文脈

**このリポジトリは OSS として公開する**（[0021](0021-published-as-oss-named-mdoro.md)）。
**git の履歴は、公開と同時に誰でも読める。**

2026-09-16 の監査（軸 I）が、**履歴が作者のメールアドレスを2つ公開すること**を挙げた。

- **ローカルの `git config` のもの** —— 520 commit のうち **176** の author / committer に入っている。
  **最後に増えたのは 2026-09-03 で、以後は増えていない**（オーケストレーターの commit は
  `Claude <noreply@anthropic.com>` である）
- **GitHub 上の merge 操作に紐づくもの** —— merge commit の author に入る

**利用者の裁定（2026-09-16）: 前者は公開できない。後者は構わない。**

**リポジトリはこの時点でまだ private である。**公開されたものは何も無い。

### 履歴以外には無い

- **commit メッセージの本文** —— 0件
- **追跡されているファイル** —— 0件（起票した台帳の行が1件持っていたが、言い換えた）
- **tag** —— 0本

**author / committer のメタデータだけである。**

## 判断

**`git filter-repo --mailmap` で置換し、force-push する。**

**受け入れない。** 監査役の当初の読みは「**ユーザー名は commit の author メールに既に含まれるので、
履歴を書き換えても隠れない**」だったが、**それは「ホームのパスのユーザー名」の話であって、
アドレスそのものの話ではない。**

**新しいリポジトリを作り直す道は採らない。** 履歴は完全にきれいになるが、
**PR 番号（`#37`〜）が全部失われる。****台帳はそれを大量に引いており、この開発の記録がそこに乗っている。**

**書き換えで失うのは commit の SHA だけである。**
`git filter-repo` は**旧→新の対応表**（`.git/filter-repo/commit-map`）を書き出すので、
**台帳が引く53個の SHA は機械的に書き換えられる。**手作業ではない。

### これだけでは足りない

**GitHub は PR の head commit を `refs/pull/N/head` に保持する。**
**force-push しても、PR ページには古い commit が残る。****public にした瞬間に、そこから読める。**

**GitHub Support に purge を依頼する工程が要る。** GitHub 自身が、機微情報を履歴から消したあとの
手順としてそれを案内している。**この工程を飛ばすと、書き換えた意味がほとんど無い。**

## 1回目は失敗した（2026-09-16）

**下の手順は、失敗を踏まえて書き直したものである。** 最初の版で流したところ、**2つ壊れた。**

**(1) `main` が30本ぶん巻き戻った。** 利用者の手元の `main` は **`#91` の頃のまま**だった ——
**PR は GitHub の画面で merge されており、ローカルに `git pull` されていなかった。**
`filter-repo` はその古い履歴を書き換え、`push --force` が**本物の `main` を上書きした。**
**`#92` から `#123` までが `main` から消えた。**

**手順が「手元の clone が `origin/main` と一致していること」を確かめさせていなかった。**
**下の 1 がそれである。**

**(2) アドレスは1件も消えていなかった。** 対応表が **`<ここに古いアドレス>` というプレースホルダのまま**だった。
**ヒアドキュメントで「そのまま流せる形」に見える指示を出したためである。**
`filter-repo` は正常に走り（全 SHA が変わった）、**置換だけが何にもマッチしなかった。**
**シェルは何も言わない。**

**手順が「push の前に0件になったことを確かめる」を独立の工程にしていなかった。**
**下の 6 がそれである（送る前に0件を確かめる、を独立の工程にした）。**

**復旧はできた** —— クラウド側の clone が force-push 直前の `main` を保持しており、
それを `restore/main-before-the-rewrite` として push し、利用者が `main` を戻した。
**失ったのは `#123` の merge commit ひとつで、中身は PR で戻した。**
**GitHub は merge 済みの PR の `refs/pull/N/merge` を消すので、あの merge commit 自体は回収できない。**

## 進め方

⚠ **オーケストレーターは force-push できない** —— **ブランチ削除も force-push も、クラウド側で
destructive として止められる**（2026-09-16 に両方確認）。**全部を利用者の Mac で流す。**

⚠ **`main` へ直接書き込まない・PR を通す**という規律（`CLAUDE.md`）を、**7で1回だけ外す。**
**履歴の書き換えは PR で通せない。****飛ばしたことをここに書いておく。**

### 0. 開いている PR を全部 merge するか閉じる

**書き換えたあとの `main` に対して、古い履歴の PR は行き先を失う。**

### 1. ⚠ 手元の clone が `origin` と一致していることを確かめる

**ここを飛ばすと `main` が巻き戻る。1回目がそれで壊れた。**

```bash
git fetch origin
git checkout main
git status --short                    # 何も出ないこと
git rev-parse HEAD origin/main        # 2行が同じ SHA であること
```

**違ったら `git pull --ff-only` で揃える。****揃わないなら、clone し直してから始める。**

### 2. 退避する

```bash
git bundle create ../mdoro-before-rewrite.bundle --all
git for-each-ref --format='%(refname) %(objectname)' > ../mdoro-refs-before.txt
```

**bundle は1ファイルで、そのまま `git clone` できる。**戻せることを確かめてから先へ進む。

### 3. 道具を入れる

```bash
brew install git-filter-repo
```

### 4. ⚠ 対応表を、履歴から組み立てる

**プレースホルダを置かない。1回目はそれを残したまま流し、置換が1件も起きなかった。**

**アドレスを手で打たずに、履歴が持っているものをそのまま使う。**

```bash
git log --all --format='%ae%n%ce' | sort -u      # まず、在るアドレスを全部見る
```

**出てきた中から、消したいものを `OLD` に入れる。**

```bash
OLD='...'                                        # 上の出力から選んで貼る
git log --all --format='%ae%n%ce' | grep -Fc "$OLD"   # 0 でないこと。ここが件数である
printf 'Soh <257237375+soh-arch@users.noreply.github.com> <%s>\n' "$OLD" > ../mailmap.txt
cat ../mailmap.txt                               # ⚠ 目で見る。`<...>` が2つ、中身が入っていること
```

**`257237375` は GitHub のユーザー ID である**（`https://api.github.com/users/soh-arch` が返す）。
**この形式が GitHub の noreply アドレスで、GitHub 側で本人に紐づく**（contribution も切れない）。

### 5. 置換する

```bash
git filter-repo --mailmap ../mailmap.txt --force
git remote add origin https://github.com/soh-arch/mdoro.git
```

**`--force` が要る** —— 作業ツリーが fresh clone でないため。
**`filter-repo` は `origin` を外す**ので、その場で戻す。

### 6. ⚠ 送る前に、0件になったことを確かめる

**これは独立の工程である。1回目は確かめずに送った。**

```bash
git log --all --format='%ae%n%ce' | grep -Fc "$OLD"    # 0 であること
```

⚠ **`filter-repo` は、置換が1件も起きなくても正常終了する。**
**SHA が全部変わったことは、置換が効いた証拠にならない。**
**0 が出なければ、4に戻る。**（`$OLD` を別のシェルで作った場合は入れ直す。）

### 7. 送る

```bash
git push --force origin main
```

⚠ **ここが取り消せない工程である。**2の bundle が手元にあることを先に確かめる。

### 8. 対応表を渡す

```bash
cp .git/filter-repo/commit-map ../commit-map.txt
```

**このファイルは旧 SHA と新 SHA が並んでいるだけで、個人情報を含まない。**
**これを渡せば、台帳が引く53個の SHA を機械的に書き換えた PR を出せる。**

### 9. GitHub Support に purge を依頼する

**PR に残る古い commit を消してもらう。**依頼には、リポジトリ名と、
**「履歴から機微情報を取り除いて force-push したので、PR に残る古い参照を消してほしい」**と書く。

### 10. 増えないようにする

```bash
git config user.email "257237375+soh-arch@users.noreply.github.com"
```

**GitHub の Settings → Emails で:**

- **Keep my email addresses private**
- **Block command line pushes that expose my email**

⚠ **10は今後の commit にしか効かない。**1〜9を飛ばして10だけやっても、**既にあるものは消えない。**

### 11. 公開してよいのは、9が終わってからである

**`docs/experiments/` を残すかどうか**（POL-219）と、**`Lychee`**（POL-271）は別の票である。
**公開の前に、両方とも閉じておく。**

## 影響

- **全 commit の SHA が変わる。** 手元に clone を持っている者は、**clone し直す。**
- **台帳が引く53個の SHA が無効になる。** 8で渡す対応表で機械的に直す。
- **PR 番号は1つも失われない。**
- **PR ページの diff は、9のあと壊れる。** **議論そのものは残る。**
