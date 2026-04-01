defmodule ExBrand.Adapter.Phoenix do
  @moduledoc false

  @spec build_param_ast(module()) :: Macro.t()
  def build_param_ast(module) do
    quote do
      if Code.ensure_loaded?(Phoenix.Param) do
        defimpl Phoenix.Param, for: unquote(module) do
          def to_param(value) do
            value
            |> unquote(module).unwrap()
            |> Phoenix.Param.to_param()
          end
        end
      end
    end
  end

  @spec build_html_safe_ast(module()) :: Macro.t()
  def build_html_safe_ast(module) do
    quote do
      if Code.ensure_loaded?(Phoenix.HTML.Safe) do
        defimpl Phoenix.HTML.Safe, for: unquote(module) do
          def to_iodata(value) do
            value
            |> unquote(module).unwrap()
            # Brand の内部表現ではなく raw 値側の protocol 実装へ委譲する。
            # credo:disable-for-next-line Credo.Check.Design.AliasUsage
            |> Phoenix.HTML.Safe.to_iodata()
          end
        end
      end
    end
  end
end
