defmodule ExBrand.Adapter do
  @moduledoc """
  ExBrand の周辺統合を adapter 層として組み立てるための補助モジュール。

  Brand のコア実装から JSON/Phoenix/Ecto などの統合を分離し、
  将来的な別パッケージ化や有効化制御をしやすくするための境界として使う。
  """

  alias ExBrand.Adapter.{Ecto, JSON, Phoenix}

  @type ast_builder :: (module() -> Macro.t())

  @doc """
  Brand module の外側に追加する adapter AST の builder 群を返す。
  """
  @spec external_builders() :: [ast_builder()]
  def external_builders do
    [
      &JSON.build_json_encoder_ast/1,
      &JSON.build_jason_encoder_ast/1,
      &Phoenix.build_param_ast/1,
      &Phoenix.build_html_safe_ast/1
    ]
  end

  @doc """
  Brand module の内側に追加する adapter AST の builder 群を返す。
  """
  @spec module_builders() :: [ast_builder()]
  def module_builders do
    [&Ecto.build_ast/1]
  end

  @doc """
  指定した brand module に対する外側 adapter AST を返す。
  """
  @spec build_external_ast(module()) :: [Macro.t()]
  def build_external_ast(module) do
    Enum.map(external_builders(), & &1.(module))
  end

  @doc """
  指定した brand module に対する内側 adapter AST を返す。
  """
  @spec build_module_ast(module()) :: [Macro.t()]
  def build_module_ast(module) do
    Enum.map(module_builders(), & &1.(module))
  end
end
