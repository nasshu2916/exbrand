defmodule ExBrand.Adapter.JSON do
  @moduledoc false

  @spec build_jason_encoder_ast(module()) :: Macro.t()
  def build_jason_encoder_ast(module) do
    quote do
      if Code.ensure_loaded?(Jason.Encoder) do
        defimpl Jason.Encoder, for: unquote(module) do
          def encode(value, opts) do
            value
            |> unquote(module).unwrap()
            |> Jason.Encoder.encode(opts)
          end
        end
      end
    end
  end

  @spec build_json_encoder_ast(module()) :: Macro.t()
  def build_json_encoder_ast(module) do
    quote do
      if Code.ensure_loaded?(JSON.Encoder) do
        defimpl JSON.Encoder, for: unquote(module) do
          def encode(value, encoder) do
            value
            |> unquote(module).unwrap()
            |> JSON.Encoder.encode(encoder)
          end
        end
      end
    end
  end
end
