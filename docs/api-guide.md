# ExBrand API ガイド

## Cast API

`cast/1` は、Web や params などの境界で raw 値または同一 brand の値を受け取り、brand 値へ正規化する API です。

```elixir
{:ok, user_id} = MyApp.Types.UserID.cast(1)
{:ok, ^user_id} = MyApp.Types.UserID.cast(user_id)
{:error, :invalid_type} = MyApp.Types.UserID.cast("1")
```

すでに brand 値を渡した場合でも、内部 raw 値を再検証します。  
`cast!/1` は失敗時に `ExBrand.Error` を raise します。

## Ecto Load / Dump

DB 境界の `load` / `dump` は brand module 直下ではなく、Ecto adapter 側で扱います。

```elixir
{:ok, user_id} = MyApp.Types.UserID.EctoType.load(1)
:error = MyApp.Types.UserID.EctoType.load(MyApp.Types.UserID.new!(1))

{:ok, 1} = MyApp.Types.UserID.EctoType.dump(user_id)
{:ok, 1} = MyApp.Types.UserID.EctoType.dump(1)
:error = MyApp.Types.UserID.EctoType.dump("1")
```

- `EctoType.load/1` は DB から読んだ raw 値だけを受け付けます
- `EctoType.dump/1` は brand 値または妥当な raw 値を DB 保存用 raw 値へ変換します

## Validator

`validate:` には 1 引数関数を渡します。validator の戻り値として受け付ける形式は次のとおりです。

- `true`
- `false`
- `:ok`
- `{:ok, normalized_raw}`
- `{:error, reason}`

`{:ok, normalized_raw}` を返した場合、`normalized_raw` が brand の内部値として保持されます。

```elixir
defmodule MyApp.Types.NormalizedEmail do
  use ExBrand,
      {:string,
       validate: fn raw ->
         normalized = raw |> String.trim() |> String.downcase()

         if String.contains?(normalized, "@") do
           {:ok, normalized}
         else
           {:error, :invalid_email}
         end
       end}
end
```

```elixir
email = MyApp.Types.NormalizedEmail.new!("  USER@EXAMPLE.COM  ")
"user@example.com" = MyApp.Types.NormalizedEmail.unwrap(email)
```

## Schema DSL

複数フィールドをまとめて検証したい場合は `ExBrand.Schema` を使います。

```elixir
defmodule MyApp.UserParams do
  use ExBrand.Schema

  field :user_id, MyApp.Types.UserID
  field :email, MyApp.Types.Email
  field :age, {:integer, minimum: 18, error: :too_young}
  field :nickname, {:string, optional: true}
  field :status, {:string, default: "active"}
  field :contact_email, {MyApp.Types.Email, field: "contactEmail"}
  field :tags, {[{:string, min_length: 2}], min_items: 1, unique_items: true}
end
```

```elixir
{:ok, params} =
  MyApp.UserParams.validate(%{
    "user_id" => 1,
    "contactEmail" => "contact@example.com",
    email: "user@example.com",
    age: 20
  })
```

この例では次のように振る舞います。

- `user_id` と `email` は brand module の `cast/1` で検証される
- `age` は raw の `:integer` と `minimum: 18` の両方で検証される
- `nickname` は未指定でも `nil` で返る
- `status` は未指定なら `"active"` が入る
- `contact_email` は入力の `"contactEmail"` キーを読む
- `tags` は配列要素と配列全体の制約を両方検証する

`validate/1` は `{:ok, map}` または `{:error, %{field => reason}}` を返し、
`validate!/1` は失敗時に `ArgumentError` を raise します。

主な制約:

- `minimum`, `maximum`
- `min_length`, `max_length`
- `min_items`, `max_items`, `unique_items`
- `enum`
- `format: :email | :datetime`
- `nullable`
- `optional`
- `default`
- `field`
- `tolerant`

既存の `validate:` / `error:` も後方互換のため利用できます。

## `generator:`

property-based testing で使う generator は `generator:` で定義できます。brand module からは `gen/0` で参照します。

```elixir
defmodule MyApp.Types do
  use ExBrand

  defbrand UserID, {:integer, generator: StreamData.positive_integer()}
  defbrand OrderID, {:integer, name: "Order ID"}
end
```

```elixir
generator = MyApp.Types.UserID.gen()
```

`generator:` には generator 式そのものも、`fn -> ... end` のような 0 引数関数も渡せます。0 引数関数を渡した場合、`gen/0` 呼び出し時に評価されます。

## `derive:`

brand module には `derive:` を指定できます。`Inspect` はライブラリ側で実装されるため、`derive:` に含めても除外されます。

```elixir
defmodule MyApp.Serializable do
  defprotocol Protocol do
    def serialize(term)
  end
end

defmodule MyApp.Types.DerivedUserID do
  use ExBrand, {:integer, derive: [{MyApp.Serializable.Protocol, tag: :user_id}]}
end
```

## `name:`

brand には表示名を付けられます。指定した名前は `__name__/0`、`__meta__/0`、`Inspect`、例外メッセージで使われます。

```elixir
defmodule MyApp.Types do
  use ExBrand

  defbrand UserID, {:integer, name: "User ID"}
end
```

```elixir
MyApp.Types.UserID.__name__()
#=> "User ID"

inspect(MyApp.Types.UserID.new!(1))
#=> "#User ID<1>"
```

## `aliases:`

