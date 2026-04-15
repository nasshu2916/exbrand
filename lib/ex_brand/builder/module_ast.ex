defmodule ExBrand.Builder.ModuleAst do
  @moduledoc false

  @spec build_brand_moduledoc_ast(module()) :: Macro.t()
  def build_brand_moduledoc_ast(module) do
    quote do
      @moduledoc """
      `#{inspect(unquote(module))}` は ExBrand によって生成された brand module である。

      raw 値の生成には `new/1` または `new!/1` を使い、
      Web 境界の受け入れには `cast/1` または `cast!/1` を使い、
      取り出しには `unwrap/1` を使う。
      """
    end
  end

  @spec build_derive_ast(nil | [term()]) :: Macro.t()
  def build_derive_ast(nil) do
    quote do
    end
  end

  def build_derive_ast(derive) do
    quote do
      @derive unquote(derive)
    end
  end

  @spec signature_struct_ast(boolean()) :: Macro.t()
  def signature_struct_ast(true) do
    quote do
      @enforce_keys [:__value__, :__signature__]
      defstruct [:__value__, :__signature__]
    end
  end

  def signature_struct_ast(false) do
    quote do
      @enforce_keys [:__value__]
      defstruct [:__value__]
    end
  end

  @spec build_types_ast(Macro.t(), boolean()) :: Macro.t()
  def build_types_ast(raw_type, signature_verification) do
    quote do
      @type raw() :: unquote(raw_type)
      @type meta() :: %{
              module: module(),
              name: String.t(),
              base: ExBrand.Base.spec(),
              validator: function() | nil,
              generator: term() | nil,
              error: term() | nil
            }
      unquote(signature_type_ast(signature_verification))
    end
  end

  @spec build_brand_attributes_ast(
          ExBrand.Base.spec(),
          term(),
          String.t(),
          boolean(),
          binary() | nil
        ) ::
          Macro.t()
  def build_brand_attributes_ast(base, error, name, signature_verification, secret) do
    quote do
      @base unquote(base)
      @error_reason unquote(error)
      @brand_name unquote(name)
      @signature_verification unquote(signature_verification)

      if @signature_verification do
        @brand_secret unquote(secret)
      end
    end
  end

  @spec build_internal_helpers_ast(term(), term(), boolean()) :: Macro.t()
  def build_internal_helpers_ast(validate, generator, signature_verification) do
    quote do
      defp __validator__, do: unquote(validate)
      defp __generator__, do: unquote(generator)

      unquote(signature_helpers_ast(signature_verification))
    end
  end

  @spec build_brand_runtime_api_ast() :: Macro.t()
  def build_brand_runtime_api_ast do
    quote do
      @doc """
      brand 値から raw 値を明示的に取り出す。
      """
      @spec unwrap(t()) :: raw()
      def unwrap(%__MODULE__{__value__: value} = brand) do
        if __valid_signature__(brand) do
          value
        else
          raise ArgumentError, "invalid forged or mutated brand value for #{__name__()}"
        end
      end

      @doc """
      property-based testing 向けの generator を返す。

      `generator:` に 0 引数関数を渡した場合は、その場で評価する。
      """
      @spec gen() :: term()
      def gen, do: ExBrand.Builder.resolve_generator(__generator__())

      @doc """
      渡された値が当該 brand の struct かを返す。
      """
      @spec brand?(term()) :: boolean()
      def brand?(%__MODULE__{} = brand), do: __valid_signature__(brand)
      def brand?(_), do: false
    end
  end

  @spec build_reflection_api_ast() :: Macro.t()
  def build_reflection_api_ast do
    quote do
      @doc """
      この brand の base type を返す。
      """
      @spec __base__() :: ExBrand.Base.spec()
      def __base__, do: @base

      @doc """
      この brand の表示名を返す。
      """
      @spec __name__() :: String.t()
      def __name__, do: @brand_name

      @doc """
      この brand の定義メタデータを返す。
      """
      @spec __meta__() :: meta()
      def __meta__ do
        %{
          module: __MODULE__,
          name: @brand_name,
          base: @base,
          validator: __validator__(),
          generator: __generator__(),
          error: @error_reason
        }
      end
    end
  end

  @spec build_protocol_impls(module()) :: [Macro.t()]
  def build_protocol_impls(module) do
    [
      build_inspect_impl(module),
      build_string_chars_impl(module)
    ]
  end

  @spec build_brand_struct_from_value_ast(boolean(), Macro.t()) :: Macro.t()
  def build_brand_struct_from_value_ast(true, value_ast) do
    quote do
      %__MODULE__{__value__: unquote(value_ast), __signature__: __sign__(unquote(value_ast))}
    end
  end

  def build_brand_struct_from_value_ast(false, value_ast) do
    quote do
      %__MODULE__{__value__: unquote(value_ast)}
    end
  end

  @spec build_brand_struct_ast(boolean(), Macro.t()) :: Macro.t()
  def build_brand_struct_ast(true, normalized_value_ast) do
    quote do
      %__MODULE__{
        __value__: unquote(normalized_value_ast),
        __signature__: __sign__(unquote(normalized_value_ast))
      }
    end
  end

  def build_brand_struct_ast(false, normalized_value_ast) do
    quote do
      %__MODULE__{__value__: unquote(normalized_value_ast)}
    end
  end

  @spec build_inspect_impl(module()) :: Macro.t()
  defp build_inspect_impl(module) do
    quote do
      defimpl Inspect, for: unquote(module) do
        import Inspect.Algebra

        def inspect(value, opts) do
          concat([
            "#",
            unquote(module).__name__(),
            "<",
            to_doc(unquote(module).unwrap(value), opts),
            ">"
          ])
        end
      end
    end
  end

  @spec build_string_chars_impl(module()) :: Macro.t()
  defp build_string_chars_impl(module) do
    quote do
      defimpl String.Chars, for: unquote(module) do
        def to_string(value) do
          value
          |> unquote(module).unwrap()
          |> Kernel.to_string()
        end
      end
    end
  end

  @spec signature_type_ast(boolean()) :: Macro.t()
  defp signature_type_ast(true) do
    quote do
      @opaque t() :: %__MODULE__{__value__: raw(), __signature__: integer()}
    end
  end

  defp signature_type_ast(false) do
    quote do
      @opaque t() :: %__MODULE__{__value__: raw()}
    end
  end

  @spec signature_helpers_ast(boolean()) :: Macro.t()
  defp signature_helpers_ast(true) do
    quote do
      defp __sign__(value), do: :erlang.phash2({@brand_secret, value})

      defp __valid_signature__(%__MODULE__{__value__: value, __signature__: signature}) do
        signature == __sign__(value)
      end
    end
  end

  defp signature_helpers_ast(false) do
    quote do
      defp __valid_signature__(%__MODULE__{}), do: true
    end
  end
end
