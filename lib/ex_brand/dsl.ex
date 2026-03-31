defmodule ExBrand.DSL do
  @moduledoc """
  ExBrand の DSL 入力を正規化する内部モジュール。
  """

  @doc """
  brand 定義の引数を正規化する。
  """
  @spec normalize_brand_args(term(), keyword() | [do: Macro.t()]) :: {term(), keyword()}
  def normalize_brand_args(base, opts) do
    case opts do
      [do: block] ->
        {base, extract_block_opts(block)}

      list when is_list(list) ->
        {base, list}
    end
  end

  @doc """
  `defbrands` block 内の brand 名が重複していないことを検証する。
  """
  @spec ensure_unique_brands!(Macro.t()) :: :ok
  def ensure_unique_brands!(block) do
    duplicates =
      block
      |> block_nodes()
      |> Enum.flat_map(&extract_brand_name/1)
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)

    case duplicates do
      [] ->
        :ok

      names ->
        joined = Enum.map_join(names, ", ", &inspect/1)
        raise ArgumentError, "duplicate brand definitions in defbrands: #{joined}"
    end
  end

  @doc """
  alias 指定を brand 名のリストへ正規化する。
  """
  @spec normalize_aliases(false | nil | [Macro.t() | atom()]) :: [atom()]
  def normalize_aliases(false), do: []
  def normalize_aliases(nil), do: []

  def normalize_aliases(aliases) when is_list(aliases) do
    Enum.map(aliases, &expand_name!/1)
  end

  def normalize_aliases(other) do
    raise ArgumentError,
          "aliases must be false or a list of brand names, got: #{inspect(other)}"
  end

  @doc """
  親モジュール配下の brand module に対する alias AST を構築する。
  """
  @spec build_aliases_for_parent(module(), [atom()]) :: [Macro.t()]
  def build_aliases_for_parent(parent, aliases) do
    Enum.map(aliases, fn name ->
      quote do
        alias unquote(Module.concat(parent, name))
      end
    end)
  end

  @doc """
  brand 名を module suffix として使える atom に展開する。
  """
  @spec expand_name!(Macro.t() | atom()) :: atom()
  def expand_name!({:__aliases__, _, parts}), do: Module.concat(parts)
  def expand_name!(name) when is_atom(name), do: name

  def expand_name!(other) do
    raise ArgumentError, "brand name must be an alias or atom, got: #{Macro.to_string(other)}"
  end

  @doc """
  base type を ExBrand が扱える値に制限する。
  """
  @spec expand_base!(:integer | :binary | :string) :: :integer | :binary | :string
  def expand_base!(base) when base in [:integer, :binary, :string], do: base

  def expand_base!(other) do
    raise ArgumentError, "unsupported base type: #{inspect(other)}"
  end

  defp block_nodes({:__block__, _, nodes}), do: nodes
  defp block_nodes(node), do: [node]

  defp extract_brand_name({:brand, _, [name, _base]}), do: [expand_name!(name)]
  defp extract_brand_name({:brand, _, [name, _base, _opts]}), do: [expand_name!(name)]
  defp extract_brand_name(_node), do: []

  defp extract_block_opts({:__block__, _, nodes}) do
    Enum.map(nodes, &block_node_to_opt/1)
  end

  defp extract_block_opts(node), do: [block_node_to_opt(node)]

  defp block_node_to_opt({key, _, [value]})
       when key in [:validate, :error, :derive, :generator] do
    {key, value}
  end

  defp block_node_to_opt(other) do
    raise ArgumentError, "unsupported brand DSL node: #{Macro.to_string(other)}"
  end
end
