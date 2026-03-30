defmodule ExBrand.DSLTest do
  use ExUnit.Case, async: true

  alias ExBrand.TestSupport.Fixtures.{AliasedTypes, SelectivelyAliasedTypes, Types}

  test "block DSL is supported" do
    assert Types.PositiveUserID.new(10) |> elem(0) == :ok
    assert Types.PositiveUserID.new(0) == {:error, :must_be_positive}
  end

  test "defbrands rejects duplicate brand names" do
    assert_raise ArgumentError, ~r/duplicate brand definitions in defbrands: UserID/, fn ->
      Code.compile_string("""
      defmodule DuplicateBrands do
        use ExBrand

        defbrands do
          brand UserID, :integer
          brand UserID, :binary
        end
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
