defmodule ExBrand do
  defmacro __using__(opts \\ []) do
    case opts do
      [] ->
        quote do
          import ExBrand, only: [defbrand: 2, defbrand: 3, defbrands: 1, brand: 2, brand: 3]
        end

      _ ->
        build_brand_module(__CALLER__.module, opts)
    end
  end

  defmacro defbrand(name, base) do
    build_nested_brand(__CALLER__.module, name, base, [])
  end

  defmacro defbrand(name, base, opts) do
    {normalized_base, normalized_opts} = normalize_brand_args(base, opts)
    build_nested_brand(__CALLER__.module, name, normalized_base, normalized_opts)
  end

  defmacro defbrands(do: block) do
    quote do
      unquote(block)
    end
  end

  defmacro brand(name, base) do
    build_nested_brand(__CALLER__.module, name, base, [])
  end

  defmacro brand(name, base, opts) do
    {normalized_base, normalized_opts} = normalize_brand_args(base, opts)
    build_nested_brand(__CALLER__.module, name, normalized_base, normalized_opts)
  end

  defp normalize_brand_args(base, opts) do
    case opts do
      [do: block] ->
        {base, extract_block_opts(block)}

      list when is_list(list) ->
        {base, list}
    end
  end

  defp extract_block_opts({:__block__, _, nodes}) do
    Enum.map(nodes, &block_node_to_opt/1)
  end

  defp extract_block_opts(node), do: [block_node_to_opt(node)]

  defp block_node_to_opt({key, _, [value]}) when key in [:validate, :error, :derive] do
    {key, value}
  end

  defp block_node_to_opt(other) do
    raise ArgumentError, "unsupported brand DSL node: #{Macro.to_string(other)}"
  end

  defp build_nested_brand(parent, name, base, opts) do
    module = Module.concat(parent, expand_name!(name))
    build_brand_module(module, Keyword.put(opts, :base, expand_base!(base)))
  end

  defp expand_name!({:__aliases__, _, parts}), do: Module.concat(parts)
  defp expand_name!(name) when is_atom(name), do: name

  defp expand_name!(other) do
    raise ArgumentError, "brand name must be an alias or atom, got: #{Macro.to_string(other)}"
  end

  defp expand_base!(base) when base in [:integer, :binary, :string], do: base

  defp expand_base!(other) do
    raise ArgumentError, "unsupported base type: #{inspect(other)}"
  end

  defp build_brand_module(module, opts) do
    base = Keyword.fetch!(opts, :base)
    raw_type = raw_type_ast(base)
    validate = Keyword.get(opts, :validate)
    error = Keyword.get(opts, :error)
    derive = normalize_derive(Keyword.get(opts, :derive))
    inspect_name = inspect_name(module)

    quote do
      defmodule unquote(module) do
        @enforce_keys [:__value__]
        defstruct [:__value__]

        if unquote(derive) do
          @derive unquote(derive)
        end

        @type raw() :: unquote(raw_type)
        @opaque t() :: %__MODULE__{__value__: raw()}

        @base unquote(base)
        @error_reason unquote(error)

        defp __validator__, do: unquote(validate)

        @spec new(raw()) :: {:ok, t()} | {:error, term()}
        def new(value) do
          case ExBrand.Validator.validate(value, @base, __validator__(), @error_reason) do
            :ok -> {:ok, %__MODULE__{__value__: value}}
            {:error, reason} -> {:error, reason}
          end
        end

        @spec new!(raw()) :: t()
        def new!(value) do
          case new(value) do
            {:ok, brand} ->
              brand

            {:error, reason} ->
              raise ExBrand.Error, reason: reason, module: __MODULE__, value: value
          end
        end

        @spec unwrap(t()) :: raw()
        def unwrap(%__MODULE__{__value__: value}), do: value

        @spec valid?(raw()) :: boolean()
        def valid?(value) do
          match?({:ok, _brand}, new(value))
        end

        @spec is_brand?(term()) :: boolean()
        def is_brand?(%__MODULE__{}), do: true
        def is_brand?(_), do: false

        @spec __base__() :: :integer | :binary | :string
        def __base__, do: @base
      end

      defimpl Inspect, for: unquote(module) do
        import Inspect.Algebra

        def inspect(%unquote(module){__value__: value}, opts) do
          concat(["#", unquote(inspect_name), "<", to_doc(value, opts), ">"])
        end
      end
    end
  end

  defp raw_type_ast(:integer), do: quote(do: integer())
  defp raw_type_ast(:binary), do: quote(do: binary())
  defp raw_type_ast(:string), do: quote(do: String.t())

  defp normalize_derive(nil), do: nil

  defp normalize_derive(derive) when is_list(derive) do
    derive
    |> List.wrap()
    |> Enum.reject(&(&1 == Inspect))
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp inspect_name(module) do
    module
    |> Module.split()
    |> List.last()
  end
end
