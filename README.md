# exbrand

`exbrand` は、Elixir において primitive 値に意味的な型境界を与えるための DSL ライブラリです。

`integer()` や `String.t()` を単なる type alias としてではなく、opaque な wrapper として扱うことで、`UserID` と `OrderID` のような値の取り違えを抑制します。

## 機能概要

- `defbrand` / `defbrands` による brand module 定義
- `use ExBrand, base: ...` による standalone brand 定義
- `new/1`, `cast/1`, `load/1`, `dump/1`, `unwrap/1`, `valid?/1` などの生成
- validator による検証と正規化
- `derive:`, `name:`, `aliases:`, `generator:` のサポート
- `Inspect`, `String.Chars` の標準実装
- `JSON.Encoder`, `Jason.Encoder`, `Phoenix.Param`, `Phoenix.HTML.Safe` の条件付き実装
- `Ecto.Type` / `Ecto.ParameterizedType` の条件付き統合

## 基本例

```elixir
defmodule MyApp.Types do
  use ExBrand

  defbrand UserID, :integer
  defbrand OrderID, :integer

  defbrands do
    brand Email, :string do
      validate(&String.contains?(&1, "@"))
      error(:invalid_email)
    end
  end
end
```

```elixir
{:ok, user_id} = MyApp.Types.UserID.new(1)
1 = MyApp.Types.UserID.unwrap(user_id)
true = MyApp.Types.UserID.valid?(1)
false = MyApp.Types.UserID.valid?("1")

{:error, :invalid_email} = MyApp.Types.Email.new("invalid")
```

## ドキュメント

- 導入と基本 API: [docs/getting-started.md](docs/getting-started.md)
- 詳細 API と統合: [docs/api-guide.md](docs/api-guide.md)
