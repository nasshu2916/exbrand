# Getting Started

このドキュメントは、ExBrand を既存の Elixir アプリへ導入して brand と schema を使い始めるまでの最短手順をまとめたものです。

## 1. 依存を追加する

```elixir
defp deps do
  [
    {:ex_brand, path: "../ex_brand"}
  ]
end
```

```bash
mix deps.get
```

## 2. Brand を定義する

まずは feature 単位で brand をまとめるモジュールを作ります。

```elixir
defmodule MyApp.Accounts.Types do
  use ExBrand

  defbrand UserID, :integer

  defbrand Email,
           {:string,
            validate: fn raw ->
              normalized = raw |> String.trim() |> String.downcase()

              if String.contains?(normalized, "@") do
                {:ok, normalized}
              else
                {:error, :invalid_email}
              end
            end,
            name: "Email Address"}
end
```

これで次のモジュールが生成されます。

- `MyApp.Accounts.Types.UserID`
- `MyApp.Accounts.Types.Email`

## 3. Brand を使う

```elixir
alias MyApp.Accounts.Types

{:ok, user_id} = Types.UserID.new(1)
Types.UserID.unwrap(user_id)
#=> 1

Types.UserID.new("1")
#=> {:error, :invalid_type}

Types.Email.new!("  USER@EXAMPLE.COM  ")
|> Types.Email.unwrap()
#=> "user@example.com"
```

`new/1` は失敗を戻り値で返し、`new!/1` は `ExBrand.Error` を送出します。

## 4. ルールを追加する

brand には複数の付加情報を持たせられます。

```elixir
defmodule MyApp.Accounts.Types do
  use ExBrand

  defbrand PositiveUserID,
           {:integer,
            validate: &(&1 > 0),
            error: :must_be_positive,
            generator: {:integer_generator, min: 1},
            name: "User ID"}
end
```

使い分けは次のとおりです。

- `validate:` 独自検証や正規化
- `error:` `validate:` が `false` を返したときのエラー理由
- `generator:` generator のメタデータ
- `name:` 表示名
- `derive:` protocol 実装の導出

## 5. Custom Base を使う

組み込み base で足りない場合は `ExBrand.Base` を実装します。

```elixir
defmodule MyApp.Types.PrefixedString do
  @behaviour ExBrand.Base

  def type_ast(_opts), do: quote(do: String.t())
  def ecto_type(_opts), do: :string

  def validate(value, opts) when is_binary(value) do
    prefix = Keyword.fetch!(opts, :prefix)
    if String.starts_with?(value, prefix), do: :ok, else: {:error, :invalid_type}
  end

  def validate(_value, _opts), do: {:error, :invalid_type}
end

defmodule MyApp.Accounts.Types do
  use ExBrand

  defbrand UserToken, {MyApp.Types.PrefixedString, prefix: "usr_"}
end
```

## 6. Schema DSL を導入する

API 入口の検証には `ExBrand.Schema` を使います。

```elixir
defmodule MyApp.Accounts.UserPayload do
  use ExBrand.Schema

  field :user_id, MyApp.Accounts.Types.UserID
  field :email, {MyApp.Accounts.Types.Email, field: "contactEmail"}
  field :age, {:integer, minimum: 18, error: :too_young}
  field :tags, {[{:string, min_length: 2}], min_items: 1, unique_items: true}
end
```

```elixir
MyApp.Accounts.UserPayload.validate(%{
  "contactEmail" => "user@example.com",
  user_id: 1,
  age: 20,
  tags: ["elixir", "otp"]
})
```

成功時は brand を含む正規化済み map が返り、失敗時はフィールドごとのエラー map が返ります。

## 7. Ecto へ組み込む

Ecto がロードされていれば、brand モジュールに `ecto_type/0` が生成されます。

```elixir
schema "users" do
  field :user_id, MyApp.Accounts.Types.UserID.ecto_type()
  field :email, MyApp.Accounts.Types.Email.ecto_type()
end
```

changeset では raw 値をそのまま `cast/4` に渡せます。ExBrand 側が brand に変換します。

## 8. Phoenix / JSON へ組み込む

次のライブラリが存在すると、自動で protocol 実装が入ります。

- `Jason` または `JSON`
- `Phoenix.Param`
- `Phoenix.HTML.Safe`

そのため、controller や JSON view では raw 値へ手で戻さなくても動く場面があります。ただしレスポンス設計を明示したいなら、`unwrap/1` を使って raw 値へ戻してから組み立てる方が読みやすいです。

## 9. 実行時設定を調整する

schema のエラー収集方針は実行時に切り替えられます。

```elixir
ExBrand.Schema.set_runtime_config!(fail_fast: true)
ExBrand.Schema.set_runtime_config!(deferred_checks: [:enum, :format])
```

テスト中に切り替える場合は、終了時に `:unset` で戻しておくと影響範囲を限定できます。

## 10. 署名検証を有効にする

brand struct の改ざん検知が必要なら、アプリ設定で有効化します。

```elixir
config :ex_brand, :signature_verification, true
```

有効時は brand 内部に署名が保存され、改ざん済み struct に対する `unwrap/1` や周辺 adapter の利用が失敗します。
