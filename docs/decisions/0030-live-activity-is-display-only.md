# 0030. Live Activity は表示に徹する（ボタンを置かない）

- **状態**: accepted
- **日付**: 2026-08-28

## 文脈

Live Activity に「一時停止 / 再開」を `LiveActivityIntent` として置いていた（REQ-UIX-024、SHOULD）。
**実機で、押しても何も起きないことが報告された**（2026-08-28）。

コードを追った結果、原因は構造にあった。

```
perform() → LiveActivityCommandBridge.send()
          → handler は ClientModel.start() が入れる（＝画面が作られたときだけ）
          → handler は isConnected を見て、false なら何もしない
```

**iPhone が suspend されるとアプリのコードは実行されない**（[`docs/platform/0002`](../platform/0002-live-activity-background-start-and-suspend.md)）。したがって:

| 状況 | 結果 |
| :---- | :---- |
| アプリが前面・接続中 | 効く（が、そのとき利用者はアプリを見ている） |
| ロック中・バックグラウンド | `isConnected` が false → **何も起きない** |
| アプリが終了済み | handler が存在しない → **何も起きない** |

さらに、ボタンは**有効に見えていた。** `state.isConnected` は最後に送った値で、
suspend 直前が接続中なら true のまま残る。

REQ-UIX-024 は `perform()` の中で**再接続を試みること**を求めていたが、それは実装していなかった。

## 判断

**Live Activity からボタンを外す。ロック画面・ダイナミックアイランドの両方から。**
Live Activity は**残り時間と状態の表示に徹する。**

**ダイナミックアイランドだけを外すことはできない。**
`ActivityConfiguration` は `dynamicIsland:` を必須とし、Live Activity がある限り必ず提示される。
「アイランドの廃止」は Live Activity ごとの廃止と同義であり、それは採らない。

REQ-UIX-024 は**条件つきの条文へ書き換える**。
再接続と失敗の提示を実装しない限り、**ボタンを置いてはならない。**

## 理由・設計意図

**効かないものを置かない。** 押して何も起きないボタンは、機能が無いことより悪い。
利用者は自分の操作を疑い、次に製品を疑う。
工程11 で定めた REQ-UIX-045（無効な操作には理由を示す）と同じ原則の、より強い形である。

**機能の豊富さより誠実さを採る**（プロダクトオーナーの言、2026-08-28）。

**[0009](0009-live-activity-should-not-must.md) と一貫している。**
あの記録は「Live Activity はセッション終了を知らせる手段ではない、
アプリが動いている間の可視化に徹する」と定めた。**操作面でもない**、が今回の追加である。

**将来の実装を否定しない。** REQ-UIX-024 の条件（`perform()` 内での再接続と、
送れなかったことの提示）を満たせるなら、そのとき戻せばよい。
条文を条件つきで残すのは、そのためである。

## 影響

| 対象 | 内容 |
| :---- | :---- |
| REQ-UIX-024 | SHOULD のまま。**条件を満たさない限りボタンを置いてはならない**を追加 |
| 実装 | `Controls`（widget）、`LiveActivityIntents.swift`、`LiveActivityCommandBridge` を削除 |
| `ContentState.isConnected` | **残す。** 接続が切れていることの表示に使う（REQ-UIX-023） |

## 出典と確度

- **事実**: 押しても効かないことは 2026-08-28 の実機報告。原因はソースの確認による。
- **事実**: **依拠すべきは「suspend 中はアプリのコードが実行されない」である**
  （[`docs/platform/0002`](../platform/0002-live-activity-background-start-and-suspend.md)、2026-08-29）。
  **2026-08-29 以前、この欄は `CONTEXT.md` §3 を「一次情報で確認済み」として指していたが、
  §3 にその出典は無く、現在は [0038](0038-platform-facts-are-not-the-specs-job.md) により空である。**
  **WebSocket が切れること自体は現行の一次情報で確認できていない**が、
  **コードが走らない以上、ソケットの生死はこの判断を変えない。**
- **事実**: `ActivityConfiguration` が `dynamicIsland:` を必須とすることは API 定義による。
