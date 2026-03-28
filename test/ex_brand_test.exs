defmodule ExBrandTest do
  use ExUnit.Case, async: true

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

  defmodule StandaloneUserID do
    use ExBrand, base: :integer
  end

  defmodule StandaloneEmail do
    use ExBrand,
      base: :string,
      validate: &String.contains?(&1, "@"),
      error: :invalid_email
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
end
