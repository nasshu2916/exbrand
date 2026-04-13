# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule ExBrand.Adapter.EctoTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.Fixtures.Brands.PrefixedUserID
  alias ExBrand.TestSupport.Fixtures.Types

  test "ecto adapter exposes type helpers on the brand module" do
    assert Types.UserID.ecto_type() == Types.UserID.EctoType
    assert Types.UserID.ecto_parameterized_type() == {Types.UserID.EctoParameterizedType, []}
  end

  test "ecto type adapter casts raw values into brands" do
    assert {:ok, user_id} = Types.UserID.EctoType.cast(1)
    assert Types.UserID.unwrap(user_id) == 1

    if ecto_type_available?() do
      assert {:ok, user_id_from_string} = Types.UserID.EctoType.cast("1")
      assert Types.UserID.unwrap(user_id_from_string) == 1
    else
      assert Types.UserID.EctoType.cast("1") == :error
    end
  end

  test "ecto type adapter loads raw values into brands" do
    assert {:ok, user_id} = Types.UserID.EctoType.load(1)
    assert Types.UserID.unwrap(user_id) == 1
    assert Types.UserID.EctoType.load("1") == :error
    assert Types.UserID.EctoType.load(Types.UserID.new!(1)) == :error
  end

  test "ecto type adapter dumps brands and raw values into raw values" do
    user_id = Types.UserID.new!(1)

    assert Types.UserID.EctoType.dump(user_id) == {:ok, 1}
    assert Types.UserID.EctoType.dump(1) == {:ok, 1}
    assert Types.UserID.EctoType.dump("1") == :error
  end

  test "ecto type adapter delegates type and equality" do
    assert Types.UserID.EctoType.type() == :integer
    assert Types.Email.EctoType.type() == :string
    assert PrefixedUserID.EctoType.type() == :string
    assert Types.UserID.EctoType.equal?(1, Types.UserID.new!(1))
    refute Types.UserID.EctoType.equal?(1, 2)
    assert Types.UserID.EctoType.equal?(1, "1") == ecto_type_available?()
  end

  test "ecto parameterized type adapter casts and reports base type" do
    assert Types.UserID.EctoParameterizedType.init([]) == []
    assert Types.UserID.EctoParameterizedType.type([]) == :integer
    assert {:ok, user_id} = Types.UserID.EctoParameterizedType.cast(1, [])
    assert Types.UserID.unwrap(user_id) == 1

    if ecto_type_available?() do
      assert {:ok, user_id_from_string} = Types.UserID.EctoParameterizedType.cast("1", [])
      assert Types.UserID.unwrap(user_id_from_string) == 1
    else
      assert Types.UserID.EctoParameterizedType.cast("1", []) == :error
    end
  end

  test "ecto parameterized type adapter loads and dumps through callbacks" do
    loader = fn value -> {:ok, value} end
    dumper = fn value -> {:ok, value} end

    assert {:ok, user_id} = Types.UserID.EctoParameterizedType.load(1, loader, [])
    assert Types.UserID.unwrap(user_id) == 1
    assert Types.UserID.EctoParameterizedType.dump(user_id, dumper, []) == {:ok, 1}
    assert Types.UserID.EctoParameterizedType.dump(1, dumper, []) == {:ok, 1}
    assert Types.UserID.EctoParameterizedType.load("1", loader, []) == :error
    assert Types.UserID.EctoParameterizedType.load(Types.UserID.new!(1), loader, []) == :error
  end

  test "ecto parameterized type adapter delegates equality" do
    assert Types.UserID.EctoParameterizedType.equal?(1, Types.UserID.new!(1), [])
    refute Types.UserID.EctoParameterizedType.equal?(1, 2, [])
  end

  test "ecto adapter respects custom base configuration" do
    assert PrefixedUserID.EctoParameterizedType.type([]) == :string
    assert {:ok, user_id} = PrefixedUserID.EctoType.cast("usr_1")
    assert PrefixedUserID.unwrap(user_id) == "usr_1"
    assert PrefixedUserID.EctoType.cast("1") == :error
  end

  defp ecto_type_available? do
    Code.ensure_loaded?(Ecto.Type) and function_exported?(Ecto.Type, :cast, 2)
  end
end
