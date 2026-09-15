# 0007. 原子的な差し替えは、ディレクトリではなくボリュームの制約である

- **調査日**: 2026-08-29
- **対象**: macOS 26.5.1（build 25F80）/ `MacOSX26.5.sdk`
- **依頼の理由**: 条文とコードが違うことを言っていた（軸 K・POL-078）。
  **REQ-PLT-004（MUST）は「サンドボックス外（`/tmp` 等）を跨ぐ `rename` は失敗する」、
  コードは「サンドボックス下ではディレクトリを跨げば失敗する」。**
  **これは「動かしてはいけない3原則」の1つ目の実装そのもの**であり、
  どちらが正しいかで一時ファイルの置き場所が決まる

## 問い

**「そもそも `EXDEV` と App Sandbox は無関係ではないか」という疑いを明示して依頼した。**

1. App Sandbox の下で `rename(2)` / `FileManager.replaceItemAt` は「ディレクトリを跨ぐ」と失敗するか
2. **`rename(2)` はそもそも同一ファイルシステム内でなければ失敗する（`EXDEV`）。
   サンドボックスの話とファイルシステムの話が混ざっていないか**
3. security-scoped bookmark で開いたディレクトリの下では何が許されるか
4. `FileManager.replaceItemAt` は内部で何をするか。Apple は「同一ディレクトリ」と書いているか
5. 条文とコード、どちらが正しいか

## 答え

**条文もコードも誤っている。**

**正しい制約は「同一ボリューム（同一ファイルシステム）であること」であり、
「同一ディレクトリ」でも「サンドボックスの制約」でもない。**
これは Apple が `replaceItemAt` の文書に明記している POSIX / Foundation の制約であって、
**App Sandbox とは無関係である。**

**問い2の見立てが正しかった。** サンドボックスの話とファイルシステムの話が混ざっていた。

**軸 K のこれまでの6件と同じ壊れ方である** —— **制約は本物（同一ボリューム）だが、
付いていた限定（サンドボックス／同一ディレクトリ）が誤り。**

## 根拠

### 1. サンドボックスに、ディレクトリの関係を見る規則は無い

`man 2 rename`（macOS 26.5.1 同梱、`BSD 4.2 June 3, 2021`）の DESCRIPTION:

> Both old and new must be of the same type ... and **must reside on the same file system.**

**ディレクトリについての制限は一切書かれていない。** ERRORS の全項目を確認したが、
「異なるディレクトリ」に対応するエラーコードは無い。`EXDEV` は "different logical devices (file systems)" である。

`/System/Library/Sandbox/Profiles/application.sb`（App Sandbox の基底プロファイル）を全文検索したが、
**`rename` という語も、ソースと宛先のディレクトリ関係を見る規則も存在しない。**
サンドボックスは `file-write-create` / `file-write-unlink` などの操作をパスフィルタに照らして
**両端を独立に**評価するだけである。

**決定的な反証がプロファイル本体にある。** `application.sb:812-813`:

```
(read-write-and-issue-extensions
  (mount-relative-regex "^/\\.TemporaryItems(/|$)"))
```

`read-write-and-issue-extensions` は `appsandbox-common.sb:81-92` で
`(allow file-read* file-clone …)` ＋ `(allow file-write* file-link …)` に展開される。
**App Sandbox はすべてのサンドボックスアプリに対し、あらゆるマウントポイント直下の
`.TemporaryItems/` への読み書きを無条件に許している。**
これは `itemReplacementDirectory` が起動ボリューム以外で使う場所そのものであり、
**「別階層の一時ディレクトリに書いてから rename で差し替える」という手順を、
App Sandbox が意図的に支えている**ことを示す。

**注意**（プロファイル自身の警告、`application.sb:5-8`）:

> WARNING: The sandbox rules in this file currently constitute **Apple System Private Interface**
> and are subject to change at any time and without notice.

**一次情報ではあるが、Apple は公開 API として保証していない。**
根拠として書けるが、**この行の存在に依存する設計はしないほうがよい。**

