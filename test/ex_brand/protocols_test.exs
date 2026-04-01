# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule ExBrand.ProtocolsTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.Fixtures.{NormalizedEmail, StandaloneUserID, Types}

  test "inspect hides internal field names" do
    user_id = Types.UserID.new!(1)

    assert inspect(user_id) == "#UserID<1>"
    refute inspect(user_id) =~ "__value__"
  end

  test "string chars converts brand value to string" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert to_string(user_id) == "42"
    assert to_string(email) == "user@example.com"
  end

  test "jason encoder delegates to the raw value encoder" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    if Code.ensure_loaded?(Jason) do
      assert Jason.encode!(user_id) == Jason.encode!(42)
      assert Jason.encode!(email) == Jason.encode!("user@example.com")
    else
      assert Jason.Encoder.encode(user_id, []) == Jason.Encoder.encode(42, [])
      assert Jason.Encoder.encode(email, []) == Jason.Encoder.encode("user@example.com", [])
    end
  end

  test "json encoder delegates to the raw value encoder" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert JSON.encode!(user_id) == JSON.encode!(42)
    assert JSON.encode!(email) == JSON.encode!("user@example.com")
  end

  test "phoenix param delegates to the raw value protocol" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert Phoenix.Param.to_param(user_id) == "id-42"
    assert Phoenix.Param.to_param(email) == "param-user@example.com"
  end

  test "phoenix html safe delegates to the raw value protocol" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert Phoenix.HTML.Safe.to_iodata(user_id) == ["safe-int:", "42"]
    assert Phoenix.HTML.Safe.to_iodata(email) == ["safe-str:", "user@example.com"]
  end

  test "standalone modules also receive protocol implementations" do
    user_id = StandaloneUserID.new!(1)

    assert inspect(user_id) == "#StandaloneUserID<1>"
  end

  test "inspect uses configured brand name when present" do
    user_id = Types.NamedUserID.new!(1)

    assert inspect(user_id) == "#User ID<1>"
  end

  test "protocol implementations reject forged values" do
    module = compile_brand_with_signature_verification(true, "SignedProtocolUserIDBrand")
    forged_user_id = struct(module, __value__: 1, __signature__: 0)

    assert inspect(forged_user_id) =~ "invalid forged or mutated brand value"

    assert_raise ArgumentError, ~r/invalid forged or mutated brand value/, fn ->
      to_string(forged_user_id)
    end

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
