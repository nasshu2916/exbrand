defmodule ExBrand.Schema.CompilerTest do
  use ExUnit.Case, async: true

  alias ExBrand.Schema.Compiler
  alias ExBrand.TestSupport.Fixtures.AddressSchema

  test "build_field_ast!/1 validates field name" do
    assert_raise ArgumentError, ~r/field name must be an atom/, fn ->
      Compiler.build_field_ast!({"age", :integer})
    end
  end

  test "build_field_ast!/1 returns field AST for valid definitions" do
    ast = Compiler.build_field_ast!({:age, {:integer, optional: true}})

    assert Macro.to_string(ast) == "{:age, {:integer, optional: true}}"
  end

  test "validate_schema_definition!/2 rejects invalid list and map constraints" do
    assert_raise ArgumentError,
                 ~r/list schema must contain exactly one item schema/,
                 fn ->
                   Compiler.validate_schema_definition!([:integer, :string], "field :tags")
                 end

    assert_raise ArgumentError,
                 ~r/unsupported constraints for map at field :profile: :minimum/,
                 fn ->
                   Compiler.validate_schema_definition!(
                     {%{name: :string}, minimum: 1},
                     "field :profile"
                   )
                 end
  end

  test "validate_schema_definition!/2 traverses nested schemas" do
    assert :ok =
             Compiler.validate_schema_definition!(
               {%{address: AddressSchema}, optional: true},
               "field :profile"
             )
  end
end
