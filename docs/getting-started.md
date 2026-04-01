# ExBrand 導入ガイド

## 目的

ExBrand は、`integer()` や `String.t()` のような primitive 値に対して、意味的な型境界を与えるためのライブラリです。

`UserID` と `OrderID` のように実行時表現が同じ値でも、brand module を分けて `@opaque` な wrapper として扱うことで、値の取り違えを抑制します。

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

    brand PositiveUserID, :integer do
      validate(&(&1 > 0))
      error(:must_be_positive)
    end
  end
end
```

```elixir
{:ok, user_id} = MyApp.Types.UserID.new(1)
1 = MyApp.Types.UserID.unwrap(user_id)
true = MyApp.Types.UserID.valid?(1)
false = MyApp.Types.UserID.valid?("1")
{:ok, same_user_id} = MyApp.Types.UserID.cast(user_id)

{:error, :invalid_email} = MyApp.Types.Email.new("invalid")
```

## 生成される API

生成される各 brand module は、主に次の型と関数を公開します。

- `@type raw()`
- `@opaque t()`
- `new/1`
- `new!/1`
- `cast/1`
- `cast!/1`
- `load/1`
- `dump/1`
- `unwrap/1`
- `valid?/1`
- `gen/0`
- `is_brand?/1`
- `__base__/0`
- `__name__/0`
- `__meta__/0`
- `__brand__/0`
- `ecto_type/0`
- `ecto_parameterized_type/0`

## Standalone Brand

親モジュール配下ではなく、モジュール自身を brand として定義することもできます。

```elixir
defmodule MyApp.Types.UserID do
  use ExBrand, base: :integer
end
```

```elixir
user_id = MyApp.Types.UserID.new!(1)
1 = MyApp.Types.UserID.unwrap(user_id)
:integer = MyApp.Types.UserID.__base__()
```
