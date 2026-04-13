defmodule ExBrand.Schema.Codegen do
  @moduledoc false

  alias ExBrand.Schema.{Definition, Runtime}

  @spec build_compiled_root_validator_ast([{atom(), term()}], term(), boolean()) :: Macro.t()
  def build_compiled_root_validator_ast(
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

  def build_compiled_root_validator_ast(
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
          defp unquote(collect_name)(params, key_context, normalized, errors) do
            case unquote(runtime_module).fetch_compiled_field_value(
                   params,
                   unquote(lookup_ast),
                   key_context
                 ) do
              {:ok, field_value, _used_key} ->
                case unquote(runtime_module).validate_compiled_nested(
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
          defp unquote(collect_name)(params, key_context, normalized, errors, consumed_keys) do
            case unquote(runtime_module).fetch_compiled_field_value(
                   params,
                   unquote(lookup_ast),
                   key_context
                 ) do
              {:ok, field_value, used_key} ->
                case unquote(runtime_module).validate_compiled_nested(
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
          defp unquote(fail_name)(params, key_context, normalized) do
            case unquote(runtime_module).fetch_compiled_field_value(
                   params,
                   unquote(lookup_ast),
                   key_context
                 ) do
              {:ok, field_value, _used_key} ->
                case unquote(runtime_module).validate_compiled_nested(
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
          defp unquote(fail_name)(params, key_context, normalized, consumed_keys) do
            case unquote(runtime_module).fetch_compiled_field_value(
                   params,
                   unquote(lookup_ast),
                   key_context
                 ) do
              {:ok, field_value, used_key} ->
                case unquote(runtime_module).validate_compiled_nested(
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
    runtime_module = Runtime

    step_asts =
      Enum.map(field_fun_names, fn field_fun_name ->
        quote do
          {normalized, errors} = unquote(field_fun_name)(params, key_context, normalized, errors)
        end
      end)

    quote do
      defp __validate_root_map_collect__(params) when is_map(params) do
        key_context = unquote(runtime_module).build_key_lookup_context(params)
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
            unquote(field_fun_name)(params, key_context, normalized, errors, consumed_keys)
        end
      end)

    quote do
      defp __validate_root_map_collect__(params) when is_map(params) do
        key_context = unquote(runtime_module).build_key_lookup_context(params)
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
    runtime_module = Runtime

    chain_ast =
      case field_fun_names do
        [] ->
          quote(do: {:ok, %{}})

        [first_fun_name | rest_fun_names] ->
          Enum.reduce(
            rest_fun_names,
            quote(do: unquote(first_fun_name)(params, key_context, %{})),
            fn field_fun_name, acc_ast ->
              quote do
                case unquote(acc_ast) do
                  {:ok, normalized} -> unquote(field_fun_name)(params, key_context, normalized)
                  {:error, reason} -> {:error, reason}
                end
              end
            end
          )
      end

    quote do
      defp __validate_root_map_fail_fast__(params) when is_map(params) do
        key_context = unquote(runtime_module).build_key_lookup_context(params)
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
            quote(do: unquote(first_fun_name)(params, key_context, %{}, MapSet.new())),
            fn field_fun_name, acc_ast ->
              quote do
                case unquote(acc_ast) do
                  {:ok, normalized, consumed_keys} ->
                    unquote(field_fun_name)(params, key_context, normalized, consumed_keys)

                  {:error, reason} ->
                    {:error, reason}
                end
              end
            end
          )
      end

    quote do
      defp __validate_root_map_fail_fast__(params) when is_map(params) do
        key_context = unquote(runtime_module).build_key_lookup_context(params)

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
end
