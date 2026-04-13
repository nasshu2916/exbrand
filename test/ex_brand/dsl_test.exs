defmodule ExBrand.DSLTest do
  use ExUnit.Case, async: true

  test "tuple-style brand definition is supported" do
    modules =
      Code.compile_string("""
      defmodule TupleStyleTypes do
        use ExBrand

        defbrand UserID, :integer
        defbrand NamedOrderID, {:integer, name: "Order ID"}

        def user_id_base, do: __MODULE__.UserID.__base__()
        def named_order_id_name, do: __MODULE__.NamedOrderID.__name__()
      end
      """)

    {module, _bytecode} =
      Enum.find(modules, fn {compiled_module, _bytecode} ->
        compiled_module == TupleStyleTypes
      end)

    assert module.user_id_base() == :integer
    assert module.named_order_id_name() == "Order ID"
  end

  test "multiple defbrand definitions can be written sequentially" do
    modules =
      Code.compile_string("""
      defmodule TupleStyleBlockTypes do
        use ExBrand

        defbrand UserID, :integer
        defbrand Email, {:string, name: "Email Address"}

        def user_id_base, do: __MODULE__.UserID.__base__()
        def email_name, do: __MODULE__.Email.__name__()
      end
      """)

    {module, _bytecode} =
      Enum.find(modules, fn {compiled_module, _bytecode} ->
        compiled_module == TupleStyleBlockTypes
      end)

    assert module.user_id_base() == :integer
    assert module.email_name() == "Email Address"
  end

  test "defbrand can be declared in a module that also defines defstruct" do
    modules =
      Code.compile_string("""
        defmodule StructBackedTypes do
        use ExBrand

        defstruct [user_id: nil]

        def new_struct(id), do: %__MODULE__{user_id: __MODULE__.UserID.new!(id)}
        def unwrap_struct(%__MODULE__{user_id: user_id}), do: __MODULE__.UserID.unwrap(user_id)

        defbrand UserID, :integer
      end
      """)

    {module, _bytecode} =
      Enum.find(modules, fn {compiled_module, _bytecode} ->
        compiled_module == StructBackedTypes
      end)

    struct_value = module.new_struct(1)
    brand_module = Module.concat(module, UserID)

    assert struct_value.user_id == brand_module.new!(1)
    assert module.unwrap_struct(struct_value) == 1
  end

  test "keyword-style brand definition is rejected" do
    assert_raise ArgumentError,
                 ~r/keyword-style defbrand syntax is no longer supported/,
                 fn ->
                   Code.compile_string("""
                   defmodule LegacyKeywordStyleBrand do
                     use ExBrand

                     defbrand UserID, name: "User ID"
                   end
                   """)
                 end
  end

  test "legacy nested defbrand spec is rejected" do
    assert_raise ArgumentError,
                 ~r/legacy nested defbrand spec is no longer supported/,
                 fn ->
                   Code.compile_string("""
                   defmodule LegacyNestedDefbrandSpec do
                     use ExBrand

                     defbrand UserID, {{:integer, []}, [name: "User ID"]}
                   end
                   """)
                 end
  end

  test "standalone brand definition is rejected" do
    assert_raise ArgumentError,
                 ~r/does not accept options/,
                 fn ->
                   Code.compile_string("""
                   defmodule LegacyStandaloneBrand do
                     use ExBrand, :integer
                   end
                   """)
                 end
  end

  test "removed defbrands DSL is rejected" do
    assert_raise CompileError, fn ->
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule RemovedDefbrandsDslBrand do
          use ExBrand

          defbrands do
            defbrand PositiveUserID, :integer
          end
        end
        """)
      end)
    end
  end

  test "custom base module must export required callbacks" do
    assert_raise ArgumentError,
                 ~r/custom base module InvalidCustomBase must export type_ast\/1/,
                 fn ->
                   Code.compile_string("""
                   defmodule InvalidCustomBase do
                     def validate(_value, _opts), do: :ok
                     def ecto_type(_opts), do: :string
                   end

                   defmodule InvalidCustomBaseBrandContainer do
                     use ExBrand

                     defbrand InvalidCustomBaseBrand, InvalidCustomBase
                   end
                   """)
                 end
  end

  test "use ExBrand rejects options" do
    assert_raise ArgumentError, ~r/does not accept options/, fn ->
      Code.compile_string("""
      defmodule InvalidUseExBrandOption do
        use ExBrand, aliases: [UserID]
      end
      """)
    end
  end
end
