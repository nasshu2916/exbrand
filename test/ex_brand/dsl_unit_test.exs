defmodule ExBrand.DSLUnitTest do
  use ExUnit.Case, async: true

  alias ExBrand.DSL
  alias ExBrand.Type.Email
  alias ExBrand.TestSupport.CustomBases.PrefixedString

  test "expand_name!/1 accepts aliases and atoms" do
    assert DSL.expand_name!({:__aliases__, [], [:Foo, :Bar]}) == Foo.Bar
    assert DSL.expand_name!(:UserID) == :UserID
  end

  test "expand_name!/1 rejects unsupported values" do
    assert_raise ArgumentError, ~r/brand name must be an alias or atom/, fn ->
      DSL.expand_name!("UserID")
    end
  end

  test "expand_base!/2 expands custom base aliases and tuple-style AST" do
    assert DSL.expand_base!(:integer, __ENV__) == :integer
    assert DSL.expand_base!({:__aliases__, [], [:ExBrand, :Type, :Email]}, __ENV__) == Email

    assert DSL.expand_base!(
             {{:__aliases__, [], [:ExBrand, :TestSupport, :CustomBases, :PrefixedString]},
              [prefix: "usr_"]},
             __ENV__
           ) == {PrefixedString, prefix: "usr_"}
  end
end
