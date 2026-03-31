defmodule ExBrand do
  @moduledoc """
  プリミティブ値に意味的な型境界を与えるための DSL を提供する。

  主な使い方は 2 つある。

  1. 親モジュール配下に `defbrand` / `defbrands` で定義する
  2. standalone module に `use ExBrand, base: ...` で直接定義する
  """

  alias ExBrand.{Builder, DSL}

  @doc """
  ExBrand が生成した brand 値から raw 値を取り出す。

  ExBrand の brand でない値を渡した場合は `ArgumentError` を raise する。
  """
  @spec unwrap(term()) :: term()
  def unwrap(value) do
    case brand_module_for(value) do
      {:ok, module} -> module.unwrap(value)
      :error -> raise ArgumentError, "expected an ExBrand value, got: #{inspect(value)}"
    end
  end

  @doc """
  値が ExBrand の brand なら raw 値を返し、そうでなければそのまま返す。
  """
  @spec maybe_unwrap(term()) :: term()
  def maybe_unwrap(value) do
    case brand_module_for(value) do
      {:ok, module} -> module.unwrap(value)
      :error -> value
    end
  end

  @doc """
  ExBrand の DSL もしくは低レベル API を導入する。

  `base:` がある場合は、そのモジュール自身を brand module として構築する。
  `base:` がない場合は、`defbrand` / `defbrands` / `brand` を import する。
  """
  defmacro __using__(opts \\ []) do
    if Keyword.has_key?(opts, :base) do
      Builder.build_brand_inline(__CALLER__.module, opts)
    else
      aliases = DSL.normalize_aliases(Keyword.get(opts, :aliases, false))
      alias_asts = DSL.build_aliases_for_parent(__CALLER__.module, aliases)

      quote do
        unquote_splicing(alias_asts)
        import ExBrand, only: [defbrand: 2, defbrand: 3, defbrands: 1, brand: 2, brand: 3]
      end
    end
  end

  @doc """
  親モジュール配下に brand module を 1 つ定義する。
  """
  defmacro defbrand(name, base) do
    Builder.build_nested_brand(__CALLER__.module, name, base, [])
  end

  @doc """
  親モジュール配下に option 付きの brand module を 1 つ定義する。
  """
  defmacro defbrand(name, base, opts) do
    {normalized_base, normalized_opts} = DSL.normalize_brand_args(base, opts)
    Builder.build_nested_brand(__CALLER__.module, name, normalized_base, normalized_opts)
  end

  @doc """
  複数の brand 定義を 1 つの block にまとめる。

  block 内では `brand` を使う。
  """
  defmacro defbrands(do: block) do
    DSL.ensure_unique_brands!(block)

    quote do
      unquote(block)
    end
  end

  @doc """
  `defbrands` block の中で brand module を 1 つ定義する。
  """
  defmacro brand(name, base) do
    Builder.build_nested_brand(__CALLER__.module, name, base, [])
  end

  @doc """
  `defbrands` block の中で option 付きの brand module を 1 つ定義する。
  """
  defmacro brand(name, base, opts) do
    {normalized_base, normalized_opts} = DSL.normalize_brand_args(base, opts)
    Builder.build_nested_brand(__CALLER__.module, name, normalized_base, normalized_opts)
  end

  defp brand_module_for(%module{} = value) when is_atom(module) do
    if function_exported?(module, :__brand__, 0) and
         function_exported?(module, :unwrap, 1) and
         module.is_brand?(value) do
      {:ok, module}
    else
      :error
    end
  end

  defp brand_module_for(_value), do: :error
end
