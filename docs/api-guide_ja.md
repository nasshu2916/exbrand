# API Guide

このドキュメントは ExBrand の公開 API と、`ExBrand.Schema` の制約を仕様ベースで整理したものです。

英語版: [api-guide.md](/Users/naoya/src/exbrand/docs/api-guide.md)

## `ExBrand`

### `use ExBrand`

brand DSL を導入します。オプションは受け付けません。

```elixir
defmodule MyApp.Accounts.Types do
  use ExBrand
end
```

### `defbrand name, spec`

親モジュール配下に brand モジュールを生成します。

```elixir
defbrand UserID, :integer
defbrand Email, {:string, name: "Email Address"}
defbrand UserToken, {MyApp.Types.PrefixedString, prefix: "usr_"}
```

`spec` は次のどれかです。

- `:integer`
- `:string`
- `:binary`
- `custom_base_module`
- `{base, opts}`

### Brand オプション

`opts` に含められる brand 向けオプションは次のとおりです。

- `validate: (term() -> term())`
- `error: term()`
- `derive: protocol | [protocol]`
- `generator: term() | (() -> term())`
- `name: String.t() | atom()`

base module 側に渡すオプションと brand オプションは同じ keyword に書けます。ExBrand 側が `validate:` などの brand オプションを切り分けます。

```elixir
defbrand UserToken,
         {MyApp.Types.PrefixedString,
          prefix: "usr_",
          ecto_type: :string,
          name: "User Token"}
```

### 生成される brand API

各 brand モジュールには次の API が生成されます。

- `new/1`
- `new!/1`
- `unsafe_new/1`
- `unwrap/1`
- `brand?/1`
- `gen/0`
- `__base__/0`
- `__name__/0`
- `__meta__/0`

#### `new/1`

raw 値を brand 化します。

```elixir
Types.UserID.new(1)
#=> {:ok, %Types.UserID{}}
```

戻り値:

- `{:ok, brand}`
- `{:error, reason}`

#### `new!/1`

`new/1` の bang 版です。失敗時は `ExBrand.Error` を送出します。

#### `unsafe_new/1`

base 検証も custom validator も通さずに brand を生成します。高信頼な内部境界でのみ使う前提です。

#### `unwrap/1`

brand から raw 値を取り出します。署名検証が有効な場合は forged value や mutation を検出します。

#### `brand?/1`

その brand モジュールが生成した値かを判定します。

#### `gen/0`

`generator:` に入れた値を返します。0 引数関数を渡していた場合は、このタイミングで評価されます。

#### `__meta__/0`

brand 定義の反射情報を返します。

```elixir
%{
  module: Types.UserID,
  name: "UserID",
  base: :integer,
  validator: nil,
  generator: nil,
  error: nil
}
```

### `ExBrand.unwrap!/1`

任意の ExBrand 値から raw 値を取り出します。brand 以外を渡すと `ArgumentError` を送出します。

### `ExBrand.unwrap/1`

brand なら raw 値を返し、brand でなければ入力をそのまま返します。

## `ExBrand.Base`

custom base module は次の callback を実装します。

```elixir
@callback type_ast(keyword()) :: Macro.t()
@callback validate(term(), keyword()) :: :ok | {:error, term()}
@callback ecto_type(keyword()) :: term()
```

役割は次のとおりです。

- `type_ast/1`: brand の `raw()` 型を生成する
- `validate/2`: raw 値がその base に適合するか判定する
- `ecto_type/1`: Ecto 連携時の型を返す

## `ExBrand.Type.Email`

組み込み custom base です。raw 値は `String.t()`、Ecto 型は `:string`、不正な email には `{:error, :invalid_email}` を返します。

## `ExBrand.Schema`

### `use ExBrand.Schema`

schema DSL を導入します。オプションは受け付けません。

### `field/2`

1 フィールド分の schema を定義します。

