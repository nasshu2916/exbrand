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

  alias ExBrand.Schema.{Compiler, Definition, Runtime}

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
      build_compiled_root_validator_ast(field_definitions, compiled_schema, tolerant)

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
      def validate(params), do: __validate_compiled_root__(params)

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

  defp build_compiled_root_validator_ast(
         field_definitions,
         {:compiled, :map, compiled_fields, _opts},
         tolerant
       ) do
    ordered_compiled_fields =
      Enum.map(field_definitions, fn {name, _schema} ->
        {name, Map.fetch!(compiled_fields, name)}
      end)

    build_compiled_map_validator_ast(ordered_compiled_fields, tolerant)
  end

  defp build_compiled_root_validator_ast(
         _field_definitions,
         {:compiled, kind, data, opts},
         _tolerant
       ) do
    runtime_module = Runtime

    quote do
      defp __validate_compiled_root__(params) do
        unquote(runtime_module).validate_compiled_root(
          params,
          unquote(kind),
          unquote(Macro.escape(data)),
          unquote(Macro.escape(opts))
        )
      end
    end
  end

  defp build_compiled_map_validator_ast(ordered_compiled_fields, tolerant) do
    runtime_module = Runtime

    field_plans =
      ordered_compiled_fields
      |> Enum.with_index()
      |> Enum.map(fn {{name, field}, index} ->
        collect_name = String.to_atom("__validate_field_collect_#{index}__")
        fail_name = String.to_atom("__validate_field_fail_#{index}__")

        {collect_def, fail_def} =
          build_collect_and_fail_field_defs(name, field, collect_name, fail_name, tolerant)

        %{
          collect_def: collect_def,
          collect_name: collect_name,
          fail_def: fail_def,
          fail_name: fail_name
        }
      end)

    collect_field_defs = Enum.map(field_plans, & &1.collect_def)
    collect_field_fun_names = Enum.map(field_plans, & &1.collect_name)
    fail_field_defs = Enum.map(field_plans, & &1.fail_def)
    fail_field_fun_names = Enum.map(field_plans, & &1.fail_name)

    collect_root_ast = build_map_collect_root_ast(collect_field_fun_names, tolerant)
    fail_root_ast = build_map_fail_root_ast(fail_field_fun_names, tolerant)

    quote do
      unquote_splicing(collect_field_defs)
      unquote_splicing(fail_field_defs)
      unquote(collect_root_ast)
      unquote(fail_root_ast)

      defp __validate_compiled_root__(params) do
        if unquote(runtime_module).schema_fail_fast_enabled?() do
          __validate_root_map_fail_fast__(params)
        else
          __validate_root_map_collect__(params)
        end
      end
    end
  end

  defp build_collect_and_fail_field_defs(name, field, collect_name, fail_name, tolerant) do
    runtime_module = Runtime

    %{
      lookup: lookup,
      schema: schema,
      schema_without_opts: schema_without_opts,
      opts: field_opts
    } = field

    {schema_kind, schema_data_ast, schema_opts_ast} = compiled_parts(schema)
    missing_schema_ast = Macro.escape(schema_without_opts)
    lookup_ast = Macro.escape(lookup)
    field_opts_ast = Macro.escape(field_opts)

    collect_ast =
      if tolerant do
        quote do
          defp unquote(collect_name)(params, normalized, errors) do
            case unquote(runtime_module).fetch_compiled_field_value(params, unquote(lookup_ast)) do
              {:ok, field_value, _used_key} ->
                case unquote(runtime_module).validate_compiled_root(
                       field_value,
                       unquote(schema_kind),
                       unquote(schema_data_ast),
                       unquote(schema_opts_ast)
                     ) do
                  {:ok, normalized_value} ->
                    {Map.put(normalized, unquote(name), normalized_value), errors}

                  {:error, reason} ->
                    next_errors =
                      unquote(runtime_module).accumulate_error(errors, unquote(name), reason)

                    {normalized, next_errors}
                end

              :missing ->
                case unquote(runtime_module).resolve_missing_field(
                       unquote(missing_schema_ast),
                       unquote(field_opts_ast)
                     ) do
                  {:ok, default_or_nil} ->
                    {Map.put(normalized, unquote(name), default_or_nil), errors}

                  {:error, reason} ->
                    next_errors =
                      unquote(runtime_module).accumulate_error(errors, unquote(name), reason)

                    {normalized, next_errors}
                end
            end
          end
        end
      else
        quote do
          defp unquote(collect_name)(params, normalized, errors, consumed_keys) do
            case unquote(runtime_module).fetch_compiled_field_value(params, unquote(lookup_ast)) do
              {:ok, field_value, used_key} ->
                case unquote(runtime_module).validate_compiled_root(
                       field_value,
                       unquote(schema_kind),
                       unquote(schema_data_ast),
                       unquote(schema_opts_ast)
                     ) do
                  {:ok, normalized_value} ->
                    {Map.put(normalized, unquote(name), normalized_value), errors,
                     MapSet.put(consumed_keys, used_key)}

                  {:error, reason} ->
                    next_errors =
                      unquote(runtime_module).accumulate_error(errors, unquote(name), reason)

                    {normalized, next_errors, MapSet.put(consumed_keys, used_key)}
                end

              :missing ->
                case unquote(runtime_module).resolve_missing_field(
                       unquote(missing_schema_ast),
                       unquote(field_opts_ast)
                     ) do
                  {:ok, default_or_nil} ->
                    {Map.put(normalized, unquote(name), default_or_nil), errors, consumed_keys}

                  {:error, reason} ->
                    next_errors =
                      unquote(runtime_module).accumulate_error(errors, unquote(name), reason)

                    {normalized, next_errors, consumed_keys}
                end
            end
          end
        end
      end

    fail_ast =
      if tolerant do
        quote do
          defp unquote(fail_name)(params, normalized) do
            case unquote(runtime_module).fetch_compiled_field_value(params, unquote(lookup_ast)) do
              {:ok, field_value, _used_key} ->
                case unquote(runtime_module).validate_compiled_root(
                       field_value,
                       unquote(schema_kind),
                       unquote(schema_data_ast),
                       unquote(schema_opts_ast)
                     ) do
                  {:ok, normalized_value} ->
                    {:ok, Map.put(normalized, unquote(name), normalized_value)}

                  {:error, reason} ->
                    {:error, %{unquote(name) => reason}}
                end

              :missing ->
                case unquote(runtime_module).resolve_missing_field(
                       unquote(missing_schema_ast),
                       unquote(field_opts_ast)
                     ) do
                  {:ok, default_or_nil} ->
                    {:ok, Map.put(normalized, unquote(name), default_or_nil)}

                  {:error, reason} ->
                    {:error, %{unquote(name) => reason}}
                end
            end
          end
        end
      else
        quote do
          defp unquote(fail_name)(params, normalized, consumed_keys) do
            case unquote(runtime_module).fetch_compiled_field_value(params, unquote(lookup_ast)) do
              {:ok, field_value, used_key} ->
                case unquote(runtime_module).validate_compiled_root(
                       field_value,
                       unquote(schema_kind),
                       unquote(schema_data_ast),
                       unquote(schema_opts_ast)
                     ) do
                  {:ok, normalized_value} ->
                    {:ok, Map.put(normalized, unquote(name), normalized_value),
                     MapSet.put(consumed_keys, used_key)}

                  {:error, reason} ->
                    {:error, %{unquote(name) => reason}}
                end

              :missing ->
                case unquote(runtime_module).resolve_missing_field(
                       unquote(missing_schema_ast),
                       unquote(field_opts_ast)
                     ) do
                  {:ok, default_or_nil} ->
                    {:ok, Map.put(normalized, unquote(name), default_or_nil), consumed_keys}

                  {:error, reason} ->
                    {:error, %{unquote(name) => reason}}
                end
            end
          end
        end
      end

    {collect_ast, fail_ast}
  end

  defp build_map_collect_root_ast(field_fun_names, true) do
    step_asts =
      Enum.map(field_fun_names, fn field_fun_name ->
        quote do
          {normalized, errors} = unquote(field_fun_name)(params, normalized, errors)
        end
      end)

    quote do
      defp __validate_root_map_collect__(params) when is_map(params) do
        {normalized, errors} = {%{}, nil}
        unquote_splicing(step_asts)

        if is_nil(errors), do: {:ok, normalized}, else: {:error, errors}
      end

      defp __validate_root_map_collect__(_params), do: {:error, :invalid_type}
    end
  end

  defp build_map_collect_root_ast(field_fun_names, false) do
    runtime_module = Runtime
    definition_module = Definition

    step_asts =
      Enum.map(field_fun_names, fn field_fun_name ->
        quote do
          {normalized, errors, consumed_keys} =
            unquote(field_fun_name)(params, normalized, errors, consumed_keys)
        end
      end)

    quote do
      defp __validate_root_map_collect__(params) when is_map(params) do
        {normalized, errors, consumed_keys} = {%{}, nil, MapSet.new()}
        unquote_splicing(step_asts)

        errors =
          case unquote(runtime_module).extra_fields(params, consumed_keys) do
            [] ->
              errors

            fields ->
              reason = Enum.sort(fields)
              key = unquote(definition_module).internal_error_key()

              if is_nil(errors), do: %{key => reason}, else: Map.put(errors, key, reason)
          end

        if is_nil(errors), do: {:ok, normalized}, else: {:error, errors}
      end

      defp __validate_root_map_collect__(_params), do: {:error, :invalid_type}
    end
  end

  defp build_map_fail_root_ast(field_fun_names, true) do
    chain_ast =
      case field_fun_names do
        [] ->
          quote(do: {:ok, %{}})

        [first_fun_name | rest_fun_names] ->
          Enum.reduce(
            rest_fun_names,
            quote(do: unquote(first_fun_name)(params, %{})),
            fn field_fun_name, acc_ast ->
              quote do
                case unquote(acc_ast) do
                  {:ok, normalized} -> unquote(field_fun_name)(params, normalized)
                  {:error, reason} -> {:error, reason}
                end
              end
            end
          )
      end

    quote do
      defp __validate_root_map_fail_fast__(params) when is_map(params) do
        unquote(chain_ast)
      end

      defp __validate_root_map_fail_fast__(_params), do: {:error, :invalid_type}
    end
  end

  defp build_map_fail_root_ast(field_fun_names, false) do
    runtime_module = Runtime
    definition_module = Definition

    chain_ast =
      case field_fun_names do
        [] ->
          quote(do: {:ok, %{}, MapSet.new()})

        [first_fun_name | rest_fun_names] ->
          Enum.reduce(
            rest_fun_names,
            quote(do: unquote(first_fun_name)(params, %{}, MapSet.new())),
            fn field_fun_name, acc_ast ->
              quote do
                case unquote(acc_ast) do
                  {:ok, normalized, consumed_keys} ->
                    unquote(field_fun_name)(params, normalized, consumed_keys)

                  {:error, reason} ->
                    {:error, reason}
                end
              end
            end
          )
      end

    quote do
      defp __validate_root_map_fail_fast__(params) when is_map(params) do
        case unquote(chain_ast) do
          {:error, reason} ->
            {:error, reason}

          {:ok, normalized, consumed_keys} ->
            case unquote(runtime_module).extra_fields(params, consumed_keys) do
              [] ->
                {:ok, normalized}

              fields ->
                {:error, %{unquote(definition_module).internal_error_key() => Enum.sort(fields)}}
            end
        end
      end

      defp __validate_root_map_fail_fast__(_params), do: {:error, :invalid_type}
    end
  end

  defp compiled_parts({:compiled, kind, data, opts}),
    do: {kind, Macro.escape(data), Macro.escape(opts)}

  @doc """
  schema 定義に従って値を検証する。
  """
  @spec validate(term(), schema_definition()) :: {:ok, term()} | {:error, term()}
  def validate(value, schema), do: Runtime.validate(value, schema)

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
