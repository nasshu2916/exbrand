# API Guide

This document summarizes the public ExBrand API and the supported `ExBrand.Schema` constraints based on the current implementation.

Japanese version: [api-guide_ja.md](/Users/naoya/src/exbrand/docs/api-guide_ja.md)

## `ExBrand`

### `use ExBrand`

Introduces the brand DSL. It does not accept options.

```elixir
defmodule MyApp.Accounts.Types do
  use ExBrand
end
```

### `defbrand name, spec`

Generates a brand module under the parent module.

```elixir
defbrand UserID, :integer
defbrand Email, {:string, name: "Email Address"}
defbrand UserToken, {MyApp.Types.PrefixedString, prefix: "usr_"}
```

`spec` can be one of:

- `:integer`
- `:string`
- `:binary`
- `custom_base_module`
- `{base, opts}`

### Brand Options

Brand-specific options are:

- `validate: (term() -> term())`
- `error: term()`
- `derive: protocol | [protocol]`
- `generator: term() | (() -> term())`
- `name: String.t() | atom()`

Custom base options and brand options can coexist in the same keyword list. ExBrand splits out `validate:` and the other brand-level keys internally.

```elixir
defbrand UserToken,
         {MyApp.Types.PrefixedString,
          prefix: "usr_",
          ecto_type: :string,
          name: "User Token"}
```

### Generated Brand API

Each brand module exposes:

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

Constructs a branded value from a raw value.

```elixir
Types.UserID.new(1)
#=> {:ok, %Types.UserID{}}
```

Return values:

- `{:ok, brand}`
- `{:error, reason}`

#### `new!/1`

Bang version of `new/1`. Raises `ExBrand.Error` on failure.

#### `unsafe_new/1`

Constructs a brand without base validation or custom validation. This is intended for trusted internal boundaries only.

#### `unwrap/1`

Extracts the raw value. If signature verification is enabled, forged or mutated values are rejected.

#### `brand?/1`

Checks whether the value belongs to that exact brand module.

#### `gen/0`

Returns the configured `generator:` value. If `generator:` is a zero-arity function, it is evaluated when `gen/0` is called.

#### `__meta__/0`

Returns reflection metadata for the brand definition.

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

Extracts the raw value from any ExBrand value. Raises `ArgumentError` for non-brand values.

### `ExBrand.unwrap/1`

Returns the raw value for brands and passes non-brand values through unchanged.

## `ExBrand.Base`

A custom base module must implement:

```elixir
@callback type_ast(keyword()) :: Macro.t()
@callback validate(term(), keyword()) :: :ok | {:error, term()}
@callback ecto_type(keyword()) :: term()
```

Responsibilities:

- `type_ast/1`: produces the brand `raw()` type
- `validate/2`: validates whether a raw value matches the base
- `ecto_type/1`: returns the Ecto type used for integration

## `ExBrand.Type.Email`

Built-in custom base for email strings. Its raw type is `String.t()`, its Ecto type is `:string`, and invalid values return `{:error, :invalid_email}`.

## `ExBrand.Schema`

### `use ExBrand.Schema`

Introduces the schema DSL. It does not accept options.

### `field/2`

Defines one schema field.

```elixir
field :user_id, Types.UserID
field :email, {Types.Email, field: "contactEmail"}
field :age, {:integer, minimum: 18}
field :tags, {[{:string, min_length: 2}], min_items: 1}
field :address, %{city: :string, zip: {:string, min_length: 5, max_length: 5}}
```

### Supported Schema Shapes

`ExBrand.Schema` supports:

- scalar base: `:any | :boolean | :integer | :number | :null | :string | :binary`
- brand module
- nested schema module
- `{schema, opts}`
- `[item_schema]`
- `%{field_name => schema}`

List schemas must be single-element lists. A list such as `[:integer, :string]` is invalid.

### Field Options

Available options depend on the schema shape.

#### Common

- `enum: list()`
- `error: term()`
- `field: atom() | String.t()`
- `nullable: boolean()`
- `validate: (term() -> term())`

#### Numeric

- `minimum: number()`
- `maximum: number()`

#### String / binary

- `min_length: non_neg_integer()`
- `max_length: non_neg_integer()`
- `format: :email | :datetime`

#### List

- `min_items: non_neg_integer()`
- `max_items: non_neg_integer()`
- `unique_items: boolean()`

Unsupported constraints on map schemas or nested schema modules fail at compile time.

### `validate/1`

Generated for every module that uses `ExBrand.Schema`.

```elixir
MySchema.validate(params)
```

Return values:

- `{:ok, normalized_value}`
- `{:error, errors}`

For map schemas, `errors` is keyed by field name. For list schemas, it is keyed by item index. List-level errors are stored in `:__self__`, and unknown map fields are stored in `:__extra_fields__`.

### `validate!/1`

Raises `ArgumentError` on validation failure.

### `valid?/1`

Returns a boolean indicating whether `validate/1` succeeds.

### `__schema__/0`

Returns the original schema definition.

### `__compiled_schema__/0`

Returns the compiled schema.

### `ExBrand.Schema.compile!/1`

Compiles an inline schema for runtime use.

```elixir
schema = ExBrand.Schema.compile!({%{name: :string, age: {:integer, minimum: 18}}, []})
ExBrand.Schema.validate(%{name: "naoya", age: 20}, schema)
```

### `ExBrand.Schema.validate/2`

Validates against a schema compiled with `compile!/1`. Passing an uncompiled schema raises `ArgumentError`.

### `ExBrand.Schema.set_runtime_config!/1`

Updates runtime configuration.

```elixir
ExBrand.Schema.set_runtime_config!(fail_fast: true)
ExBrand.Schema.set_runtime_config!(deferred_checks: [:enum, :format])
ExBrand.Schema.set_runtime_config!(fail_fast: :unset)
ExBrand.Schema.set_runtime_config!(deferred_checks: :unset)
```

Supported options:

- `fail_fast: true | false | :unset`
- `deferred_checks: list() | :unset`

Allowed deferred checks:

- `:enum`
- `:format`
- `:regex`
- `:unique_items`
- `:deep_nested`

In the current implementation, confirmed runtime effects exist for `:enum`, `:format`, and `:unique_items`.

## Integration APIs

### Ecto

Brand modules expose:

- `ecto_type/0`
- `ecto_parameterized_type/0`

These are only usable when `Ecto` / `Ecto.ParameterizedType` are loaded.

### JSON

If `Jason.Encoder` or `JSON.Encoder` exists, brands are encoded as raw values.

### Phoenix

If `Phoenix.Param` and `Phoenix.HTML.Safe` exist, ExBrand delegates to the raw value's protocol implementations.

## Exceptions

### `ExBrand.Error`

Raised by `new!/1`. Main fields:

- `:reason`
- `:module`
- `:value`
- `:message`

If a brand defines `name:`, that display name is also used in the exception message.
