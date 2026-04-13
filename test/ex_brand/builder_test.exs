defmodule ExBrand.BuilderTest do
  use ExUnit.Case, async: false

  alias ExBrand.TestSupport.Fixtures.Brands.{
    DerivedUserID,
    GeneratedEmail,
    NormalizedEmail,
    PrefixedUserID
  }

  alias ExBrand.TestSupport.Fixtures.Types
  alias ExBrand.TestSupport.Serializable

  test "integer brands are distinct modules" do
    {:ok, user_id} = Types.UserID.new(1)
    {:ok, order_id} = Types.OrderID.new(1)

    assert Types.UserID.brand?(user_id)
    refute Types.UserID.brand?(order_id)
  end

  test "forged struct is not treated as a brand" do
    module = compile_brand_with_signature_verification(true, "SignedUserIDBrand")

    refute module.brand?(struct(module, __value__: 1, __signature__: 0))
  end

  test "unwrap returns raw value" do
    user_id = Types.UserID.new!(1)

    assert Types.UserID.unwrap(user_id) == 1
  end

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

  test "unwrap rejects forged or mutated brand value" do
    module = compile_brand_with_signature_verification(true, "SignedUserIDForUnwrapBrand")
    user_id = module.new!(1)
    forged_user_id = struct(module, __value__: 1, __signature__: 0)
    mutated_user_id = %{user_id | __value__: 2}

    assert_raise ArgumentError, ~r/invalid forged or mutated brand value/, fn ->
      module.unwrap(forged_user_id)
    end

    assert_raise ArgumentError, ~r/invalid forged or mutated brand value/, fn ->
      module.unwrap(mutated_user_id)
    end
  end

  test "generic unwrap extracts raw value from any ExBrand value" do
    user_id = Types.UserID.new!(1)
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert ExBrand.unwrap!(user_id) == 1
    assert ExBrand.unwrap!(email) == "user@example.com"
  end

  test "generic unwrap rejects non-brand values" do
    assert_raise ArgumentError, ~r/expected an ExBrand value/, fn ->
      ExBrand.unwrap!(1)
    end
  end

  test "maybe_unwrap returns raw value for brands and passthrough otherwise" do
    user_id = Types.UserID.new!(1)

    assert ExBrand.unwrap(user_id) == 1
    assert ExBrand.unwrap("plain") == "plain"
    assert ExBrand.unwrap(nil) == nil
  end

  test "gen returns configured generator expression" do
    assert Types.UserID.gen() == nil
    assert Types.GeneratedUserID.gen() == {:integer_generator, min: 1}

    assert GeneratedEmail.gen() == {:email_generator, normalize: true}
  end

  test "validate option rejects invalid value" do
    assert Types.Email.new("user@example.com") |> elem(0) == :ok
    assert Types.Email.new("invalid") == {:error, :invalid_email}
  end

  test "signature verification is disabled by default for newly compiled brands" do
    module = compile_brand_with_signature_verification(:unset, "SignatureDefaultDisabledBrand")
    brand = module.new!(1)

    assert module.brand?(brand)
    assert module.unwrap(brand) == 1
    assert Map.has_key?(brand, :__value__)
    refute Map.has_key?(brand, :__signature__)
  end

  test "signature verification can be enabled via config" do
    module = compile_brand_with_signature_verification(true, "SignatureEnabledBrand")
    forged_brand = struct(module, __value__: 1, __signature__: 0)

    refute module.brand?(forged_brand)

    assert_raise ArgumentError, ~r/invalid forged or mutated brand value/, fn ->
      module.unwrap(forged_brand)
    end
  end

  test "inspect rejects forged values" do
    module = compile_brand_with_signature_verification(true, "SignedInspectUserIDBrand")
    forged_brand = struct(module, __value__: 1, __signature__: 0)

    assert inspect(forged_brand) =~ "invalid forged or mutated brand value"
  end

  test "string chars rejects forged values" do
    module = compile_brand_with_signature_verification(true, "SignedStringCharsUserIDBrand")
    forged_brand = struct(module, __value__: 1, __signature__: 0)

    assert_raise ArgumentError, ~r/invalid forged or mutated brand value/, fn ->
      to_string(forged_brand)
    end
  end

  test "invalid type is rejected" do
    assert Types.UserID.new("1") == {:error, :invalid_type}
  end

  test "unsafe_new/1 bypasses base validation and custom validator" do
    assert {:ok, unsafe_user_id} = Types.UserID.unsafe_new("1")
    assert Types.UserID.unwrap(unsafe_user_id) == "1"

    assert {:ok, unsafe_email} = Types.Email.unsafe_new("invalid")
    assert Types.Email.unwrap(unsafe_email) == "invalid"
  end

  test "unsafe_new/1 generates a valid signed brand when signature verification is enabled" do
    module = compile_brand_with_signature_verification(true, "SignedUnsafeNewUserIDBrand")
    assert {:ok, unsafe_brand} = module.unsafe_new("invalid_type")
    assert module.brand?(unsafe_brand)
    assert module.unwrap(unsafe_brand) == "invalid_type"
  end

  test "new! raises custom exception" do
    assert_raise ExBrand.Error, fn ->
      Types.PositiveUserID.new!(0)
    end
  end

  test "custom base module can validate user-defined raw types" do
    assert {:ok, user_id} = PrefixedUserID.new("usr_123")
    assert PrefixedUserID.unwrap(user_id) == "usr_123"
    assert PrefixedUserID.new("123") == {:error, :invalid_type}

    assert PrefixedUserID.__base__() ==
             {ExBrand.TestSupport.CustomBases.PrefixedString, prefix: "usr_", ecto_type: :string}
  end

  test "reflection API exposes brand metadata" do
    assert Types.UserID.__meta__() == %{
             module: Types.UserID,
             name: "UserID",
             base: :integer,
             validator: nil,
             generator: nil,
             error: nil
           }

    email_meta = Types.Email.__meta__()

    assert email_meta.module == Types.Email
    assert email_meta.base == :string
    assert email_meta.error == :invalid_email
    assert email_meta.generator == nil
    assert is_function(email_meta.validator, 1)
  end

  test "reflection API exposes configured generator metadata" do
    assert Types.GeneratedUserID.__meta__() == %{
             module: Types.GeneratedUserID,
             name: "GeneratedUserID",
             base: :integer,
             validator: nil,
             generator: {:integer_generator, min: 1},
             error: nil
           }
  end

  test "custom base metadata is reflected as configured" do
    assert PrefixedUserID.__meta__() == %{
             module: PrefixedUserID,
             name: "PrefixedUserID",
             base:
               {ExBrand.TestSupport.CustomBases.PrefixedString,
                prefix: "usr_", ecto_type: :string},
             validator: nil,
             generator: nil,
             error: nil
           }
  end

  test "brand can expose a custom display name" do
    assert Types.NamedUserID.__name__() == "User ID"
    assert Types.NamedUserID.__meta__().name == "User ID"
    assert Types.NamedAccessToken.__name__() == "Access Token"
    assert inspect(Types.NamedUserID.new!(1)) == "#User ID<1>"
  end

  test "name option rejects unsupported shapes" do
    assert_raise ArgumentError, ~r/name must be a string or atom/, fn ->
      Code.compile_string("""
      defmodule InvalidNamedBrandContainer do
        use ExBrand

        defbrand InvalidNamedBrand, {:integer, name: 123}
      end
      """)
    end
  end

  test "validator can normalize raw value before branding" do
    email = NormalizedEmail.new!("  USER@EXAMPLE.COM  ")

    assert NormalizedEmail.unwrap(email) == "user@example.com"
  end

  test "derive applies protocol implementations with options" do
    user_id = DerivedUserID.new!(42)

    assert Serializable.serialize(user_id) == {:user_id, 42}
  end

  test "derive option rejects unsupported shapes" do
    assert_raise ArgumentError,
                 ~r/derive must be a protocol or list of protocols/,
                 fn ->
                   Code.compile_string("""
                   defmodule InvalidDerivedBrandContainer do
                     use ExBrand

                     defbrand InvalidDerivedBrand, {:integer, derive: "Serializable"}
                   end
                   """)
                 end
  end

  defp compile_brand_with_signature_verification(enabled, module_name) do
    compile_brand_module_with_signature_verification(
      enabled,
      module_name,
      "defbrand GeneratedBrand, :integer"
    )
  end

  defp compile_brand_module_with_signature_verification(enabled, module_name, module_body) do
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

          #{module_body}
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
