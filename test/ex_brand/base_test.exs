defmodule ExBrand.BaseTest do
  use ExUnit.Case, async: true

  alias ExBrand.Base
  alias ExBrand.TestSupport.CustomBases.PrefixedString

  defmodule MissingCallbacksBase do
    def validate(_value, _opts), do: :ok
  end

  test "normalize! accepts built-in and custom base definitions" do
    assert Base.normalize!(:integer) == :integer
    assert Base.normalize!(:binary) == :binary
    assert Base.normalize!(:string) == :string
    assert Base.normalize!(PrefixedString) == PrefixedString

    assert Base.normalize!({PrefixedString, prefix: "usr_"}) ==
             {PrefixedString, prefix: "usr_"}
  end

  test "normalize! rejects unsupported base definitions" do
    assert_raise ArgumentError, ~r/unsupported base type: 123/, fn ->
      Base.normalize!(123)
    end

    assert_raise ArgumentError, ~r/custom base options must be a keyword list/, fn ->
      Base.normalize!({PrefixedString, ["usr_"]})
    end

    assert_raise ArgumentError,
                 ~r/custom base module UnknownCustomBase could not be loaded/,
                 fn ->
                   Base.normalize!(UnknownCustomBase)
                 end

    assert_raise ArgumentError,
                 ~r/custom base module .*MissingCallbacksBase must export type_ast\/1/,
                 fn ->
                   Base.normalize!(MissingCallbacksBase)
                 end
  end

  test "type_ast! returns AST for built-in and custom bases" do
    assert Macro.to_string(Base.type_ast!(:integer)) == "integer()"
    assert Macro.to_string(Base.type_ast!(:binary)) == "binary()"
    assert Macro.to_string(Base.type_ast!(:string)) == "String.t()"
    assert Macro.to_string(Base.type_ast!(PrefixedString)) == "String.t()"
  end

  test "validate/2 validates built-in and custom bases" do
    assert Base.validate(1, :integer) == :ok
    assert Base.validate("abc", :binary) == :ok
    assert Base.validate("abc", :string) == :ok

    assert Base.validate("1", :integer) == {:error, :invalid_type}
    assert Base.validate(1, :binary) == {:error, :invalid_type}
    assert Base.validate(1, :string) == {:error, :invalid_type}

    assert Base.validate("usr_123", {PrefixedString, prefix: "usr_"}) == :ok
    assert Base.validate("abc", {PrefixedString, prefix: "usr_"}) == {:error, :invalid_type}
  end

  test "ecto_type!/1 returns configured ecto types" do
    assert Base.ecto_type!(:integer) == :integer
    assert Base.ecto_type!(:binary) == :binary
    assert Base.ecto_type!(:string) == :string
    assert Base.ecto_type!(PrefixedString) == :string

    assert Base.ecto_type!({PrefixedString, prefix: "usr_", ecto_type: :binary_id}) ==
             :binary_id
  end
end
