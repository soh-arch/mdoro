# 0015 — `.task` がいつ再び走るのか（2026-09-18）

**問い**: SwiftUI の `.task` の中身は、いつ再び走るのか。とくに **macOS でウィンドウを閉じて
開き直したとき、そのウィンドウの中のビューに付いた `.task` はもう一度走るのか。**

このリポジトリはその答えに依存している —— **Mac のアプリの起動処理（`AppModel.start()`）は
ビューの `.task` から呼ばれる**ので、`.task` が2度走れば、サーバーも Bonjour の広告も2つになる。

**方法**: 一次情報のみ（Apple の Developer Documentation・WWDC セッション・リリースノート）。
**二次情報は使っていない。** そのうえで、このリポジトリに既にある実測と突き合わせた。

**対象**: SwiftUI（可用性は iOS 15.0 / macOS 12.0 以降。文書の参照日 2026-09-18）/
実測は macOS 26（2026-08-30・所有者の実機・1回）

## 答え

**一次情報が述べているのは「ビューの識別（identity）ごとに1回」であって、「現れるたび」ではない。**

**「ウィンドウを開き直すと `.task` が再び走る」と1文で述べた一次情報は無い。**
**3つの記述の連結と、このリポジトリの実測で支えられている。**

| 事実 | 確度 |
| :---- | :---- |
| **`.task` はビューが現れる前に走り、その寿命はビューの寿命に一致する。** ビューが取り除かれるか**識別が変わる**と cancel される | **文書化** |
| **`State` の文書は `.task` を「ビューが最初に現れたとき1回だけ呼ばれる」と呼ぶ** | **文書化** |
| **「ビューの寿命」とは、そのビューに結び付いた識別が続いている期間である**（WWDC21） | **文書化** |
| **`onAppear` / `onDisappear` に結び付いているとは、どの一次情報も述べていない** | **文書化（述べていない）** |
| **macOS でウィンドウを閉じることは「Scene が明示的に破棄される」ことである** —— `SceneStorage` の文書が「the window is closed on macOS」をその例として挙げている | **文書化** |
| **再実行の引き金として一次情報が挙げているのは2つだけ** —— ビューの識別の始まりと、`.task(id:)` の `id` の不等 | **文書化** |
| **macOS 26 / iOS 26 でこの振る舞いが変わったという記述は無い**（`updates/swiftui` に "task" の語が1件も無く、Xcode 26 と macOS 26 のリリースノートにも該当記述なし） | **文書化（述べていない）** |
| **ウィンドウを開き直すと `.task` が再び走る** | **帰結＋実測**（上の連結と、2026-08-30 の実測。**単独の条文では示せない**） |

引用（`View/task(name:priority:file:line:_:)`。シンボル名は `task(name:priority:file:line:_:)` で、
`.task { … }` はこれに解決する）:

> Use this modifier to perform an asynchronous task with a lifetime that matches that of the
> modified view. If the task doesn't finish before SwiftUI removes the view or the view changes
> identity, SwiftUI cancels the task.

`State` の文書:

> …you can defer the creation of the object using the `task(name:priority:file:line:_:)` modifier,
> which is called only once when the view first appears

WWDC21 セッション 10019「Discover concurrency in SwiftUI」
<https://developer.apple.com/videos/play/wwdc2021/10019/>:

> In the past, you might have used **onAppear** for this, but starting this year in SwiftUI, use
> the task modifier. … A task's lifetime is tied to the view's lifetime … and the task will be
> automatically canceled when the view's lifetime ends.

WWDC21 セッション 10022「Demystify SwiftUI」
<https://developer.apple.com/videos/play/wwdc2021/10022/>:

> Once the identity of the view changes or the view is removed, its lifetime ends. Whenever we
> talk about the lifetime of a view, we are referring to the duration of the identity associated
> with that view.

`SceneStorage` <https://developer.apple.com/documentation/swiftui/scenestorage>:

> If the `Scene` is explicitly destroyed (e.g. the switcher snapshot is destroyed on iPadOS or
> **the window is closed on macOS**), the data is also destroyed.

**この一文は `SceneStorage` の説明の中にあるが、主語は `Scene` 一般であり、
`WindowGroup` 限定とは書かれていない。**

