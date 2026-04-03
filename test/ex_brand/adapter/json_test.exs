# credo:disable-for-this-file Credo.Check.Design.AliasUsage
defmodule ExBrand.Adapter.JSONTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.Fixtures.Brands.NormalizedEmail
  alias ExBrand.TestSupport.Fixtures.Types

  test "jason encoder adapter delegates to the raw value encoder" do
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

  test "json encoder adapter delegates to the raw value encoder" do
    user_id = Types.UserID.new!(42)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert JSON.encode!(user_id) == JSON.encode!(42)
    assert JSON.encode!(email) == JSON.encode!("user@example.com")
  end
end