親モジュール側で `aliases:` を指定すると、列挙した brand に対してのみ alias を生成できます。

```elixir
defmodule MyApp.Types do
  use ExBrand, aliases: [UserID, OrderID]

  defbrand UserID, :integer
  defbrand OrderID, :integer

  def user_id_base, do: UserID.__base__()
end
```

`aliases:` が未指定、または `false` の場合、alias は生成されません。

## Custom Base Type

brand spec には組み込みの `:integer` / `:binary` / `:string` だけでなく、
`ExBrand.Base` を実装した custom base module も指定できます。

custom base module には次の callback が必要です。

- `type_ast/1`: 生成される `raw()` 型の typespec AST を返す
- `validate/2`: raw 値がその base に適合するか検証する
- `ecto_type/1`: `Ecto.Type` / `Ecto.ParameterizedType` で返す型を指定する

```elixir
defmodule MyApp.Types.PrefixedStringBase do
  @behaviour ExBrand.Base

  def type_ast(_opts), do: quote(do: String.t())

  def ecto_type(opts), do: Keyword.get(opts, :ecto_type, :string)

  def validate(value, opts) when is_binary(value) do
    prefix = Keyword.fetch!(opts, :prefix)

    if String.starts_with?(value, prefix) do
      :ok
    else
      {:error, :invalid_type}
    end
  end

  def validate(_value, _opts), do: {:error, :invalid_type}
end
```

```elixir
defmodule MyApp.Types.UserID do
  use ExBrand, {MyApp.Types.PrefixedStringBase, prefix: "usr_", ecto_type: :string}
end
```

この例では次のように振る舞います。

- `raw()` は `String.t()` になる
- `"usr_"` で始まる文字列だけを受け付ける
- `Ecto.Type.type/0` と `Ecto.ParameterizedType.type/1` は `:string` を返す

base module に設定値が不要なら、`use ExBrand, MyApp.Types.PrefixedStringBase` のように
module 単体でも指定できます。

## Generic Helper API

brand module を意識せずに raw 値へ戻したい場合は、`ExBrand.unwrap/1` と `ExBrand.maybe_unwrap/1` を使えます。

```elixir
user_id = MyApp.Types.UserID.new!(1)

1 = ExBrand.unwrap(user_id)
1 = ExBrand.maybe_unwrap(user_id)
"plain" = ExBrand.maybe_unwrap("plain")
```

`ExBrand.unwrap/1` は ExBrand の brand 値のみを受け付け、そうでない値には `ArgumentError` を raise します。  
`ExBrand.maybe_unwrap/1` は brand なら raw 値を返し、brand でなければ元の値をそのまま返します。

また、brand 値は内部署名付きで生成されるため、`%Brand{...}` による偽造や `%{brand | ...}` による不正更新は `unwrap/1` や各 protocol 実装で拒否されます。

パフォーマンスを優先したい場合は、brand コンパイル時の設定で署名検証を無効化できます。

```elixir
config :ex_brand, signature_verification: false
```

デフォルトは `false` です。この設定は brand module の生成時に参照されます。`false` にすると新しくコンパイルされる brand は `__signature__` を持たず、偽造・更新検知も行いません。必要な場合だけ `true` を明示設定してください。

## Reflection API

各 brand module は、自身の定義情報を参照するための reflection API も公開します。

```elixir
iex> MyApp.Types.UserID.__meta__()
%{
  module: MyApp.Types.UserID,
  base: :integer,
  validator: nil,
  generator: nil,
  error: nil
}
```

## Protocol 実装

ExBrand が自動生成する protocol 実装は次のとおりです。

常に実装される protocol:

- `Inspect`
- `String.Chars`

対象 protocol がロード済みの場合に実装される protocol:

- `JSON.Encoder`
- `Jason.Encoder`
- `Phoenix.Param`
- `Phoenix.HTML.Safe`

このライブラリ自体は `JSON`, `Jason`, `Phoenix` への dependency を持ちません。これらの protocol を利用する場合は、利用側アプリケーションで必要な dependency を追加してください。

## Ecto 統合

`Ecto` がロード済みの場合、各 brand module には `ecto_type/0` と `ecto_parameterized_type/0` が追加されます。

```elixir
defmodule MyApp.Schema do
  use Ecto.Schema

  schema "users" do
    field :user_id, MyApp.Types.UserID.ecto_type()
    field :email, MyApp.Types.Email.ecto_parameterized_type()
  end
end
```

`ecto_type/0` は `MyApp.Types.UserID.EctoType` のような brand 専用 `Ecto.Type` module を返します。  
`ecto_parameterized_type/0` は `{MyApp.Types.UserID.EctoParameterizedType, []}` の形を返します。

## 追加 Protocol 実装

ExBrand が自動実装しない protocol については、利用側で通常の `defimpl` を追加できます。

```elixir
defprotocol MyApp.Serializable do
  def serialize(term)
end

defmodule MyApp.Types.UserID do
  use ExBrand, :integer
end

defimpl MyApp.Serializable, for: MyApp.Types.UserID do
  def serialize(value) do
    {:user_id, MyApp.Types.UserID.unwrap(value)}
  end
end
```

`derive:` で導出可能な protocol であれば、brand 定義時に指定することもできます。

```elixir
defmodule MyApp.Types.UserID do
  use ExBrand, {:integer, derive: [MyApp.Serializable]}
end
```
