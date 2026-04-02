defmodule ExBrand do
  @moduledoc """
  プリミティブ値に意味的な型境界を与えるための DSL を提供する。

  主な使い方は 2 つある。

  1. 親モジュール配下に `defbrand` で定義する
  2. standalone module に `use ExBrand, ...` で直接定義する
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

  引数が空、もしくは `aliases:` のみの場合は DSL を import する。
  それ以外の引数は、そのモジュール自身を brand module として構築する。
  """
  defmacro __using__(opts \\ []) do
    cond do
      opts == [] ->
        build_dsl_import_ast(__CALLER__.module, false)

      is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) -- [:aliases] == [] ->
        build_dsl_import_ast(__CALLER__.module, Keyword.get(opts, :aliases, false))

      is_list(opts) and Keyword.keyword?(opts) ->
        raise ArgumentError,
              "standalone brand syntax no longer accepts keyword options; use `use ExBrand, :integer` or `use ExBrand, {:string, validate: ...}` instead"

      true ->
        base_or_spec = opts
        {base, brand_opts} = extract_brand_spec(base_or_spec)
        normalized_base = DSL.expand_base!(base, __CALLER__)

        Builder.build_brand_inline(
          __CALLER__.module,
          Keyword.put(brand_opts, :base, normalized_base)
        )
    end
  end

  @doc """
  親モジュール配下に brand module を 1 つ定義する。
  """
  defmacro defbrand(name, base_or_spec) do
    {base, opts} = extract_brand_spec(base_or_spec)
    expanded_base = DSL.expand_base!(base, __CALLER__)
    Builder.build_nested_brand(__CALLER__.module, name, expanded_base, opts)
  end

  @brand_option_keys [:validate, :error, :derive, :generator, :name]

  defp extract_brand_spec({{base, base_opts}, brand_opts})
       when is_list(base_opts) and is_list(brand_opts) do
    if Keyword.keyword?(base_opts) and Keyword.keyword?(brand_opts) and
         Enum.all?(Keyword.keys(brand_opts), &(&1 in @brand_option_keys)) do
      {{base, base_opts}, brand_opts}
    else
      {{{base, base_opts}, brand_opts}, []}
    end
  end

  defp extract_brand_spec({base, opts}) when is_list(opts) do
    if Keyword.keyword?(opts) and Enum.all?(Keyword.keys(opts), &(&1 in @brand_option_keys)) do
      {base, opts}
    else
      {{base, opts}, []}
    end
  end

  defp extract_brand_spec(base), do: {base, []}

  defp build_dsl_import_ast(parent_module, aliases) do
    normalized_aliases = DSL.normalize_aliases(aliases)
    alias_asts = DSL.build_aliases_for_parent(parent_module, normalized_aliases)

    quote do
      unquote_splicing(alias_asts)
      import ExBrand, only: [defbrand: 2]
    end
  end

  defp brand_module_for(%module{} = value) when is_atom(module) do
    if function_exported?(module, :__meta__, 0) and
         function_exported?(module, :unwrap, 1) and
         module.is_brand?(value) do
      {:ok, module}
    else
      :error
    end
  end

  defp brand_module_for(_value), do: :error
end
