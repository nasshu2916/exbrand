defmodule ExBrand.Schema do
  @moduledoc """
  `simple_schema` 風の宣言的な schema DSL と実行時バリデーションを提供する。

  主な制約は型指定の tuple にまとめて記述できる。

      field :age, {:integer, minimum: 18}
      field :email, {:string, format: :email}
      field :tags, {[{:string, min_length: 1}], min_items: 1}

  field option として渡していた `required:`, `default:`, `from:`, `validate:`, `error:`
  も後方互換のため引き続き利用できる。
  """

  alias ExBrand.Schema.{Codegen, Compiler, Definition, Runtime}

  @type scalar_schema() ::
          :any | :boolean | :integer | :number | :null | :string | :binary
  @type schema() ::
          scalar_schema()
          | module()
          | {schema(), keyword()}
          | [schema()]
          | %{atom() => schema()}
  @type schema_definition() :: schema()

  @doc """
  Schema DSL を導入する。
  """
  defmacro __using__(opts \\ []) do
    validate_use_opts!(opts)
    tolerant = Keyword.get(opts, :tolerant, false)

    quote bind_quoted: [tolerant: tolerant] do
      import ExBrand.Schema, only: [field: 2, field: 3]

      Module.register_attribute(__MODULE__, :ex_brand_schema_fields, accumulate: true)
      Module.put_attribute(__MODULE__, :ex_brand_schema_tolerant, tolerant)
      @before_compile ExBrand.Schema
    end
  end

  defp validate_use_opts!(opts) when is_list(opts) do
    invalid_keys =
      opts
      |> Keyword.keys()
      |> Enum.uniq()
      |> Enum.reject(&(&1 in [:tolerant]))

    case invalid_keys do
      [] ->
        :ok

      keys ->
        joined = Enum.map_join(keys, ", ", &inspect/1)
        raise ArgumentError, "unsupported use ExBrand.Schema options: #{joined}"
    end
  end

  @doc """
  schema field を 1 つ定義する。
  """
  defmacro field(name, schema, opts \\ []) do
    expanded_schema = Definition.expand_schema(schema, __CALLER__)

    quote do
      @ex_brand_schema_fields {
        unquote(Macro.escape(name)),
        unquote(Macro.escape(expanded_schema)),
        unquote(Macro.escape(opts))
      }
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    tolerant = Module.get_attribute(env.module, :ex_brand_schema_tolerant)

    field_definitions =
      env.module
      |> Module.get_attribute(:ex_brand_schema_fields)
      |> Enum.reverse()
      |> Enum.map(&Compiler.build_field_definition!/1)

    fields_ast =
      Enum.map(field_definitions, &Compiler.build_field_ast/1)

    schema_ast =
      quote do
        {
          %{unquote_splicing(fields_ast)},
          tolerant: unquote(tolerant)
        }
      end

    compiled_schema =
      Definition.compile_runtime_schema!({
        Map.new(field_definitions),
        tolerant: tolerant
      })

    root_validator_ast =
      Codegen.build_compiled_root_validator_ast(field_definitions, compiled_schema, tolerant)

    quote do
      @doc """
      schema 定義を返す。
      """
      @spec __schema__() :: ExBrand.Schema.schema_definition()
      def __schema__, do: unquote(schema_ast)

      @doc false
      def __compiled_schema__, do: unquote(Macro.escape(compiled_schema))

      unquote(root_validator_ast)

      @doc """
      入力値を schema 定義に従って検証し、正規化済みの値を返す。
      """
      @spec validate(term()) :: {:ok, term()} | {:error, term()}
      def validate(params),
        do: Runtime.with_runtime_config(fn -> __validate_compiled_root__(params) end)

      @doc """
      `validate/1` の bang 版。
      """
      @spec validate!(term()) :: term()
      def validate!(params),
        do: ExBrand.Schema.validate!(params, __MODULE__, __compiled_schema__())

      @doc """
      入力値が schema に適合するかを返す。
      """
      @spec valid?(term()) :: boolean()
      def valid?(params), do: match?({:ok, _result}, validate(params))
    end
  end

  @doc """
  schema 定義に従って値を検証する。
  """
  @spec validate(term(), schema_definition()) :: {:ok, term()} | {:error, term()}
  def validate(value, schema) do
    if Definition.compiled_runtime_schema?(schema) do
      Runtime.validate(value, schema)
    else
      raise ArgumentError,
            "schema must be compiled with ExBrand.Schema.compile!/1 before validate/2"
    end
  end

  @doc """
  schema 定義をコンパイル済み形式へ変換する。
  """
  @spec compile!(schema_definition()) :: term()
  def compile!(schema), do: Definition.compile_runtime_schema!(schema)

  @doc """
  schema 定義に従って値を検証し、失敗時は例外を送出する。
  """
  @spec validate!(term(), module(), schema_definition()) :: term()
  def validate!(value, module, schema) do
    case validate(value, schema) do
      {:ok, normalized_value} ->
        normalized_value

      {:error, reason} ->
        raise ArgumentError,
              "invalid schema value for #{inspect(module)}: #{inspect(reason)}"
    end
  end
end
