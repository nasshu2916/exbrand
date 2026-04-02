defmodule ExBrand.ValidatorTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.CustomBases.PrefixedString
  alias ExBrand.Validator

  test "validate/4 returns base validation errors before custom validation" do
    assert Validator.validate("1", :integer, fn _ -> true end, :invalid) ==
             {:error, :invalid_type}
  end

  test "validate_custom/4 accepts boolean and ok validator results" do
    assert Validator.validate_custom(
             "usr_1",
             {PrefixedString, prefix: "usr_"},
             fn _ -> true end,
             nil
           ) ==
             {:ok, "usr_1"}

    assert Validator.validate_custom(
             "usr_1",
             {PrefixedString, prefix: "usr_"},
             fn _ -> :ok end,
             nil
           ) ==
             {:ok, "usr_1"}
  end

  test "validate_custom/4 handles false, explicit errors, and invalid validator results" do
    assert Validator.validate_custom(
             "usr_1",
             {PrefixedString, prefix: "usr_"},
             fn _ -> false end,
             nil
           ) ==
             {:error, :invalid_value}

    assert Validator.validate_custom(
             "usr_1",
             {PrefixedString, prefix: "usr_"},
             fn _ -> false end,
             :custom_error
           ) ==
             {:error, :custom_error}

    assert Validator.validate_custom(
             "usr_1",
             {PrefixedString, prefix: "usr_"},
             fn _ -> {:error, :bad} end,
             nil
           ) ==
             {:error, :bad}

    assert Validator.validate_custom(
             "usr_1",
             {PrefixedString, prefix: "usr_"},
             fn _ -> :wat end,
             nil
           ) ==
             {:error, {:invalid_validator_result, :wat}}
  end

  test "validate_custom/4 validates normalized values returned by validators" do
    assert Validator.validate_custom(
             "usr_1",
             {PrefixedString, prefix: "usr_"},
             fn _ -> {:ok, "usr_2"} end,
             nil
           ) ==
             {:ok, "usr_2"}

    assert Validator.validate_custom(
             "usr_1",
             {PrefixedString, prefix: "usr_"},
             fn _ -> {:ok, "bad"} end,
             nil
           ) ==
             {:error, {:invalid_normalized_type, "bad"}}
  end

  test "validate_schema_base/2 supports schema-only scalar types and invalid schemas" do
    assert Validator.validate_schema_base(%{raw: "value"}, :any) == {:ok, %{raw: "value"}}
    assert Validator.validate_schema_base(true, :boolean) == {:ok, true}
    assert Validator.validate_schema_base(1.5, :number) == {:ok, 1.5}
    assert Validator.validate_schema_base(nil, :null) == {:ok, nil}

    assert Validator.validate_schema_base("true", :boolean) == {:error, :invalid_type}
    assert Validator.validate_schema_base("1.5", :number) == {:error, :invalid_type}
    assert Validator.validate_schema_base("nil", :null) == {:error, :invalid_type}
    assert Validator.validate_schema_base("value", "invalid") == {:error, :invalid_schema}
  end
end
