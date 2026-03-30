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

  test "standalone modules also receive protocol implementations" do
    user_id = StandaloneUserID.new!(1)

    assert inspect(user_id) == "#StandaloneUserID<1>"
  end
end
