defmodule ExBrand do
  @moduledoc """
  プリミティブ値に意味的な型境界を与えるための DSL を提供する。
  """

  alias ExBrand.{Builder, DSL}

  @doc """
  ExBrand が生成した brand 値から raw 値を取り出す。

  ExBrand の brand でない値を渡した場合は `ArgumentError` を raise する。
  """
  @spec unwrap!(term()) :: term()
  def unwrap!(value) do
    case brand_module_for(value) do
      {:ok, module} -> module.unwrap(value)
      :error -> raise ArgumentError, "expected an ExBrand value, got: #{inspect(value)}"
    end
  end

  @doc """
  値が ExBrand の brand なら raw 値を返し、そうでなければそのまま返す。
  """
  @spec unwrap(term()) :: term()
  def unwrap(value) do
    case brand_module_for(value) do
      {:ok, module} -> module.unwrap(value)
      :error -> value
    end
  end

  @doc """
  ExBrand の DSL を導入する。
  """
  defmacro __using__(opts \\ []) do
    if opts == [] do
      quote do
        import ExBrand, only: [defbrand: 2]
      end
    else
      raise ArgumentError, "`use ExBrand` does not accept options"
    end
  end

  @doc """
  親モジュール配下に brand module を定義する。
  """
  defmacro defbrand(name, base_or_spec) do
    {base, opts} = extract_brand_spec(base_or_spec)
    expanded_base = DSL.expand_base!(base, __CALLER__)
    Builder.build_nested_brand(__CALLER__.module, name, expanded_base, opts)
  end

  @brand_option_keys [:validate, :error, :derive, :generator, :name]

  defp extract_brand_spec({{_base, _base_opts}, _brand_opts}) do
    raise ArgumentError,
          "legacy nested defbrand spec is no longer supported; use `defbrand Name, {Base, base_opts ++ brand_opts}`"
  end

  defp extract_brand_spec({base, opts}) when is_list(opts) do
    if Keyword.keyword?(opts) do
      {brand_opts, base_opts} = Keyword.split(opts, @brand_option_keys)
      normalized_base = if base_opts == [], do: base, else: {base, base_opts}
      {normalized_base, brand_opts}
    else
      raise ArgumentError,
            "base options must be a keyword list, got: #{inspect(opts)}"
    end
  end

  defp extract_brand_spec(base_or_opts) when is_list(base_or_opts) do
    if Keyword.keyword?(base_or_opts) do
      raise ArgumentError,
            "keyword-style defbrand syntax is no longer supported; use `defbrand UserID, :integer` or `defbrand UserID, {:integer, name: ...}` instead"
    else
      raise ArgumentError,
            "invalid defbrand spec: #{inspect(base_or_opts)}"
    end
  end

  defp extract_brand_spec(base), do: {base, []}

  defp brand_module_for(%module{} = value) when is_atom(module) do
    if function_exported?(module, :__meta__, 0) and
         function_exported?(module, :unwrap, 1) and
         module.brand?(value) do
      {:ok, module}
    else
      :error
    end
  end

  defp brand_module_for(_value), do: :error
end
