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
**その「破棄される」は、同じ日のうちに是正されている**（POL-189）—— **いま何が起きるかは末尾の節にある。**

**依拠する条文**: REQ-PRT-005（既知のフィールドに載る未知の値の扱い）。
「この版に case が無い列挙値だけを拾う」という線引きを `DecodingError` の型**だけ**で表現すると、
上の事実により、**型に収まらない数はその線の外に落ちる。**

**このリポジトリの実装は、もうその線を error の型だけでは引いていない**（2026-09-03 の是正。`80e1c9b`）。
`CommandParams.value`（`Packages/MdoroCore/Sources/MdoroCore/Protocol/Messages.swift`）は
`DecodingError` でない throw も通したうえで、**届いたメッセージそのものが JSON として成り立っているかを
`JSONWellFormedness` に問う。** 型に収まらない数は**破棄されず、REQ-CFG-018 の `settingOutOfRange` が返る。**
押さえているのは `aNumberNoTypeHereCanHoldIsAnsweredForRatherThanDropped`
（`Packages/MdoroCore/Tests/MdoroCoreTests/ASettingWeCannotReadTests.swift`）。

**上の事実は、それでも条文の射程の内側にある。** error の型は判定の半分でしかなくなったが、
**その半分がこの事実のとおりに振る舞うことを前提に、残りの半分を文法の走査が負っている。**
