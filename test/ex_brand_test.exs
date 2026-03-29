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

defmodule ExBrandTest do
  use ExUnit.Case, async: true

  defprotocol Serializable do
    @fallback_to_any true
    def serialize(term)
  end

  defimpl Serializable, for: Any do
    def serialize(value), do: {:raw, value}

    defmacro __deriving__(module, _struct, options) do
      tag = Keyword.get(options, :tag, :derived)

      quote do
        defimpl ExBrandTest.Serializable, for: unquote(module) do
          def serialize(value) do
            {unquote(tag), unquote(module).unwrap(value)}
          end
        end
      end
    end
  end

  defmodule Types do
    use ExBrand

    defbrand UserID, :integer
    defbrand OrderID, :integer

    defbrand Email, :string,
      validate: &String.contains?(&1, "@"),
      error: :invalid_email

    defbrands do
      brand AccessToken, :binary

      brand PositiveUserID, :integer do
        validate(&(&1 > 0))
        error(:must_be_positive)
      end
    end
  end

  defmodule AliasedTypes do
    use ExBrand, aliases: [UserID, OrderID]

    defbrand UserID, :integer
    defbrand OrderID, :integer

    def user_id_base, do: UserID.__base__()
    def order_id_base, do: OrderID.__base__()
  end

  defmodule SelectivelyAliasedTypes do
    use ExBrand, aliases: [UserID]

    defbrand UserID, :integer
    defbrand OrderID, :integer

    def user_id_base, do: UserID.__base__()
  end

  defmodule StandaloneUserID do
    use ExBrand, base: :integer
  end

  defmodule StandaloneEmail do
    use ExBrand,
      base: :string,
      validate: &String.contains?(&1, "@"),
      error: :invalid_email
  end

  defmodule NormalizedEmail do
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

  defmodule DerivedUserID do
    use ExBrand,
      base: :integer,
      derive: [{Serializable, tag: :user_id}]
  end

  test "integer brands are distinct modules" do
    {:ok, user_id} = Types.UserID.new(1)
    {:ok, order_id} = Types.OrderID.new(1)

    assert Types.UserID.is_brand?(user_id)
    refute Types.UserID.is_brand?(order_id)
  end

  test "unwrap returns raw value" do
    user_id = Types.UserID.new!(1)

    assert Types.UserID.unwrap(user_id) == 1
  end

  test "validate option rejects invalid value" do
    assert Types.Email.new("user@example.com") |> elem(0) == :ok
    assert Types.Email.new("invalid") == {:error, :invalid_email}
  end

  test "block DSL is supported" do
    assert Types.PositiveUserID.new(10) |> elem(0) == :ok
    assert Types.PositiveUserID.new(0) == {:error, :must_be_positive}
  end

  test "invalid type is rejected" do
    assert Types.UserID.new("1") == {:error, :invalid_type}
  end

  test "new! raises custom exception" do
    assert_raise ExBrand.Error, fn ->
      Types.PositiveUserID.new!(0)
    end
  end

  test "inspect hides internal field names" do
    user_id = Types.UserID.new!(1)

    assert inspect(user_id) == "#UserID<1>"
    refute inspect(user_id) =~ "__value__"
  end

  test "string chars converts brand value to string" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert to_string(user_id) == "42"
    assert to_string(email) == "user@example.com"
  end

  test "jason encoder delegates to the raw value encoder" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    if Code.ensure_loaded?(Jason) do
      assert Jason.encode!(user_id) == Jason.encode!(42)
      assert Jason.encode!(email) == Jason.encode!("user@example.com")
    else
      assert Jason.Encoder.encode(user_id, []) == Jason.Encoder.encode(42, [])
      assert Jason.Encoder.encode(email, []) == Jason.Encoder.encode("user@example.com", [])
    end
  end

  test "json encoder delegates to the raw value encoder" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert JSON.encode!(user_id) == JSON.encode!(42)
    assert JSON.encode!(email) == JSON.encode!("user@example.com")
  end

  test "phoenix param delegates to the raw value protocol" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert Phoenix.Param.to_param(user_id) == "id-42"
    assert Phoenix.Param.to_param(email) == "param-user@example.com"
  end

  test "low-level API defines standalone brand module" do
    user_id = StandaloneUserID.new!(1)

    assert StandaloneUserID.unwrap(user_id) == 1
    assert StandaloneUserID.__base__() == :integer
    assert inspect(user_id) == "#StandaloneUserID<1>"
  end

  test "low-level API supports validation options" do
    assert StandaloneEmail.new("user@example.com") |> elem(0) == :ok
    assert StandaloneEmail.new("invalid") == {:error, :invalid_email}
  end

  test "defbrands rejects duplicate brand names" do
    assert_raise ArgumentError, ~r/duplicate brand definitions in defbrands: UserID/, fn ->
      Code.compile_string("""
      defmodule DuplicateBrands do
        use ExBrand

        defbrands do
          brand UserID, :integer
          brand UserID, :binary
        end
      end
      """)
    end
  end

  test "validator can normalize raw value before branding" do
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert NormalizedEmail.unwrap(email) == "user@example.com"
    assert inspect(email) == "#NormalizedEmail<\"user@example.com\">"
  end

  test "derive applies protocol implementations with options" do
    user_id = DerivedUserID.new!(42)

    assert Serializable.serialize(user_id) == {:user_id, 42}
  end

  test "derive option rejects unsupported shapes" do
    assert_raise ArgumentError,
                 ~r/derive must be a protocol or list of protocols/,
                 fn ->
                   Code.compile_string("""
                   defmodule InvalidDerivedBrand do
                     use ExBrand,
                       base: :integer,
                       derive: "Serializable"
                   end
                   """)
                 end
  end

  test "aliases list generates helper aliases in the parent module" do
    assert AliasedTypes.user_id_base() == :integer
    assert AliasedTypes.order_id_base() == :integer
  end

  test "aliases can be limited to selected brand names" do
    assert SelectivelyAliasedTypes.user_id_base() == :integer
  end

  test "selected aliases do not expose non-listed brand names" do
    modules =
      Code.compile_string("""
      defmodule InvalidAliasSelection do
        use ExBrand, aliases: [UserID]

        defbrand UserID, :integer
        defbrand OrderID, :integer

        def order_id_base, do: OrderID.__base__()
      end
      """)

    {module, _bytecode} =
      Enum.find(modules, fn {compiled_module, _bytecode} ->
        compiled_module == InvalidAliasSelection
      end)

    assert_raise UndefinedFunctionError, fn ->
      module.order_id_base()
    end
  end

  test "aliases option rejects unsupported shapes" do
    assert_raise ArgumentError,
                 ~r/aliases must be false or a list of brand names/,
                 fn ->
                   Code.compile_string("""
                   defmodule InvalidAliasesOption do
                     use ExBrand, aliases: true
                   end
                   """)
                 end
  end
end
