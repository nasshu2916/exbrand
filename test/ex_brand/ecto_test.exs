# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule ExBrand.EctoTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.Fixtures.Types

  test "brand exposes ecto type helpers" do
    assert Types.UserID.ecto_type() == Types.UserID.EctoType
    assert Types.UserID.ecto_parameterized_type() == {Types.UserID.EctoParameterizedType, []}
  end

  test "ecto type casts raw values into brands" do
    assert {:ok, user_id} = Types.UserID.EctoType.cast(1)
    assert Types.UserID.unwrap(user_id) == 1
    assert Types.UserID.EctoType.cast("1") == :error
  end

  test "ecto type loads raw values into brands" do
    assert {:ok, user_id} = Types.UserID.EctoType.load(1)
    assert Types.UserID.unwrap(user_id) == 1
    assert Types.UserID.EctoType.load("1") == :error
  end

  test "ecto type dumps brands and raw values into raw values" do
    user_id = Types.UserID.new!(1)

    assert Types.UserID.EctoType.dump(user_id) == {:ok, 1}
    assert Types.UserID.EctoType.dump(1) == {:ok, 1}
    assert Types.UserID.EctoType.dump("1") == :error
  end

  test "ecto type delegates type and equality" do
    assert Types.UserID.EctoType.type() == :integer
    assert Types.Email.EctoType.type() == :string
    assert Types.UserID.EctoType.equal?(1, Types.UserID.new!(1))
    refute Types.UserID.EctoType.equal?(1, 2)
    refute Types.UserID.EctoType.equal?(1, "1")
  end

  test "ecto parameterized type casts and reports base type" do
    assert Types.UserID.EctoParameterizedType.init([]) == []
    assert Types.UserID.EctoParameterizedType.type([]) == :integer
    assert {:ok, user_id} = Types.UserID.EctoParameterizedType.cast(1, [])
    assert Types.UserID.unwrap(user_id) == 1
    assert Types.UserID.EctoParameterizedType.cast("1", []) == :error
  end

  test "ecto parameterized type loads and dumps through callbacks" do
    loader = fn value -> {:ok, value} end
    dumper = fn value -> {:ok, value} end

    assert {:ok, user_id} = Types.UserID.EctoParameterizedType.load(1, loader, [])
    assert Types.UserID.unwrap(user_id) == 1
    assert Types.UserID.EctoParameterizedType.dump(user_id, dumper, []) == {:ok, 1}
    assert Types.UserID.EctoParameterizedType.dump(1, dumper, []) == {:ok, 1}
    assert Types.UserID.EctoParameterizedType.load("1", loader, []) == :error
  end

  test "ecto parameterized type delegates equality" do
    assert Types.UserID.EctoParameterizedType.equal?(1, Types.UserID.new!(1), [])
    refute Types.UserID.EctoParameterizedType.equal?(1, 2, [])
  end
end
