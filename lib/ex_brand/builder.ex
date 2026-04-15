defmodule ExBrand.Builder do
  @moduledoc """
  ExBrand の brand module を生成する内部モジュール。
  """

  alias ExBrand.Adapter
  alias ExBrand.Builder.{Context, ModuleAst}
  alias ExBrand.DSL

  @doc false
  @spec resolve_generator(term()) :: term()
  def resolve_generator(generator) when is_function(generator, 0), do: generator.()
  def resolve_generator(generator), do: generator

  @doc """
  親モジュール配下に生成する brand module の AST を返す。
  """
  @spec build_nested_brand(module(), Macro.t() | atom(), ExBrand.Base.spec(), keyword()) ::
          Macro.t()
  def build_nested_brand(parent, name, base, opts) do
    module = Module.concat(parent, DSL.expand_name!(name))
    build_brand_module(module, Keyword.put(opts, :base, base))
  end

  @spec build_brand_module(module(), keyword()) :: Macro.t()
  defp build_brand_module(module, opts) do
    quote do
      defmodule unquote(module) do
        unquote(build_brand_body(module, opts))
      end

      unquote_splicing(ModuleAst.build_protocol_impls(module))
      unquote_splicing(Adapter.build_external_ast(module))
    end
  end

  @spec build_brand_body(module(), keyword()) :: Macro.t()
  defp build_brand_body(module, opts) do
    ast_context = Context.from_opts(module, opts)

    quote do
      (unquote_splicing(build_brand_ast_parts(ast_context)))
    end
  end

  @spec build_brand_ast_parts(Context.t()) :: [Macro.t()]
  defp build_brand_ast_parts(%Context{} = ast_context) do
    [
      ModuleAst.build_brand_moduledoc_ast(ast_context.module),
      ModuleAst.build_derive_ast(ast_context.derive),
      ModuleAst.signature_struct_ast(ast_context.signature_verification),
      ModuleAst.build_types_ast(ast_context.raw_type, ast_context.signature_verification),
      ModuleAst.build_brand_attributes_ast(
        ast_context.base,
        ast_context.error,
        ast_context.name,
        ast_context.signature_verification,
        ast_context.secret
      ),
      ModuleAst.build_internal_helpers_ast(
        ast_context.validate,
        ast_context.generator,
        ast_context.signature_verification
      ),
      build_constructor_api_ast(ast_context),
      ModuleAst.build_brand_runtime_api_ast(),
      ModuleAst.build_reflection_api_ast(),
      Adapter.build_module_ast(ast_context.module)
    ]
    |> List.flatten()
  end

  @spec build_constructor_api_ast(Context.t()) :: Macro.t()
  defp build_constructor_api_ast(%Context{
         base: base,
         validate: validate,
         signature_verification: signature_verification
       }) do
    new_ast = build_optimized_new_ast(base, validate, signature_verification)

    unsafe_struct_ast =
      ModuleAst.build_brand_struct_from_value_ast(signature_verification, quote(do: value))

    quote do
      unquote(new_ast)

      @doc """
      raw 値から検証を行わずに brand 値を生成する。

      高信頼な境界内でのみ利用すること。
      """
      @spec unsafe_new(raw()) :: {:ok, t()}
      def unsafe_new(value) do
        {:ok, unquote(unsafe_struct_ast)}
      end

      @doc """
      `new/1` の bang 版。

      生成に失敗した場合は `ExBrand.Error` を raise する。
      """
      @spec new!(raw()) :: t()
      def new!(value) do
        case new(value) do
          {:ok, brand} ->
            brand

          {:error, reason} ->
            raise ExBrand.Error, reason: reason, module: __MODULE__, value: value
        end
      end
    end
  end

  # Base type check is inlined as a guard, eliminating runtime calls on the fast path.
  @spec build_optimized_new_ast(ExBrand.Base.spec(), term(), boolean()) :: Macro.t()
  defp build_optimized_new_ast(base, nil, signature_verification)
       when base in [:integer, :string, :binary] do
    guard = builtin_guard_ast(base)

    struct_ast =
      ModuleAst.build_brand_struct_from_value_ast(signature_verification, quote(do: value))

    quote do
      @doc """
      raw 値から brand 値を生成する。

      validator が正規化値を返した場合は、その値を内部に保持する。
      """
      @spec new(raw()) :: {:ok, t()} | {:error, term()}
      def new(value) when unquote(guard) do
        {:ok, unquote(struct_ast)}
      end

      def new(_value), do: {:error, :invalid_type}
    end
  end

  @spec build_optimized_new_ast(ExBrand.Base.spec(), term(), boolean()) :: Macro.t()
  defp build_optimized_new_ast(base, _validate, signature_verification)
       when base in [:integer, :string, :binary] do
    guard = builtin_guard_ast(base)

    struct_ast =
      ModuleAst.build_brand_struct_ast(signature_verification, quote(do: normalized_value))

    quote do
      @doc """
      raw 値から brand 値を生成する。

      validator が正規化値を返した場合は、その値を内部に保持する。
      """
      @spec new(raw()) :: {:ok, t()} | {:error, term()}
      def new(value) when unquote(guard) do
        case ExBrand.Validator.validate_custom(
               value,
               unquote(base),
               __validator__(),
               @error_reason
             ) do
          {:ok, normalized_value} ->
            {:ok, unquote(struct_ast)}

          {:error, reason} ->
            {:error, reason}
        end
      end

      def new(_value), do: {:error, :invalid_type}
    end
  end

  @spec build_optimized_new_ast(ExBrand.Base.spec(), term(), boolean()) :: Macro.t()
  defp build_optimized_new_ast(_base, _validate, signature_verification) do
    struct_ast =
      ModuleAst.build_brand_struct_ast(signature_verification, quote(do: normalized_value))

    quote do
      @doc """
      raw 値から brand 値を生成する。

      validator が正規化値を返した場合は、その値を内部に保持する。
      """
      @spec new(raw()) :: {:ok, t()} | {:error, term()}
      def new(value) do
        case ExBrand.Validator.validate(value, @base, __validator__(), @error_reason) do
          {:ok, normalized_value} ->
            {:ok, unquote(struct_ast)}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @spec builtin_guard_ast(:integer | :string | :binary) :: Macro.t()
  defp builtin_guard_ast(:integer), do: quote(do: is_integer(value))
  defp builtin_guard_ast(:string), do: quote(do: is_binary(value))
  defp builtin_guard_ast(:binary), do: quote(do: is_binary(value))
end
