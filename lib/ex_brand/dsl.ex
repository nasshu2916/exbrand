defmodule ExBrand.DSL do
  @moduledoc """
  ExBrand の DSL 入力を正規化する内部モジュール。
  """

  alias ExBrand.Base

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
  base type 指定を ExBrand が扱える形に正規化する。
  """
  @spec expand_base!(term(), Macro.Env.t()) :: ExBrand.Base.spec()
  def expand_base!(base, env), do: base |> expand_base_ast(env) |> Base.normalize!()

  defp expand_base_ast({:__aliases__, _, _} = base, env), do: Macro.expand(base, env)

  defp expand_base_ast({:{}, _, [module_ast, opts]}, env) when is_list(opts) do
    {expand_base_ast(module_ast, env), opts}
  end

  defp expand_base_ast({module_ast, opts}, env) when is_list(opts) do
    {expand_base_ast(module_ast, env), opts}
  end

  defp expand_base_ast(base, _env), do: base
end
