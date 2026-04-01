defmodule ExBrand.Adapter.Ecto do
  @moduledoc false

  @spec build_ast(module()) :: Macro.t()
  def build_ast(module) do
    quote do
      if Code.ensure_loaded?(Ecto.Type) do
        @doc """
        この brand 用の `Ecto.Type` module を返す。
        """
        @spec ecto_type() :: module()
        def ecto_type, do: Module.concat(__MODULE__, EctoType)

        defmodule EctoType do
          use Ecto.Type

          @brand unquote(module)

          @impl true
          def type, do: ExBrand.Ecto.type_for(@brand)

          @impl true
          def cast(value), do: ExBrand.Ecto.cast(@brand, value)

          @impl true
          def load(value), do: ExBrand.Ecto.load(@brand, value)

          @impl true
          def dump(value), do: ExBrand.Ecto.dump(@brand, value)

          @impl true
          def embed_as(_format), do: :self

          @impl true
          def equal?(left, right), do: ExBrand.Ecto.equal?(@brand, left, right)
        end
      end

      if Code.ensure_loaded?(Ecto.ParameterizedType) do
        @doc """
        この brand 用の `Ecto.ParameterizedType` 定義を返す。
        """
        @spec ecto_parameterized_type() :: {module(), keyword()}
        def ecto_parameterized_type, do: {Module.concat(__MODULE__, EctoParameterizedType), []}

        defmodule EctoParameterizedType do
          use Ecto.ParameterizedType

          @brand unquote(module)

          @impl true
          def init(opts), do: opts

          @impl true
          def type(_params), do: ExBrand.Ecto.type_for(@brand)

          @impl true
          def cast(value, _params), do: ExBrand.Ecto.cast(@brand, value)

          @impl true
          def load(value, loader, _params) do
            ExBrand.Ecto.parameterized_load(@brand, value, loader)
          end

          @impl true
          def dump(value, dumper, _params) do
            ExBrand.Ecto.parameterized_dump(@brand, value, dumper)
          end

          @impl true
          def embed_as(_format, _params), do: :self

          @impl true
          def equal?(left, right, _params), do: ExBrand.Ecto.equal?(@brand, left, right)
        end
      end
    end
  end
end
