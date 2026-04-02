defmodule ExBrand.DSLTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.Fixtures.{AliasedTypes, SelectivelyAliasedTypes}

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

  test "keyword-style brand definition is rejected" do
    assert_raise ArgumentError, ~r/unsupported base type/, fn ->
      Code.compile_string("""
      defmodule LegacyKeywordStyleBrand do
        use ExBrand

        defbrand UserID, name: "User ID"
      end
      """)
    end
  end

  test "keyword-style standalone brand definition is rejected" do
    assert_raise ArgumentError,
                 ~r/standalone brand syntax no longer accepts keyword options/,
                 fn ->
                   Code.compile_string("""
                   defmodule LegacyKeywordStandaloneBrand do
                     use ExBrand, base: :integer
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

                   defmodule InvalidCustomBaseBrand do
                     use ExBrand, InvalidCustomBase
                   end
                   """)
                 end
  end

  test "aliases list generates helper aliases in the parent module" do
    assert AliasedTypes.user_id_base() == :integer
    assert AliasedTypes.order_id_base() == :integer
  end

  test "aliases can be limited to selected brand names" do
    assert SelectivelyAliasedTypes.user_id_base() == :integer
  end

  test "selected aliases do not expose non-listed brand names" do
    modules =
      capture_compile_stderr(fn ->
        Code.compile_string("""
        defmodule InvalidAliasSelection do
          use ExBrand, aliases: [UserID]

          defbrand UserID, :integer
          defbrand OrderID, :integer

          def order_id_base, do: OrderID.__base__()
        end
        """)
      end)

    {module, _bytecode} =
      Enum.find(modules, fn {compiled_module, _bytecode} ->
        compiled_module == InvalidAliasSelection
      end)

    assert_raise UndefinedFunctionError, fn ->
      module.order_id_base()
    end
  end

  test "aliases option rejects unsupported shapes" do
    assert_raise ArgumentError,
                 ~r/aliases must be false or a list of brand names/,
                 fn ->
                   Code.compile_string("""
                   defmodule InvalidAliasesOption do
                     use ExBrand, aliases: true
                   end
                   """)
                 end
  end

  defp capture_compile_stderr(fun) do
    parent = self()
    ref = make_ref()

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      send(parent, {ref, fun.()})
    end)

    receive do
      {^ref, result} -> result
    end
  end
end
