# ExBrand

ExBrand は、Elixir のプリミティブ値に意味的な境界を与えるための brand DSL です。`integer()` や `String.t()` をそのまま渡し回す代わりに、`UserID` や `Email` のような専用型を生成し、生成時に検証と正規化をまとめて適用できます。

このリポジトリには次の 2 つの機能があります。

- `ExBrand`: brand 型を定義する DSL
- `ExBrand.Schema`: API 入力のような map/list を宣言的に検証する schema DSL

## 何ができるか

- `defbrand` で distinct な brand 型を生成する
- `new/1` と `new!/1` で raw 値を安全に brand 化する
- `validate:` で独自検証や正規化を追加する
- `generator:` や `derive:` を brand 定義に持たせる
- `Ecto.Type` / `Ecto.ParameterizedType` を自動生成する
- `Jason.Encoder` / `JSON.Encoder` / `Phoenix.Param` / `Phoenix.HTML.Safe` を条件付きで実装する
- `ExBrand.Schema` で入れ子の map/list を検証し、brand を含む正規化済みデータを返す

## インストール

`mix.exs` に依存を追加します。

```elixir
defp deps do
  [
    {:ex_brand, path: "../ex_brand"}
  ]
end
```

公開パッケージ化されていない前提なら `path:` 参照で利用できます。

## Brand の定義

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

`defbrand Name, spec` は親モジュール配下に `MyApp.Accounts.Types.Name` を生成します。

生成される主な API は次のとおりです。

- `new/1`: `{:ok, brand}` か `{:error, reason}` を返す
- `new!/1`: 失敗時に `ExBrand.Error` を送出する
- `unsafe_new/1`: 検証を通さず brand を作る
- `unwrap/1`: raw 値を取り出す
- `brand?/1`: その brand の値か判定する
- `gen/0`: `generator:` の値を返す
- `__base__/0`, `__name__/0`, `__meta__/0`: 反射用メタ情報を返す

`ExBrand.unwrap!/1` は任意の brand から raw 値を取り出します。`ExBrand.unwrap/1` は brand でなければそのまま返します。

## 利用例

```elixir
alias MyApp.Accounts.Types

{:ok, user_id} = Types.UserID.new(42)
Types.UserID.unwrap(user_id)
#=> 42

{:ok, email} = Types.Email.new("  USER@EXAMPLE.COM  ")
Types.Email.unwrap(email)
#=> "user@example.com"
```

brand は別モジュールとして生成されるため、`UserID` と `OrderID` がどちらも `:integer` ベースでも混同しにくくなります。

## Base 型

組み込み base は次の 3 つです。

- `:integer`
- `:string`
- `:binary`

加えて、`ExBrand.Base` の callback を実装した custom base module を使えます。

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

組み込み custom type として `ExBrand.Type.Email` も含まれています。

## Brand オプション

`defbrand` で指定できる主なオプションは次のとおりです。

- `validate:` 1 引数関数。`true` / `false` / `:ok` / `{:ok, normalized}` / `{:error, reason}` を返せる
- `error:` `validate:` が `false` を返したときのエラー理由
- `name:` 表示名。`Inspect` や例外メッセージに使われる
- `derive:` protocol か protocol のリスト
- `generator:` property-based testing 向けの任意値

`validate:` が `{:ok, normalized}` を返した場合、正規化済みの raw 値が brand 内部に保存されます。

## Ecto / JSON / Phoenix 連携

ExBrand は関連ライブラリがロードされているときだけ連携コードを生成します。

### Ecto

brand ごとに `ecto_type/0` と `ecto_parameterized_type/0` が生えます。

```elixir
schema "users" do
  field :user_id, MyApp.Accounts.Types.UserID.ecto_type()
  field :email, MyApp.Accounts.Types.Email.ecto_type()
end
```

`Ecto.Type.cast/2` が使える環境では、文字列から整数 brand への cast も Ecto 側の変換に委譲されます。

### JSON

`Jason` または `JSON` があれば、brand は raw 値として encode されます。

### Phoenix

`Phoenix.Param` と `Phoenix.HTML.Safe` があれば、brand 自体ではなく raw 値側の protocol 実装へ委譲されます。

## Schema DSL

`ExBrand.Schema` は API 入力や外部 payload の検証に使えます。

```elixir
defmodule MyApp.Accounts.UserInput do
  use ExBrand.Schema

  field :user_id, MyApp.Accounts.Types.UserID
  field :email, {MyApp.Accounts.Types.Email, field: "contactEmail"}
  field :age, {:integer, minimum: 18, error: :too_young}
  field :tags, {[{:string, min_length: 2}], min_items: 1, unique_items: true}
  field :published_at, {:string, format: :datetime}
end
```

```elixir
MyApp.Accounts.UserInput.validate(%{
  "contactEmail" => "user@example.com",
  user_id: 1,
  age: 20,
  tags: ["elixir"],
  published_at: "2026-04-02T12:34:56Z"
})
```

戻り値は `{:ok, normalized_map}` か `{:error, errors}` です。brand フィールドは brand 値に正規化され、`field:` を使った入力キーの別名も処理されます。

## Runtime 設定

schema の実行時挙動は `ExBrand.Schema.set_runtime_config!/1` で切り替えられます。

```elixir
ExBrand.Schema.set_runtime_config!(fail_fast: true)
ExBrand.Schema.set_runtime_config!(deferred_checks: [:enum, :format])
```

- `fail_fast: true`: map/list 検証で最初のエラーで停止する
- `deferred_checks:`: `:enum`, `:format`, `:regex`, `:unique_items`, `:deep_nested` を遅延できる

## 署名検証

`config :ex_brand, :signature_verification, true` を有効にすると、brand struct に署名を持たせて forged value や mutation を検出できます。`unwrap/1`、`brand?/1`、Phoenix/Ecto 連携もこの検証を尊重します。

既定値は `false` です。

## サンプルアプリ

`examples/customer_portal` に Phoenix/Ecto 連携の最小サンプルがあります。brand を schema、changeset、JSON レスポンスでどう扱うかを確認できます。

詳細は [examples/customer_portal/README.md](/Users/naoya/src/exbrand/examples/customer_portal/README.md) を参照してください。

## 開発

代表的なコマンドは次のとおりです。

```bash
mix test
mix credo
mix dialyzer
```

追加ドキュメント:

- [docs/getting-started.md](/Users/naoya/src/exbrand/docs/getting-started.md)
- [docs/api-guide.md](/Users/naoya/src/exbrand/docs/api-guide.md)
