unless Code.ensure_loaded?(Jason.Encoder) do
  defprotocol Jason.Encoder do
    @fallback_to_any true
    def encode(value, opts)
  end

  defimpl Jason.Encoder, for: Integer do
    def encode(value, _opts), do: "int:#{value}"
  end

  defimpl Jason.Encoder, for: BitString do
    def encode(value, _opts), do: "str:#{value}"
  end

  defimpl Jason.Encoder, for: Any do
    def encode(value, _opts), do: "raw:#{inspect(value)}"
  end
end

unless Code.ensure_loaded?(Phoenix.Param) do
  defprotocol Phoenix.Param do
    @fallback_to_any true
    def to_param(value)
  end

  defimpl Phoenix.Param, for: Integer do
    def to_param(value), do: "id-#{value}"
  end

  defimpl Phoenix.Param, for: BitString do
    def to_param(value), do: "param-#{value}"
  end

  defimpl Phoenix.Param, for: Any do
    def to_param(value), do: "raw-#{inspect(value)}"
  end
end

unless Code.ensure_loaded?(Phoenix.HTML.Safe) do
  defprotocol Phoenix.HTML.Safe do
    @fallback_to_any true
    def to_iodata(value)
  end

  defimpl Phoenix.HTML.Safe, for: Integer do
    def to_iodata(value), do: ["safe-int:", Integer.to_string(value)]
  end

  defimpl Phoenix.HTML.Safe, for: BitString do
    def to_iodata(value), do: ["safe-str:", value]
  end

  defimpl Phoenix.HTML.Safe, for: Any do
    def to_iodata(value), do: ["safe-raw:", inspect(value)]
  end
end

unless Code.ensure_loaded?(Ecto.Type) do
  defmodule Ecto.Type do
    @callback type() :: term()
    @callback cast(term()) :: {:ok, term()} | :error
    @callback load(term()) :: {:ok, term()} | :error
    @callback dump(term()) :: {:ok, term()} | :error
    @callback embed_as(term()) :: term()
    @callback equal?(term(), term()) :: boolean()

    defmacro __using__(_opts) do
      quote do
        @behaviour Ecto.Type
      end
    end
  end
end

unless Code.ensure_loaded?(Ecto.ParameterizedType) do
  defmodule Ecto.ParameterizedType do
    @callback init(keyword()) :: term()
    @callback type(term()) :: term()
    @callback cast(term(), term()) :: {:ok, term()} | :error
    @callback load(term(), (term() -> {:ok, term()} | :error), term()) :: {:ok, term()} | :error
    @callback dump(term(), (term() -> {:ok, term()} | :error), term()) :: {:ok, term()} | :error
    @callback embed_as(term(), term()) :: term()
    @callback equal?(term(), term(), term()) :: boolean()

    defmacro __using__(_opts) do
      quote do
        @behaviour Ecto.ParameterizedType
      end
    end
  end
end

defprotocol ExBrand.TestSupport.Serializable do
  @fallback_to_any true
  def serialize(term)
end

defimpl ExBrand.TestSupport.Serializable, for: Any do
  def serialize(value), do: {:raw, value}

  defmacro __deriving__(module, _struct, options) do
    tag = Keyword.get(options, :tag, :derived)

    quote do
      defimpl ExBrand.TestSupport.Serializable, for: unquote(module) do
        def serialize(value) do
          {unquote(tag), unquote(module).unwrap(value)}
        end
      end
    end
  end
end

defmodule ExBrand.TestSupport.Fixtures.Types do
  use ExBrand

  defbrand UserID, :integer
  defbrand OrderID, :integer
  defbrand NamedUserID, :integer, name: "User ID"

  defbrand Email, :string,
    validate: &String.contains?(&1, "@"),
    error: :invalid_email

  defbrands do
    brand AccessToken, :binary

    brand GeneratedUserID, :integer do
      generator({:integer_generator, min: 1})
    end

    brand NamedAccessToken, :binary do
      name("Access Token")
    end

    brand PositiveUserID, :integer do
      validate(&(&1 > 0))
      error(:must_be_positive)
    end
  end
end

defmodule ExBrand.TestSupport.Fixtures.AliasedTypes do
  use ExBrand, aliases: [UserID, OrderID]

  defbrand UserID, :integer
  defbrand OrderID, :integer

  def user_id_base, do: UserID.__base__()
  def order_id_base, do: OrderID.__base__()
end

defmodule ExBrand.TestSupport.Fixtures.SelectivelyAliasedTypes do
  use ExBrand, aliases: [UserID]

  defbrand UserID, :integer
  defbrand OrderID, :integer

  def user_id_base, do: UserID.__base__()
end

defmodule ExBrand.TestSupport.Fixtures.StandaloneUserID do
  use ExBrand, base: :integer
end

defmodule ExBrand.TestSupport.Fixtures.StandaloneEmail do
  use ExBrand,
    base: :string,
    validate: &String.contains?(&1, "@"),
    error: :invalid_email
end

defmodule ExBrand.TestSupport.Fixtures.StandaloneGeneratedEmail do
  use ExBrand,
    base: :string,
    generator: fn -> {:email_generator, normalize: true} end
end

defmodule ExBrand.TestSupport.Fixtures.NormalizedEmail do
  use ExBrand,
    base: :string,
    validate: fn raw ->
      normalized = raw |> String.trim() |> String.downcase()

      if String.contains?(normalized, "@") do
        {:ok, normalized}
      else
        {:error, :invalid_email}
      end
    end
end

defmodule ExBrand.TestSupport.Fixtures.DerivedUserID do
  use ExBrand,
    base: :integer,
    derive: [{ExBrand.TestSupport.Serializable, tag: :user_id}]
end
