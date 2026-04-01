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
  defbrand CustomerID, :integer

  defbrands do
    brand Email, {:string, validate: &String.contains?(&1, "@"), error: :invalid_email}
    brand PositiveUserID, {:integer, validate: &(&1 > 0), error: :must_be_positive}
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
- `ecto_type/0`
- `ecto_parameterized_type/0`

## Standalone Brand

親モジュール配下ではなく、モジュール自身を brand として定義することもできます。

```elixir
defmodule MyApp.Types.UserID do
  use ExBrand, :integer
end
```

```elixir
user_id = MyApp.Types.UserID.new!(1)
1 = MyApp.Types.UserID.unwrap(user_id)
:integer = MyApp.Types.UserID.__base__()
```

## Custom Base Type

組み込みの `:integer` / `:binary` / `:string` 以外を使いたい場合は、
`ExBrand.Base` を実装した module を `use ExBrand, ...` や `defbrand ...` の引数として渡します。

```elixir
defmodule MyApp.Types.PrefixedStringBase do
  @behaviour ExBrand.Base

  def type_ast(_opts), do: quote(do: String.t())
  def ecto_type(_opts), do: :string

  def validate(value, opts) when is_binary(value) do
    if String.starts_with?(value, Keyword.fetch!(opts, :prefix)) do
      :ok
    else
      {:error, :invalid_type}
    end
  end

  def validate(_value, _opts), do: {:error, :invalid_type}
end

defmodule MyApp.Types.UserID do
  use ExBrand, {MyApp.Types.PrefixedStringBase, prefix: "usr_"}
end
```

module 単体も渡せます。設定値が必要な場合だけ
`{MyApp.Types.PrefixedStringBase, prefix: "usr_"}` のような tuple 形式を使います。
