defmodule ExBrand.EctoTest do
  use ExUnit.Case, async: true

  alias ExBrand.Ecto
  alias ExBrand.TestSupport.Fixtures.Brands.PrefixedUserID
  alias ExBrand.TestSupport.Fixtures.Types

  test "type_for/1 returns the ecto type for a brand" do
    assert Ecto.type_for(Types.UserID) == :integer
    assert Ecto.type_for(PrefixedUserID) == :string
  end

  test "cast/load/dump normalize failures to :error" do
    assert Ecto.cast(Types.UserID, 1) == {:ok, Types.UserID.new!(1)}
    assert Ecto.cast(Types.UserID, "1") == expected_user_id_cast_result()

    assert Ecto.load(Types.UserID, 1) == {:ok, Types.UserID.new!(1)}
    assert Ecto.load(Types.UserID, "1") == :error

    assert Ecto.dump(Types.UserID, Types.UserID.new!(1)) == {:ok, 1}
    assert Ecto.dump(Types.UserID, 1) == {:ok, 1}
    assert Ecto.dump(Types.UserID, "1") == :error
  end

  test "parameterized_load/3 and parameterized_dump/3 propagate callback failures" do
    assert Ecto.parameterized_load(Types.UserID, 1, fn value -> {:ok, value} end) ==
             {:ok, Types.UserID.new!(1)}

    assert Ecto.parameterized_load(Types.UserID, 1, fn _value -> :error end) == :error

    assert Ecto.parameterized_dump(Types.UserID, Types.UserID.new!(1), fn value ->
             {:ok, value}
           end) ==
             {:ok, 1}

    assert Ecto.parameterized_dump(Types.UserID, Types.UserID.new!(1), fn _value -> :error end) ==
             :error
  end

  test "equal?/3 compares values through brand casts" do
    assert Ecto.equal?(Types.UserID, 1, Types.UserID.new!(1))
    refute Ecto.equal?(Types.UserID, 1, 2)
    assert Ecto.equal?(Types.UserID, 1, "1") == ecto_type_available?()
  end

  test "dump/2 returns :error for forged brand values" do
    module = compile_brand_with_signature_verification(true, "SignedEctoDumpUserIDBrand")
    forged = struct(module, __value__: 1, __signature__: 0)

    assert Ecto.dump(module, forged) == :error
  end

  defp compile_brand_with_signature_verification(enabled, module_name) do
    previous_value = Application.get_env(:ex_brand, :signature_verification)

    case enabled do
      :unset -> Application.delete_env(:ex_brand, :signature_verification)
      value -> Application.put_env(:ex_brand, :signature_verification, value)
    end

    try do
      parent_module = Module.concat([module_name])
      target_module = Module.concat(parent_module, GeneratedBrand)

      {module, _bytecode} =
        Code.compile_string("""
        defmodule #{module_name} do
          use ExBrand

          defbrand GeneratedBrand, :integer
        end
        """)
        |> Enum.find(fn {compiled_module, _bytecode} ->
          compiled_module == target_module
        end)

      module
    after
      if is_nil(previous_value) do
        Application.delete_env(:ex_brand, :signature_verification)
      else
        Application.put_env(:ex_brand, :signature_verification, previous_value)
      end
    end
  end

  defp expected_user_id_cast_result do
    if ecto_type_available?() do
      {:ok, Types.UserID.new!(1)}
    else
      :error
    end
  end

  defp ecto_type_available? do
    Code.ensure_loaded?(Ecto.Type) and function_exported?(Ecto.Type, :cast, 2)
  end
end
