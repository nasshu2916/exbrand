defmodule ExBrand.BuilderTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.Fixtures.{
    DerivedUserID,
    NormalizedEmail,
    StandaloneEmail,
    StandaloneUserID,
    Types
  }

  alias ExBrand.TestSupport.Serializable

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

  test "invalid type is rejected" do
    assert Types.UserID.new("1") == {:error, :invalid_type}
  end

  test "new! raises custom exception" do
    assert_raise ExBrand.Error, fn ->
      Types.PositiveUserID.new!(0)
    end
  end

  test "low-level API defines standalone brand module" do
    user_id = StandaloneUserID.new!(1)

    assert StandaloneUserID.unwrap(user_id) == 1
    assert StandaloneUserID.__base__() == :integer
  end

  test "low-level API supports validation options" do
    assert StandaloneEmail.new("user@example.com") |> elem(0) == :ok
    assert StandaloneEmail.new("invalid") == {:error, :invalid_email}
  end

  test "validator can normalize raw value before branding" do
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert NormalizedEmail.unwrap(email) == "user@example.com"
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
end
