# 0012. 型に収まらない数は `DecodingError` ではない

- **調査**: 2026-09-03
- **確度**: **実測**（最小再現あり）
- **確認日**: 2026-09-03
- **対象**: Foundation の `JSONDecoder`（Swift 6.3 / macOS 26）

## 事実

**JSON の数が Swift の型に収まらないとき、ネストした復号の catch に届くのは `DecodingError` ではない。**
`JSONError`（Foundation 内部の型）である。

`catch let error as DecodingError` はこれを**素通りさせる**。したがって、
「未知の値だけを拾って復号を続ける」ために `DecodingError` を捕まえる書き方をすると、
**型に収まらない数は拾えず、メッセージごと throw される。**

**外から見ると `dataCorrupted` に見える。** `JSONDecoder.decode` が最後にそれを
`DecodingError.dataCorrupted` で包むためである。**スタックの一番外で型を見て分岐を推定すると読み違える。**

## 最小再現

```swift
struct Inner: Codable { var hour: Int? }
struct Outer: Decodable {
    enum K: String, CodingKey { case inner }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        do { _ = try c.decodeIfPresent(Inner.self, forKey: .inner) }
        catch let e as DecodingError { print("DecodingError: \(e)") }
        catch { print("NOT a DecodingError: \(type(of: error))") }   // ← ここに来る
    }
}
_ = try? JSONDecoder().decode(Outer.self, from: Data(#"{"inner":{"hour":4.5}}"#.utf8))
```

| 入力 | ネストした catch が見るもの |
| :---- | :---- |
| `{"hour": 4.5}`（整数でない数） | **`JSONError`**（`DecodingError` ではない） |
| `{"hour": 99999999999999999999999}`（桁あふれ） | **`JSONError`** |
| `{"hour": "four"}`（型違い） | `DecodingError.typeMismatch` |
| 列挙型に無い raw 値 | `DecodingError.dataCorrupted` |

## なぜ記録するか

**同じ場所で2回読み違えた。** 2026-09-03、検証役が「`4.5` は `dataCorrupted` として拾われ、
`settingOutOfRange` が返る」と報告し（外側で包まれた型を見ていた）、
実装役が実経路で測り直して「throw して破棄される」と覆した。オーケストレーターが独立に再現して確定した。

**依拠する条文**: REQ-PRT-005（既知のフィールドに載る未知の値の扱い）。
「この版に case が無い列挙値だけを拾う」という線引きを `DecodingError` の型で表現している以上、
**何が `DecodingError` で何がそうでないかは、条文の射程そのものである。**