### 2. `/tmp` は EXDEV を起こさない — 混ざっていた

**実測**（このマシン、macOS 26.5.1）:

```
$ stat -f "%d %N" /private/tmp /private/var/folders ~ /
16777234 /private/tmp
16777234 /private/var/folders
16777234 /Users/<you>
16777234 /
```

⚠ **実測の出力のうち、ホームのパスのユーザー名だけを `<you>` に置き換えている。**
**device id は1桁も触っていない** —— この記録が主張しているのはその列だけである。

**すべて同一 device id である。** APFS の firmlink により、`/private/tmp`・`/private/var/folders`・
ユーザーのホームは**同じ Data ボリューム上の同じファイルシステム**にある。
**したがって条文の言う「`/tmp` を跨ぐ `rename`」は、`EXDEV` では失敗しない。**

**では `/tmp` に置くと何が起きるか。** `/System/Library/Sandbox/Profiles/system.sb:84-88` は
`/tmp` に対して `file-read-metadata` と `file-test-existence` しか与えていない（symlink 解決のため）。
**書き込みを許す規則は基底プロファイルのどこにも無い。**

**つまりサンドボックスアプリが `/private/tmp` に一時ファイルを置こうとすると、
`rename` ではなく `open` / `write` の段階で失敗する。**
**失敗する事実は合っているが、失敗する場所も理由も条文の説明と違う。**

**本当に `EXDEV` が起きるのは、ログフォルダが外付けドライブやネットワーク共有にある場合**（別ボリューム）であり、
**これはサンドボックスの有無と無関係に起きる。**

### 3. bookmark はディレクトリ単位ではなく、配下すべてに及ぶ

[Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox):

> the operating system extends your app's sandbox to items within that folder, **and recursively in nested folders**

プロファイル側の裏付け: `com.apple.security.files.user-selected.read-write` に対応するパス規則は
`application.sb` に**存在しない。** ファイルアクセスは `(appsandbox-extensions)` が展開する
`(allow file-write* file-link (extension "com.apple.app-sandbox.read-write"))` だけから来る。
`extension` フィルタは発行時のパスを祖先として持つ vnode に一致するため、
**ディレクトリに対して発行された extension は、そのサブツリー全体を覆う。**

**「同じフォルダの下の別ディレクトリ」は読み書きできる。ここは条文・コードのいずれの心配も当たらない。**

### 4. Apple は「同一ディレクトリ」と書いていない。しかも第一推奨ですらない

