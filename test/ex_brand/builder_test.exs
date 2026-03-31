defmodule ExBrand.BuilderTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.Fixtures.{
    DerivedUserID,
    NormalizedEmail,
    StandaloneEmail,
    StandaloneGeneratedEmail,
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

  test "forged struct is not treated as a brand" do
    refute Types.UserID.is_brand?(%Types.UserID{__value__: 1, __signature__: 0})
  end

  test "unwrap returns raw value" do
    user_id = Types.UserID.new!(1)

    assert Types.UserID.unwrap(user_id) == 1
  end

  test "unwrap rejects forged or mutated brand value" do
    user_id = Types.UserID.new!(1)
    forged_user_id = %Types.UserID{__value__: 1, __signature__: 0}
    mutated_user_id = %{user_id | __value__: 2}

    assert_raise ArgumentError, ~r/invalid forged or mutated brand value/, fn ->
      Types.UserID.unwrap(forged_user_id)
    end

    assert_raise ArgumentError, ~r/invalid forged or mutated brand value/, fn ->
      Types.UserID.unwrap(mutated_user_id)
    end
  end

  test "generic unwrap extracts raw value from any ExBrand value" do
    user_id = Types.UserID.new!(1)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert ExBrand.unwrap(user_id) == 1
    assert ExBrand.unwrap(email) == "user@example.com"
  end

  test "generic unwrap rejects non-brand values" do
    assert_raise ArgumentError, ~r/expected an ExBrand value/, fn ->
      ExBrand.unwrap(1)
    end
  end

  test "maybe_unwrap returns raw value for brands and passthrough otherwise" do
    user_id = Types.UserID.new!(1)

    assert ExBrand.maybe_unwrap(user_id) == 1
    assert ExBrand.maybe_unwrap("plain") == "plain"
    assert ExBrand.maybe_unwrap(nil) == nil
  end

  test "gen returns configured generator expression" do
    assert Types.UserID.gen() == nil
    assert Types.GeneratedUserID.gen() == {:integer_generator, min: 1}
    assert StandaloneGeneratedEmail.gen() == {:email_generator, normalize: true}
  end

  test "validate option rejects invalid value" do
    assert Types.Email.new("user@example.com") |> elem(0) == :ok
    assert Types.Email.new("invalid") == {:error, :invalid_email}
  end

  test "cast accepts valid raw value" do
    assert {:ok, user_id} = Types.UserID.cast(1)
    assert Types.UserID.unwrap(user_id) == 1
  end

  test "cast accepts the same brand value and keeps it valid" do
    user_id = Types.UserID.new!(1)

    assert {:ok, casted_user_id} = Types.UserID.cast(user_id)
    assert casted_user_id == user_id
  end

  test "cast revalidates an existing brand value" do
    forged_email = %Types.Email{__value__: "invalid", __signature__: 0}

    assert_raise ArgumentError, ~r/invalid forged or mutated brand value/, fn ->
      Types.Email.cast(forged_email)
    end
  end

  test "cast rejects invalid raw value" do
    assert Types.UserID.cast("1") == {:error, :invalid_type}
  end

  test "cast! raises custom exception on invalid value" do
    assert_raise ExBrand.Error, fn ->
      Types.PositiveUserID.cast!(0)
    end
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

  test "reflection API exposes brand metadata" do
    assert Types.UserID.__meta__() == %{
             module: Types.UserID,
             name: "UserID",
             base: :integer,
             validator: nil,
             generator: nil,
             error: nil
           }

    email_meta = Types.Email.__meta__()

    assert email_meta.module == Types.Email
    assert email_meta.base == :string
    assert email_meta.error == :invalid_email
    assert email_meta.generator == nil
    assert is_function(email_meta.validator, 1)
    assert Types.Email.__brand__() == email_meta
  end

  test "reflection API exposes configured generator metadata" do
    assert Types.GeneratedUserID.__meta__() == %{
             module: Types.GeneratedUserID,
             name: "GeneratedUserID",
             base: :integer,
             validator: nil,
             generator: {:integer_generator, min: 1},
             error: nil
           }
  end

  test "brand can expose a custom display name" do
    assert Types.NamedUserID.__name__() == "User ID"
    assert Types.NamedUserID.__meta__().name == "User ID"
    assert Types.NamedAccessToken.__name__() == "Access Token"
  end

  test "name option rejects unsupported shapes" do
    assert_raise ArgumentError, ~r/name must be a string or atom/, fn ->
      Code.compile_string("""
      defmodule InvalidNamedBrand do
        use ExBrand,
          base: :integer,
          name: 123
      end
      """)
    end
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
