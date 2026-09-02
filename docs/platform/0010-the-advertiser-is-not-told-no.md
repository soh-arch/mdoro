# 0010 — 広告する側は、拒否を知らされない（macOS）

**問い**: macOS アプリは、ローカルネットワーク許可の拒否によって自分の Bonjour 広告が
不可視になっていることを、検出できるか（POL-164 の実装可否）。

**方法**: 一次情報の調査（platform-researcher・2026-09-02）。実機検証はしていない。
**対象**: macOS 26（TN3179 現行版 / macOS 26.5 SDK ヘッダ / WWDC20 10110）。

## 分かったこと

| 事実 | 確度 |
| :---- | :---- |
| `NWListener` は許可拒否を API に表出しない。TN3179 が挙げる検出手段は browse 側の2つだけで、登録側の経路は存在しない。`listener.h` の状態定義（`waiting` / `failed`）にも拒否の意味づけは無い | 文書化（不在の確認） |
| 枠組みの内部（`_NWAdvertiser`）は `advertising denied by policy` を受け取り、**os_log に落としてアプリに上げない**（フォーラムの観察。0009 の実測「エラーが1文字も出ない」と整合） | 二次情報 |
| "There's no general API that returns whether the current process has local network access (FB8711182)"（TN3179）。**対象に macOS 15+ を明記**しており、iOS 限定ではない | 文書化 |
| 許可は単数の "the Local Network privilege"。TN3179 の同じ要否表が登録と探索の両方を "yes" とする（「トグルは1つ」の明文1文は無い） | 文書化＋帰結 |
| **唯一の文書化された検出は self-browse**（browse 側の `kDNSServiceErr_PolicyDenied`。TN3179 のコード例にプラットフォーム限定なし）。ただし **macOS 実機で実際に返るかは未実測**で、「拒否は既存に効かない」（0009）が browse にも及ぶかも不明 | 文書化／未検証 |
| `DNSServiceRegister` コールバックへの PolicyDenied 到達は、シミュレータ環境の事例と内部ログという二次情報のみ。macOS 実機では不明 | 二次情報／不明 |

## 確かめられなかったこと

- macOS 26 実機で self-browse が PolicyDenied を返すか。継続中の browse が後からの OFF を拾うか
- macOS 26 実機で `DNSServiceRegister` コールバックに PolicyDenied が届くか

**主要出典**: [TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy) /
macOS 26.5 SDK `dns_sd.h` L801, L1268-1291・`listener.h` L43-64, L349-378 /
[WWDC20 10110](https://developer.apple.com/videos/play/wwdc2020/10110/) /
DevForums 757766・766133・664264（二次情報）