[`replaceItemAt(_:withItemAt:backupItemName:options:)`](https://developer.apple.com/documentation/foundation/filemanager/replaceitemat(_:withitemat:backupitemname:options:)) の Discussion:

> This method works only when the `originalItemURL` and `newItemURL` parameters are located on the
> **same volume.** … you can call the `url(for:in:appropriateFor:create:)` method, passing
> `itemReplacementDirectory` as the search path directory, to get a temporary URL **on the
> destination's volume** that is suitable for use with this method.

同ページの `newItemURL` パラメータ説明（`MacOSX26.5.sdk` の `NSFileManager.h:290` に同文）:

> **It is recommended that you put this item in a temporary directory as provided by the OS.**
> **If a temporary directory is not available**, put this item in a uniquely named directory that is
> in the same directory as the original item.

**同一ディレクトリは「OS の一時ディレクトリが使えないときのフォールバック」として書かれており、
Apple の第一推奨ではない。** 条文が MUST にしている手順は、**Apple の推奨と第一・第二が入れ替わっている。**

補強: `url(for:in:appropriateFor:create:)` の `appropriateFor` の説明は
**"Only the volume of this parameter is used."** ——
**Apple の API 自体がボリューム単位で設計されており、ディレクトリは見ていない。**

**内部実装は不明。** `Foundation` の import には `_rename`（libSystem）と `_FSRenameUnicode`（CoreServices）があり、
`exchangedata` は無い。**しかし逆アセンブルして確認したわけではないので、この API がどの経路を通るかは不明とする。**

なお `appsandbox-common.sb:689-695` の `com.apple.app-sandbox.replace-file` という特権ファイル操作は、
`com.apple.developer.security.privileged-file-operations` を持つアプリにしか与えられない
（`application.sb:873-874`）。**通常のサンドボックスアプリの `replaceItemAt` はこの経路を通らない。**

### 5. 正しい言い方

> **一時ファイルはログファイルと同一ボリューム上に置かなければならない。**
> これは `rename(2)` が同一ファイルシステム内でしか成立しない（`EXDEV`）ことと、
> `FileManager.replaceItemAt` が「同一ボリューム上でのみ動作する」と文書で明記していることによる。
> **同一ディレクトリに置くことはこの制約を満たす十分条件であって、必要条件ではない。**
> **App Sandbox はこの制約に関与しない。**

## 確度

| 主張 | 確度 |
| :---- | :---- |
| `rename(2)` は同一ファイルシステム内でのみ成立する。ディレクトリの制限は無い | **文書化**（`man 2 rename`） |
| `replaceItemAt` は同一ボリュームでのみ動作する | **文書化** |
| **Apple の第一推奨は OS の一時ディレクトリ。同一ディレクトリは次善策** | **文書化**（+ SDK ヘッダ） |
| `appropriateFor` は**ボリュームだけ**を見る | **文書化** |
| App Sandbox に `rename` の規則もディレクトリ関係の規則も無い | **文書化**（ただし Apple は「私的インタフェース」と宣言） |
| `.TemporaryItems/` への読み書きが全アプリに許されている | **文書化**（同上） |
| **`/private/tmp` とホームは同一 device id**（firmlink） | **実測** |
| `/tmp` への書き込みは sandbox のパス規則で拒否される | **文書化**（`system.sb`） |
| bookmark はディレクトリの**サブツリー全体**を覆う | **文書化** |
| `replaceItemAt` が実際に呼ぶシステムコール | **不明** |

## 確かめられなかったこと

**推測で埋めない。**

- **`-[NSFileManager replaceItemAtURL:…]` が実際に呼ぶシステムコール。** 逆アセンブルしていない
- **外付けボリューム / SMB 共有上のログフォルダで、`url(for:.itemReplacementDirectory, appropriateFor:)` が
  実際に成功するか。** プロファイルの規則から成功するはずだと読めるが、**実測していない**
- **`NSTemporaryDirectory()` がサンドボックスアプリでコンテナ内に解決されること。**
  実在は観測したが、Apple の公開文書に明記を見つけられなかった
- **WWDC のセッション**は該当するものを特定できなかった
- [Apple Developer Forums thread 676124](https://developer.apple.com/forums/thread/676124) は**二次情報**として扱う。
  内容は「サンドボックス下で `rename()` 自体は成功したが、その後の読み込みが拒否され、FAT32 でのみ再現」で、
  **「ディレクトリを跨ぐと rename が失敗する」とは別の話。根拠には使っていない**

## 影響を受ける記述

**列挙のみ。直し方はこの記録では判断しない。**

| 箇所 | 理由 |
| :---- | :---- |
| REQ-PLT-004（`SPEC.md:575`） | **理由が誤り。** `/tmp` は同一ファイルシステムなので `EXDEV` は起きない。サンドボックスアプリで失敗するのは事実だが、失敗するのは `rename` ではなく**書き込みの段階**であり、原因は**サンドボックスのパス規則** |
| **REQ-LOG-004（`SPEC.md:809`）** | **同じ誤った前提の上に立っている。** 「一時ファイルを同一ディレクトリに置く必要があるため、出力先はフォルダとして選ばせる」——**前段が誤り** |
| `LogWriter.swift:117-118` / `FileStateStore.swift:3-4` | **端的に誤り。** ディレクトリを跨ぐ `rename` は同一ボリューム内なら成功する |
| `PLATFORM.md:202` | `未検証` の文案が「サンドボックス下では、一時ファイルを同一ディレクトリに」となっている。**切り分け方（手段と事実を分ける）は正しいが、事実として残した側が誤り** |
