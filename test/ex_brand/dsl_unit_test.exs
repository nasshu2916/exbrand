defmodule ExBrand.DSLUnitTest do
  use ExUnit.Case, async: true

  alias ExBrand.DSL
  alias ExBrand.TestSupport.CustomBases.PrefixedString
  alias ExBrand.TestSupport.Fixtures.Types

  test "normalize_aliases/1 handles false, nil, and alias lists" do
    assert DSL.normalize_aliases(false) == []
    assert DSL.normalize_aliases(nil) == []
    assert DSL.normalize_aliases([Types.UserID, String]) == [Types.UserID, String]
  end

  test "normalize_aliases/1 rejects unsupported shapes" do
    assert_raise ArgumentError, ~r/aliases must be false or a list of brand names/, fn ->
      DSL.normalize_aliases(true)
    end
  end

  test "build_aliases_for_parent/2 builds alias AST under the given parent" do
    aliases = DSL.build_aliases_for_parent(Types, [:UserID, :OrderID])

    assert Enum.map(aliases, &Macro.to_string/1) == [
             "alias ExBrand.TestSupport.Fixtures.Types.UserID",
             "alias ExBrand.TestSupport.Fixtures.Types.OrderID"
           ]
  end

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

    assert DSL.expand_base!(
             {{:__aliases__, [], [:ExBrand, :TestSupport, :CustomBases, :PrefixedString]},
              [prefix: "usr_"]},
             __ENV__
           ) == {PrefixedString, prefix: "usr_"}
  end
end
