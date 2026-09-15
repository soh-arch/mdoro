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

## 進め方

⚠ **オーケストレーターは force-push できない見込みである** —— **ブランチ削除が 403 で弾かれた**（2026-09-16）。
**1〜6は利用者の Mac で流す。**

⚠ **`main` へ直接書き込まない・PR を通す**という規律（`CLAUDE.md`）を、**5で1回だけ外す。**
**履歴の書き換えは PR で通せない。****飛ばしたことをここに書いておく。**

### 0. 先に、開いている PR を全部 merge するか閉じる

**書き換えたあとの `main` に対して、古い履歴の PR は行き先を失う。**

### 1. 退避する

```bash
git bundle create ../mdoro-before-rewrite.bundle --all
git for-each-ref --format='%(refname) %(objectname)' > ../mdoro-refs-before.txt
```

**bundle は1ファイルで、そのまま `git clone` できる。**戻せることを確かめてから先へ進む。

### 2. 道具を入れる

```bash
brew install git-filter-repo
```

### 3. 対応表を書く

`../mailmap.txt` に1行。**左が新しい名前とアドレス、右が古いアドレス。**

```
Soh <257237375+soh-arch@users.noreply.github.com> <古いアドレス>
```

**`257237375` は GitHub のユーザー ID である**（`https://api.github.com/users/soh-arch` が返す）。
**この形式が GitHub の noreply アドレスで、GitHub 側で本人に紐づく。**

### 4. 置換する

```bash
git filter-repo --mailmap ../mailmap.txt --force
```

**`--force` が要る** —— 作業ツリーが fresh clone でないため。
**`filter-repo` は `origin` を外す**ので、次で戻す。

```bash
git remote add origin https://github.com/soh-arch/mdoro.git
```

**確かめる**（0 が出ること）:

```bash
git log --all --format='%ae %ce' | grep -c '<古いアドレスのローカル部>'
```

### 5. 送る

```bash
git push --force origin main
```

⚠ **ここが取り消せない工程である。**1の bundle が手元にあることを先に確かめる。

### 6. 対応表を渡す

```bash
cp .git/filter-repo/commit-map ../commit-map.txt
```

**このファイルは旧 SHA と新 SHA が並んでいるだけで、個人情報を含まない。**
**これを渡せば、台帳が引く53個の SHA を機械的に書き換えた PR を出せる。**

### 7. GitHub Support に purge を依頼する

**PR に残る古い commit を消してもらう。**依頼には、リポジトリ名と、
**「履歴から機微情報を取り除いて force-push したので、PR に残る古い参照を消してほしい」**と書く。

### 8. 増えないようにする

```bash
git config user.email "257237375+soh-arch@users.noreply.github.com"
```

**GitHub の Settings → Emails で:**

- **Keep my email addresses private**
- **Block command line pushes that expose my email**

⚠ **8は今後の commit にしか効かない。**1〜7を飛ばして8だけやっても、**既にある176件は消えない。**

### 9. 公開してよいのは、7が終わってからである

**`docs/experiments/` を残すかどうか**（POL-219）と、**`Lychee`**（POL-271）は別の票である。
**公開の前に、両方とも閉じておく。**

## 影響

- **全 commit の SHA が変わる。** 手元に clone を持っている者は、**clone し直す。**
- **台帳が引く53個の SHA が無効になる。** 6に書いた対応表で機械的に直す。
- **PR 番号は1つも失われない。**
- **PR ページの diff は、7のあと壊れる。** **議論そのものは残る。**
