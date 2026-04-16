# ExBrand

ExBrand is a DSL for giving semantic boundaries to primitive Elixir values. Instead of passing around plain `integer()` or `String.t()` values, you can generate dedicated types such as `UserID` or `Email` and apply validation and normalization when those values are constructed.

This repository provides two core features:

- `ExBrand`: a DSL for defining brand types
- `ExBrand.Schema`: a declarative schema DSL for validating map/list payloads such as API input

Japanese documentation is also available:

- [README_ja.md](/Users/naoya/src/exbrand/README_ja.md)
- [docs/getting-started_ja.md](/Users/naoya/src/exbrand/docs/getting-started_ja.md)
- [docs/api-guide_ja.md](/Users/naoya/src/exbrand/docs/api-guide_ja.md)

## What It Does

- Generate distinct brand types with `defbrand`
- Safely construct branded values with `new/1` and `new!/1`
- Add custom validation and normalization with `validate:`
- Attach `generator:` and `derive:` metadata to brand definitions
- Auto-generate `Ecto.Type` and `Ecto.ParameterizedType`
- Conditionally implement `Jason.Encoder`, `JSON.Encoder`, `Phoenix.Param`, and `Phoenix.HTML.Safe`
- Validate nested map/list payloads with `ExBrand.Schema` and return normalized values including brands

## Installation

Add the dependency to `mix.exs`.

```elixir
defp deps do
  [
    {:ex_brand, path: "../ex_brand"}
  ]
end
```

If you are using this repository locally, `path:` is the expected integration style.

## Defining Brands

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

`defbrand Name, spec` generates `MyApp.Accounts.Types.Name` under the parent module.

Each generated brand module exposes these main APIs:

- `new/1`: returns `{:ok, brand}` or `{:error, reason}`
- `new!/1`: raises `ExBrand.Error` on failure
- `unsafe_new/1`: builds a brand without validation
- `unwrap/1`: extracts the raw value
- `brand?/1`: checks whether a value belongs to the brand
- `gen/0`: returns the configured `generator:` value
- `__base__/0`, `__name__/0`, `__meta__/0`: reflection helpers

`ExBrand.unwrap!/1` extracts the raw value from any ExBrand value. `ExBrand.unwrap/1` unwraps brands and passes through non-brand values unchanged.

## Example Usage

```elixir
alias MyApp.Accounts.Types

{:ok, user_id} = Types.UserID.new(42)
Types.UserID.unwrap(user_id)
#=> 42

{:ok, email} = Types.Email.new("  USER@EXAMPLE.COM  ")
Types.Email.unwrap(email)
#=> "user@example.com"
```

Because brands are distinct modules, `UserID` and `OrderID` remain separate even if both are backed by `:integer`.

## Base Types

Built-in base types are:

- `:integer`
- `:string`
- `:binary`

You can also use a custom base module that implements `ExBrand.Base`.

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

The repository also includes `ExBrand.Type.Email` as a built-in custom base.

## Brand Options

The main options supported by `defbrand` are:

- `validate:` a unary function returning `true`, `false`, `:ok`, `{:ok, normalized}`, or `{:error, reason}`
- `error:` the error reason used when `validate:` returns `false`
- `name:` a display name used by `Inspect` and exceptions
- `derive:` a protocol or list of protocols
- `generator:` arbitrary generator metadata for property-based testing

If `validate:` returns `{:ok, normalized}`, the normalized raw value is stored inside the brand.

## Ecto / JSON / Phoenix Integration

ExBrand only generates integration code when the relevant library is loaded.

### Ecto

Each brand gets `ecto_type/0` and `ecto_parameterized_type/0`.

```elixir
schema "users" do
  field :user_id, MyApp.Accounts.Types.UserID.ecto_type()
  field :email, MyApp.Accounts.Types.Email.ecto_type()
end
```

If `Ecto.Type.cast/2` is available, string-to-integer conversion is delegated to Ecto before branding.

### JSON

If `Jason` or `JSON` is available, brands are encoded as their raw values.

### Phoenix

If `Phoenix.Param` and `Phoenix.HTML.Safe` are available, ExBrand delegates to the raw value's protocol implementation instead of exposing the brand struct.

## Schema DSL

`ExBrand.Schema` is intended for validating API input and other external payloads.

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

The return value is `{:ok, normalized_map}` or `{:error, errors}`. Brand fields are normalized into brand values, and aliased input keys are handled through `field:`.

## Runtime Configuration

Schema runtime behavior can be changed with `ExBrand.Schema.set_runtime_config!/1`.

```elixir
ExBrand.Schema.set_runtime_config!(fail_fast: true)
ExBrand.Schema.set_runtime_config!(deferred_checks: [:enum, :format])
```

- `fail_fast: true`: stop at the first map/list validation error
- `deferred_checks:`: defer `:enum`, `:format`, `:regex`, `:unique_items`, and `:deep_nested`

## Signature Verification

Enable `config :ex_brand, :signature_verification, true` if you need forged or mutated brand structs to be detected. `unwrap/1`, `brand?/1`, and the Phoenix/Ecto integrations all respect this validation.

The default is `false`.

## Example App

`examples/customer_portal` contains a minimal Phoenix/Ecto example showing how brands move through schemas, changesets, and JSON responses.

See [examples/customer_portal/README.md](/Users/naoya/src/exbrand/examples/customer_portal/README.md) for details, or [examples/customer_portal/README_ja.md](/Users/naoya/src/exbrand/examples/customer_portal/README_ja.md) for Japanese.

## Development

Common commands:

```bash
mix test
mix credo
mix dialyzer
```

Related documentation:

- [docs/getting-started.md](/Users/naoya/src/exbrand/docs/getting-started.md)
- [docs/api-guide.md](/Users/naoya/src/exbrand/docs/api-guide.md)
