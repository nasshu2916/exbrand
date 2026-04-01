# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule ExBrand.Adapter.PhoenixTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.Fixtures.{NormalizedEmail, Types}

  test "phoenix param adapter delegates to the raw value protocol" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert Phoenix.Param.to_param(user_id) == "id-42"
    assert Phoenix.Param.to_param(email) == "param-user@example.com"
  end

  test "phoenix html safe adapter delegates to the raw value protocol" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert Phoenix.HTML.Safe.to_iodata(user_id) == ["safe-int:", "42"]
    assert Phoenix.HTML.Safe.to_iodata(email) == ["safe-str:", "user@example.com"]
  end

  test "phoenix html safe adapter rejects forged values" do
    module = compile_brand_with_signature_verification(true, "SignedPhoenixAdapterUserIDBrand")
    forged_user_id = struct(module, __value__: 1, __signature__: 0)

    assert_raise ArgumentError, ~r/invalid forged or mutated brand value/, fn ->
      Phoenix.HTML.Safe.to_iodata(forged_user_id)
    end
  end

  defp compile_brand_with_signature_verification(enabled, module_name) do
    previous_value = Application.get_env(:ex_brand, :signature_verification)

    case enabled do
      :unset -> Application.delete_env(:ex_brand, :signature_verification)
      value -> Application.put_env(:ex_brand, :signature_verification, value)
    end

    try do
      target_module = Module.concat([module_name])

      {module, _bytecode} =
        Code.compile_string("""
        defmodule #{module_name} do
          use ExBrand, :integer
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
end