## Mac のシーンは `WindowGroup` ではなく `Window` である

**この調査の途中で分かったことで、記述の訂正を1件伴う。**

`PomodoroMac/PomodoroMac/MdoroMacApp.swift` の主シーンは `Window("Mdoro", id:)` である。
**`WindowGroup` はこの target で一度も使われたことがない**（`git log -S 'WindowGroup' -- 'PomodoroMac/PomodoroMac/*'` が0件。
2026-08-30 の実測の時点の版も `Window` だった）。**`WindowGroup` を使っているのは iPhone 側だけである。**

**両者は文書上ふるまいが違う。**

| | `WindowGroup` | `Window` |
| :---- | :---- | :---- |
| `openWindow(id:)` | **新しいウィンドウを作る** | **既に開いていれば前面に出す** |
| ウィンドウごとの状態 | 文書に明記あり —— 「the system allocates new storage for any `State` … for each window that it creates」 | **記述が無い** |
| 主シーンを閉じたとき | アプリは動き続ける | **アプリが終了する**（文書に明記） |

出典: `OpenWindowAction` <https://developer.apple.com/documentation/swiftui/openwindowaction> /
`Window` <https://developer.apple.com/documentation/swiftui/window> /
`WindowGroup` <https://developer.apple.com/documentation/swiftui/windowgroup>

⚠ **したがって「新しいウィンドウは `State` の記憶域を新しく取る」は、`WindowGroup` についての記述であり、
このアプリの Mac 側には直接当たらない。** Mac 側で効いているのは
**`SceneStorage` の「閉じる＝ Scene の破棄」**のほうである。

## 確かめられなかったこと

- **同じ識別のビューが disappear → appear したときに `.task` が再び走るか**（タブの切り替え、
  `NavigationStack` の push / pop、`List` の遅延生成）。**一次情報は「識別ごとに1回」「最初に現れるとき1回」
  とだけ述べ、再出現に触れていない**
- **`Window`（単一シーン）を閉じてから `openWindow(id:)` で開き直したとき、シーンが作り直されるのか
  復元されるのか。** 一次情報は「既に開いていれば前面に出す」しか述べていない。**閉じている場合の記述が無い**
  （実測では `.task` が走っている）
- **iOS で `.task` が再実行される条件。** SwiftUI の文書はプラットフォーム差を述べておらず、**実測も無い。**
  iOS 側のシーン破棄条件は UIKit の `sceneDidDisconnect(_:)` にある（アプリスイッチャーでの明示的な
  閉じる操作、またはメモリ回収。**アプリを切り替えただけでは切断しない**）が、
  **SwiftUI の `WindowGroup` の1ウィンドウが1つの `UIScene` であるとは明文化されていない**
- **状態復元**（`restorationBehavior(_:)`、macOS 15.0 / iOS 18.0 以降）で起動時に開き直された
  ウィンドウの `.task` が走るか。文書は「サイズと位置を保存して起動時に開き直す」としか述べていない
- **SDK のヘッダ（`SwiftUI.swiftinterface`）は参照していない** —— 調査を行った環境は Linux で、macOS SDK が無い
- **「The task is created by `Task.immediate`」という一文が現行の文書にあるが、macOS 26.0 の時点で
  そうだったのか 26.x のどこかで変わったのかは、リリースノートにも `updates/swiftui` にも書かれていない**

## 影響を受ける記述

- **`docs/PUNCHLIST.md` の POL-114 が「`WindowGroup` の中のビューに付いた `.task`」と書いていた。**
  **観測は正しく、シーンの種別の名前だけが誤りである。**この調査に合わせて `Window` に直した
- **`MdoroMacApp.swift` と `AppModel.swift` のコメントが「ビューが現れるたび」と断定していた。**
  **一次情報が支えているのは「識別ごとに1回」までで、「現れるたび」は一段強い。**
  **開き直しについては実測が支えているので、そちらを根拠として書き直した**
- **`REQ-COM-003`（ペアリング画面を開くたびにサーバーが上がる）は `AppModel.start()` の冪等性に
  依存している。** その冪等性が必要な理由がこの事実である
