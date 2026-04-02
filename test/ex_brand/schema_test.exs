defmodule ExBrand.SchemaTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.Fixtures.{AddressSchema, TolerantUserSchema, Types, UserSchema}

  test "schema validates params and normalizes brand fields" do
    assert {:ok, result} =
             UserSchema.validate(%{
               "contactEmail" => "contact@example.com",
               address: %{city: "Tokyo", zip: "15000"},
               user_id: 1,
               email: "user@example.com",
               age: 20,
               tags: ["elixir", "otp"],
               published_at: "2026-04-02T12:34:56Z"
             })

    assert Types.UserID.brand?(result.user_id)
    assert Types.UserID.unwrap(result.user_id) == 1
    assert Types.Email.unwrap(result.email) == "user@example.com"
    assert Types.Email.unwrap(result.contact_email) == "contact@example.com"
    assert result.age == 20
    assert result.nickname == nil
    assert result.status == "active"
    assert result.address == %{city: "Tokyo", zip: "15000"}
    assert result.tags == ["elixir", "otp"]
    assert result.published_at == "2026-04-02T12:34:56Z"
  end

  test "schema accumulates field errors from tuple constraints" do
    assert {:error, errors} =
             UserSchema.validate(%{
               "contactEmail" => "invalid",
               address: %{city: "Tokyo", zip: "12"},
               user_id: "1",
               email: "invalid",
               age: 17,
               tags: ["x", "x"],
               published_at: "2026-04-02"
             })

    assert errors == %{
             user_id: :invalid_type,
             email: :invalid_email,
             age: :too_young,
             contact_email: :invalid_email,
             address: %{zip: :shorter_than_min_length},
             tags: %{
               0 => :shorter_than_min_length,
               1 => :shorter_than_min_length,
               :__self__ => :items_not_unique
             },
             published_at: :invalid_format
           }
  end

  test "schema reports required fields" do
    assert {:error, %{user_id: :required, contact_email: :required, address: :required}} =
             UserSchema.validate(%{
               email: "user@example.com",
               age: 20
             })
  end

  test "schema rejects unknown fields by default" do
    assert {:error, %{__extra_fields__: [:unknown]}} =
             UserSchema.validate(%{
               "contactEmail" => "contact@example.com",
               address: %{city: "Tokyo", zip: "15000"},
               user_id: 1,
               email: "user@example.com",
               age: 20,
               unknown: "value"
             })
  end

  test "tolerant schema accepts unknown fields" do
    assert {:ok, %{user_id: user_id}} =
             TolerantUserSchema.validate(%{
               user_id: 1,
               unknown: "value"
             })

    assert Types.UserID.unwrap(user_id) == 1
  end

  test "schema validates nested schema directly" do
    assert {:ok, %{city: "Osaka", zip: "53000"}} =
             AddressSchema.validate(%{city: "Osaka", zip: "53000"})
  end

  test "schema supports inline map schema" do
    schema = {%{name: {:string, min_length: 1}, age: {:integer, minimum: 18}}, tolerant: false}

    assert {:ok, %{name: "naoya", age: 20}} =
             ExBrand.Schema.validate(%{name: "naoya", age: 20}, schema)

    assert {:error, %{age: :less_than_minimum}} =
             ExBrand.Schema.validate(%{name: "naoya", age: 17}, schema)
  end

  test "schema supports direct list schema" do
    schema = {[{:integer, minimum: 1}], min_items: 2, unique_items: true}

    assert {:ok, [1, 2]} = ExBrand.Schema.validate([1, 2], schema)

    assert {:error, %{0 => :less_than_minimum, :__self__ => :fewer_than_min_items}} =
             ExBrand.Schema.validate([0], schema)
  end

  test "schema supports scalar bases handled by the shared validator" do
    assert {:ok, true} = ExBrand.Schema.validate(true, :boolean)
    assert {:ok, 1.5} = ExBrand.Schema.validate(1.5, :number)
    assert {:ok, nil} = ExBrand.Schema.validate(nil, :null)
    assert {:ok, %{raw: "value"}} = ExBrand.Schema.validate(%{raw: "value"}, :any)

    assert {:error, :invalid_type} = ExBrand.Schema.validate("true", :boolean)
    assert {:error, :invalid_type} = ExBrand.Schema.validate("1.5", :number)
    assert {:error, :invalid_type} = ExBrand.Schema.validate("nil", :null)
  end

  test "schema custom validator can normalize values through the shared validator flow" do
    schema =
      {:string,
       validate: fn value ->
         {:ok, String.trim(value)}
       end}

    assert {:ok, "naoya"} = ExBrand.Schema.validate("  naoya  ", schema)
  end

  test "unsupported constraints are rejected at compile time for scalar fields" do
    assert_raise ArgumentError,
                 ~r/unsupported constraints for integer at field :age: :min_length/,
                 fn ->
                   Code.compile_string("""
                   defmodule InvalidIntegerConstraintSchema do
                     use ExBrand.Schema

                     field :age, {:integer, min_length: 2}
                   end
                   """)
                 end
  end

  test "unsupported constraints are rejected at compile time for list fields" do
    assert_raise ArgumentError,
                 ~r/unsupported constraints for list at field :tags: :minimum/,
                 fn ->
                   Code.compile_string("""
                   defmodule InvalidListConstraintSchema do
                     use ExBrand.Schema

                     field :tags, {[ :string ], minimum: 1}
                   end
                   """)
                 end
  end

  test "invalid constraint values are rejected at compile time" do
    assert_raise ArgumentError,
                 ~r/invalid constraint value at field :published_at: :format => :uuid/,
                 fn ->
                   Code.compile_string("""
                   defmodule InvalidFormatConstraintSchema do
                     use ExBrand.Schema

                     field :published_at, {:string, format: :uuid}
                   end
                   """)
                 end
  end

  test "validate! raises on invalid params" do
    assert_raise ArgumentError, ~r/invalid schema value/, fn ->
      UserSchema.validate!(%{user_id: "1"})
    end
  end

  test "valid? returns whether params satisfy the schema" do
    assert UserSchema.valid?(%{
             "contactEmail" => "contact@example.com",
             address: %{city: "Tokyo", zip: "15000"},
             user_id: 1,
             email: "user@example.com",
             age: 20
           })

    refute UserSchema.valid?(%{user_id: "1"})
  end
end