```elixir
field :user_id, Types.UserID
field :email, {Types.Email, field: "contactEmail"}
field :age, {:integer, minimum: 18}
field :tags, {[{:string, min_length: 2}], min_items: 1}
field :address, %{city: :string, zip: {:string, min_length: 5, max_length: 5}}
```

### Schema の形

`ExBrand.Schema` が扱う schema は次のいずれかです。

- scalar base: `:any | :boolean | :integer | :number | :null | :string | :binary`
- brand module
- nested schema module
- `{schema, opts}`
- `[item_schema]`
- `%{field_name => schema}`

list schema は必ず 1 要素のリストで表現します。`[:integer, :string]` のような複数要素 list は無効です。

### フィールドオプション

利用できるオプションは schema の種類で異なります。

#### 共通

- `enum: list()`
- `error: term()`
- `field: atom() | String.t()`
- `nullable: boolean()`
- `validate: (term() -> term())`

#### 数値

- `minimum: number()`
- `maximum: number()`

#### 文字列 / binary

- `min_length: non_neg_integer()`
- `max_length: non_neg_integer()`
- `format: :email | :datetime`

#### list

- `min_items: non_neg_integer()`
- `max_items: non_neg_integer()`
- `unique_items: boolean()`

map schema や nested schema module に `minimum:` のような不適切な制約を付けると compile time で失敗します。

### `validate/1`

`use ExBrand.Schema` したモジュールごとに生成されます。

```elixir
MySchema.validate(params)
```

戻り値:

- `{:ok, normalized_value}`
- `{:error, errors}`

`errors` は map schema ならフィールド単位、list schema なら index 単位で返ります。list 自体の制約違反は `:__self__`、未定義フィールドは `:__extra_fields__` に入ります。

### `validate!/1`

失敗時に `ArgumentError` を送出します。

### `valid?/1`

`validate/1` の成否を boolean で返します。

### `__schema__/0`

元の schema 定義を返します。

### `__compiled_schema__/0`

コンパイル済み schema を返します。

### `ExBrand.Schema.compile!/1`

inline schema を実行時にコンパイルしたいときに使います。

```elixir
schema = ExBrand.Schema.compile!({%{name: :string, age: {:integer, minimum: 18}}, []})
ExBrand.Schema.validate(%{name: "naoya", age: 20}, schema)
```

### `ExBrand.Schema.validate/2`

`compile!/1` した schema を検証します。未コンパイルの schema を渡すと `ArgumentError` になります。

### `ExBrand.Schema.set_runtime_config!/1`

実行時設定を更新します。

```elixir
ExBrand.Schema.set_runtime_config!(fail_fast: true)
ExBrand.Schema.set_runtime_config!(deferred_checks: [:enum, :format])
ExBrand.Schema.set_runtime_config!(fail_fast: :unset)
ExBrand.Schema.set_runtime_config!(deferred_checks: :unset)
```

指定できるオプション:

- `fail_fast: true | false | :unset`
- `deferred_checks: list() | :unset`

許可される deferred check:

- `:enum`
- `:format`
- `:regex`
- `:unique_items`
- `:deep_nested`

現在の実装で実際に効果が確認できるのは `:enum`, `:format`, `:unique_items` です。

## 連携 API

### Ecto

brand モジュールに次が生成されます。

- `ecto_type/0`
- `ecto_parameterized_type/0`

どちらも `Ecto` / `Ecto.ParameterizedType` がロードされている場合のみ使えます。

### JSON

`Jason.Encoder` と `JSON.Encoder` が存在すれば、brand は raw 値として encode されます。

### Phoenix

`Phoenix.Param` と `Phoenix.HTML.Safe` が存在すれば、raw 値側の protocol 実装に委譲します。

## 例外

### `ExBrand.Error`

`new!/1` が失敗したときに送出されます。主なフィールドは次のとおりです。

- `:reason`
- `:module`
- `:value`
- `:message`

`name:` を指定した brand では、例外メッセージにもその表示名が使われます。
