defmodule ExBrand.ErrorTest do
  use ExUnit.Case, async: true

  alias ExBrand.Error
  alias ExBrand.TestSupport.Fixtures.Types

  defmodule PlainModule do
  end

  test "exception/1 builds message using brand display name when available" do
    assert %{
             reason: :invalid_type,
             module: Types.NamedUserID,
             value: "bad",
             message: "invalid brand value for User ID: :invalid_type (got \"bad\")"
           } = Error.exception(reason: :invalid_type, module: Types.NamedUserID, value: "bad")
  end

  test "exception/1 falls back to inspected module name when __name__/0 is unavailable" do
    assert %{
             reason: :invalid_type,
             module: PlainModule,
             value: "bad",
             message:
               "invalid brand value for ExBrand.ErrorTest.PlainModule: :invalid_type (got \"bad\")"
           } = Error.exception(reason: :invalid_type, module: PlainModule, value: "bad")
  end
end
