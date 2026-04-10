defmodule ExBrand.Schema.DefinitionTest do
  use ExUnit.Case, async: true

  alias ExBrand.Schema.Definition
  alias ExBrand.TestSupport.CustomBases.PrefixedString
  alias ExBrand.TestSupport.Fixtures.{AddressSchema, Types}

  test "returns exported schema metadata keys" do
    assert :default in Definition.schema_option_keys()
    assert :validate in Definition.schema_option_keys()
    assert Definition.internal_error_key() == :__extra_fields__
  end

  test "expand_schema/2 expands aliases inside nested structures" do
    schema_ast = {%{address: {:__aliases__, [], [:AddressSchema]}}, optional: true}
    env = %{__ENV__ | aliases: [{AddressSchema, ExBrand.TestSupport.Fixtures.AddressSchema}]}
    {expanded_schema, opts} = Definition.expand_schema(schema_ast, env)

    assert opts == [optional: true]
    assert is_atom(expanded_schema.address)
    refute expanded_schema.address == {:__aliases__, [], [:AddressSchema]}
  end

  test "split_schema_opts/1 and merge_field_opts/2 normalize field aliases" do
    assert Definition.split_schema_opts(:string) == {:string, []}
    assert Definition.split_schema_opts({:string, min_length: 2}) == {:string, [min_length: 2]}

    assert Definition.merge_field_opts({:string, min_length: 2}, required: false, from: "name") ==
             {:string, [min_length: 2, optional: true, field: "name"]}
  end

  test "compile_runtime_schema!/1 resolves runtime nodes ahead of validation" do
    compiled =
      Definition.compile_runtime_schema!({
        %{
          user_id: Types.UserID,
          contact_email: {Types.Email, field: "contactEmail"},
          profile: {AddressSchema, optional: true},
          tags: {[{:string, min_length: 2}], min_items: 1}
        },
        tolerant: false
      })

    assert Definition.compiled_runtime_schema?(compiled)

    assert {:compiled, :map, compiled_fields, [tolerant: false]} = compiled

    assert %{
             schema: {:compiled, :terminal, {:brand, Types.UserID}, []},
             lookup: [:user_id, "user_id"]
           } =
             compiled_fields.user_id

    assert %{
             schema: {:compiled, :terminal, {:brand, Types.Email}, [field: "contactEmail"]},
             lookup: ["contactEmail", {:existing_atom_binary, "contactEmail"}]
           } =
             compiled_fields.contact_email

    assert %{
             schema: {:compiled, :terminal, {:schema, AddressSchema}, [optional: true]},
             lookup: [:profile, "profile"]
           } =
             compiled_fields.profile

    assert %{
             schema:
               {:compiled, :list, {:compiled, :terminal, {:base, :string}, [min_length: 2]},
                [min_items: 1]},
             lookup: [:tags, "tags"]
           } = compiled_fields.tags
  end

  test "normalize_field_opts/1 rejects unsupported field options" do
    assert_raise ArgumentError, ~r/unsupported field option: :unknown/, fn ->
      Definition.normalize_field_opts(unknown: true)
    end
  end

  test "resolve_terminal_schema/1 distinguishes base, brand, schema, and invalid definitions" do
    assert Definition.resolve_terminal_schema(:integer) == {:ok, {:base, :integer}}
    assert Definition.resolve_terminal_schema(Types.UserID) == {:ok, {:brand, Types.UserID}}
    assert Definition.resolve_terminal_schema(AddressSchema) == {:ok, {:schema, AddressSchema}}
    assert Definition.resolve_terminal_schema(PrefixedString) == {:ok, {:base, PrefixedString}}

    assert Definition.resolve_terminal_schema({Types.UserID, precision: 2}) == :error
    assert Definition.resolve_terminal_schema({AddressSchema, precision: 2}) == :error
    assert Definition.resolve_terminal_schema("invalid") == :error
  end

  test "validate_constraint_values!/2 accepts supported constraint values" do
    assert :ok =
             Definition.validate_constraint_values!(
               [
                 default: "value",
                 enum: ["a", "b"],
                 error: :invalid,
                 field: "email",
                 format: :email,
                 max_items: 3,
                 max_length: 5,
                 maximum: 10,
                 min_items: 1,
                 min_length: 1,
                 minimum: 0,
                 nullable: false,
                 optional: true,
                 tolerant: false,
                 unique_items: true,
                 validate: fn value -> value end
               ],
               "field :email"
             )
  end

  test "validate_constraint_values!/2 rejects invalid values" do
    assert_raise ArgumentError,
                 ~r/invalid constraint value at field :published_at: :format => :uuid/,
                 fn ->
                   Definition.validate_constraint_values!([format: :uuid], "field :published_at")
                 end
  end

  test "ensure_allowed_constraints!/4 rejects unsupported keys" do
    assert_raise ArgumentError,
                 ~r/unsupported constraints for list at field :tags: :minimum/,
                 fn ->
                   Definition.ensure_allowed_constraints!(
                     [minimum: 1],
                     Definition.list_constraint_keys(),
                     "field :tags",
                     :list
                   )
                 end
  end

  test "validate_terminal_schema_definition!/3 validates scalar, brand, nested schema, and invalid schema" do
    assert :ok =
             Definition.validate_terminal_schema_definition!(
               :integer,
               [minimum: 1, maximum: 10],
               "field :age"
             )

    assert :ok =
             Definition.validate_terminal_schema_definition!(
               Types.UserID,
               [optional: true],
               "field :user_id"
             )

    assert :ok =
             Definition.validate_terminal_schema_definition!(
               AddressSchema,
               [optional: true],
               "field :address"
             )

    assert_raise ArgumentError, ~r/invalid schema at field :missing: "bad"/, fn ->
      Definition.validate_terminal_schema_definition!("bad", [], "field :missing")
    end

    assert_raise ArgumentError,
                 ~r/unsupported constraints for schema at field :address: :minimum/,
                 fn ->
                   Definition.validate_terminal_schema_definition!(
                     AddressSchema,
                     [minimum: 1],
                     "field :address"
                   )
                 end
  end

  test "constraint profile helpers infer scalar and nested schema profiles" do
    assert Definition.infer_constraint_profile(:number) == {:ok, {:scalar, :number}}
    assert Definition.infer_constraint_profile(Types.Email) == {:ok, {:brand, :string}}

    assert Definition.infer_constraint_profile(AddressSchema) ==
             {:ok, {:nested_schema, AddressSchema}}

    assert Definition.infer_constraint_profile(PrefixedString) == {:ok, {:scalar, :custom_base}}
    assert Definition.infer_constraint_profile("bad") == :error

    assert Definition.allowed_constraint_keys_for_profile(:custom_base) ==
             [:default, :enum, :error, :nullable, :optional, :field, :validate]

    assert Definition.scalar_profile_for_brand(Types.UserID) == :integer
    assert Definition.scalar_profile_for_brand(Types.Email) == :string
    assert Definition.scalar_profile_for_base(:binary) == :binary
    assert Definition.scalar_profile_for_base({PrefixedString, prefix: "usr_"}) == :custom_base
  end

  test "constraint key helpers expose map and list keys" do
    assert :tolerant in Definition.map_constraint_keys()
    assert :min_items in Definition.list_constraint_keys()
    refute :tolerant in Definition.list_constraint_keys()
  end
end
