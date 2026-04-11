defmodule ExBrand.Schema.RuntimePathsTest do
  use ExUnit.Case, async: true

  alias ExBrand.Schema
  alias ExBrand.TestSupport.Fixtures.{AddressSchema, Types}

  test "nullable scalar schema accepts nil" do
    assert Schema.validate(nil, {:string, nullable: true}) == {:ok, nil}
  end

  test "enum, numeric, length, and format constraints report their runtime errors" do
    assert Schema.validate("draft", {:string, enum: ["published"]}) == {:error, :not_in_enum}
    assert Schema.validate(11, {:integer, maximum: 10}) == {:error, :greater_than_maximum}
    assert Schema.validate("abcd", {:string, max_length: 3}) == {:error, :longer_than_max_length}
    assert Schema.validate(1, {:string, format: :email}) == {:error, :invalid_type}
    assert Schema.validate("broken", {:string, format: :datetime}) == {:error, :invalid_format}
    assert Schema.validate("value", {:string, format: :uuid}) == {:error, :invalid_schema}
  end

  test "list constraints report max_items and invalid unique_items schema settings" do
    assert Schema.validate([1, 2, 3], {[:integer], max_items: 2}) ==
             {:error, %{__self__: :more_than_max_items}}

    assert Schema.validate([1], {[:integer], unique_items: :invalid}) ==
             {:error, %{__self__: :invalid_schema}}
  end

  test "list constraints report invalid min and max schema settings" do
    assert Schema.validate([1], {[:integer], min_items: "1"}) ==
             {:error, %{__self__: :invalid_schema}}

    assert Schema.validate([1], {[:integer], max_items: "1"}) ==
             {:error, %{__self__: :invalid_schema}}
  end

  test "map validation reports invalid input type and invalid default values" do
    assert Schema.validate("bad", {%{name: :string}, optional: true}) == {:error, :invalid_type}

    assert Schema.validate(%{}, {%{age: {:integer, default: "oops"}}, optional: true}) ==
             {:error, %{age: :invalid_type}}
  end

  test "field lookup supports atom and string aliases and ignores consumed duplicate keys" do
    schema = {%{email: {:string, field: "contactEmail"}}, tolerant: false}

    assert Schema.validate(%{"contactEmail" => "a@example.com", contactEmail: "ignored"}, schema) ==
             {:error, %{__extra_fields__: [:contactEmail]}}
  end

  test "field lookup supports string field names backed by atom keys" do
    schema = {%{email: {:string, field: "contactEmail"}}, tolerant: false}

    assert Schema.validate(%{contactEmail: "a@example.com"}, schema) ==
             {:ok, %{email: "a@example.com"}}
  end

  test "allow_extra_fields skips extra-field rejection for map schema" do
    schema = {%{email: :string}, allow_extra_fields: true}

    assert Schema.validate(%{email: "a@example.com", unknown: "value"}, schema) ==
             {:ok, %{email: "a@example.com"}}
  end

  test "custom runtime validator can normalize nested values and wrap errors" do
    schema =
      {%{
         address: {AddressSchema, validate: fn value -> {:ok, Map.put(value, :zip, "53000")} end}
       }, optional: true}

    assert Schema.validate(%{address: %{city: "Osaka", zip: "12345"}}, schema) ==
             {:ok, %{address: %{city: "Osaka", zip: "53000"}}}

    assert Schema.validate("draft", {:string, enum: ["published"], error: :bad_status}) ==
             {:error, :bad_status}
  end

  test "brand-backed constraints operate on unwrapped values" do
    assert Schema.validate(1, {Types.UserID, enum: [2]}) == {:error, :not_in_enum}

    assert Schema.validate(1, {Types.UserID, validate: fn raw -> raw == 1 end}) ==
             {:ok, Types.UserID.new!(1)}
  end

  test "invalid runtime schema definitions return invalid_schema" do
    assert Schema.validate("value", []) == {:error, :invalid_schema}
    assert Schema.validate("value", {:string, enum: :invalid}) == {:error, :invalid_schema}
    assert Schema.validate(1, {:integer, minimum: "1"}) == {:error, :invalid_schema}
    assert Schema.validate("ab", {:string, min_length: "1"}) == {:error, :invalid_schema}
  end
end
