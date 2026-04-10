defmodule ExBrand.Schema.Runtime do
  @moduledoc false

  alias ExBrand.Schema.Definition
  alias ExBrand.Validator

  @spec validate(term(), term()) :: {:ok, term()} | {:error, term()}
  def validate(value, schema), do: validate_schema(value, schema)

  defp validate_schema(value, {:compiled, kind, data, opts}) do
    if Keyword.get(opts, :nullable, false) and is_nil(value) do
      {:ok, nil}
    else
      with {:ok, typed_value} <- validate_compiled_typed_value(value, kind, data, opts),
           {:ok, constrained_value} <-
             apply_constraints(typed_value, compiled_base_schema(kind, data), opts) do
        {:ok, constrained_value}
      else
        {:error, reason} -> {:error, wrap_error(reason, opts)}
      end
    end
  end

  defp validate_schema(value, schema) do
    {base_schema, opts} = Definition.split_schema_opts(schema)

    if Keyword.get(opts, :nullable, false) and is_nil(value) do
      {:ok, nil}
    else
      with {:ok, typed_value} <- validate_typed_value(value, base_schema, opts),
           {:ok, constrained_value} <- apply_constraints(typed_value, base_schema, opts) do
        {:ok, constrained_value}
      else
        {:error, reason} -> {:error, wrap_error(reason, opts)}
      end
    end
  end

  defp validate_compiled_typed_value(value, :map, schema_fields, opts),
    do: validate_map(value, schema_fields, opts)

  defp validate_compiled_typed_value(value, :list, item_schema, opts),
    do: validate_list(value, item_schema, opts)

  defp validate_compiled_typed_value(value, :terminal, resolved_schema, _opts) do
    case resolved_schema do
      {:brand, module} -> module.cast(value)
      {:schema, module} -> module.validate(value)
      {:base, base} -> Validator.validate_schema_base(value, base)
    end
  end

  defp validate_typed_value(value, schema, opts) when is_map(schema),
    do: validate_map(value, schema, opts)

  defp validate_typed_value(value, [item_schema], opts),
    do: validate_list(value, item_schema, opts)

  defp validate_typed_value(_value, [], _opts), do: {:error, :invalid_schema}

  defp validate_typed_value(value, schema, _opts) do
    case Definition.resolve_terminal_schema(schema) do
      {:ok, {:brand, module}} -> module.cast(value)
      {:ok, {:schema, module}} -> module.validate(value)
      {:ok, {:base, base}} -> Validator.validate_schema_base(value, base)
      :error -> {:error, :invalid_schema}
    end
  end

  defp validate_map(value, schema_fields, opts) when is_map(value) do
    tolerant = Keyword.get(opts, :tolerant, false)

    {normalized, errors, consumed_keys} =
      Enum.reduce(schema_fields, {%{}, %{}, MapSet.new()}, fn {name, field_schema}, acc ->
        {normalized, errors, consumed_keys} = acc
        field_opts = field_opts(field_schema)

        case fetch_field_value(value, name, field_opts) do
          {:ok, field_value, used_key} ->
            case validate_schema(field_value, field_schema) do
              {:ok, normalized_value} ->
                {Map.put(normalized, name, normalized_value), errors,
                 MapSet.put(consumed_keys, used_key)}

              {:error, reason} ->
                {normalized, Map.put(errors, name, reason), MapSet.put(consumed_keys, used_key)}
            end

          :missing ->
            handle_missing_field(
              name,
              field_schema_without_opts(field_schema),
              field_opts,
              normalized,
              errors,
              consumed_keys
            )
        end
      end)

    errors =
      if tolerant do
        errors
      else
        append_extra_field_errors(value, consumed_keys, errors)
      end

    case map_size(errors) do
      0 -> {:ok, normalized}
      _ -> {:error, errors}
    end
  end

  defp validate_map(_value, _schema_fields, _opts), do: {:error, :invalid_type}

  defp validate_list(value, item_schema, opts) when is_list(value) do
    {normalized_items, item_errors} =
      value
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {item, index}, {normalized_items, item_errors} ->
        case validate_schema(item, item_schema) do
          {:ok, normalized_item} -> {[normalized_item | normalized_items], item_errors}
          {:error, reason} -> {normalized_items, Map.put(item_errors, index, reason)}
        end
      end)

    normalized_items = Enum.reverse(normalized_items)

    case apply_list_constraints(value, normalized_items, item_errors, opts) do
      {:ok, normalized_value} -> {:ok, normalized_value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_list(_value, _item_schema, _opts), do: {:error, :invalid_type}

  defp handle_missing_field(name, field_schema, field_opts, normalized, errors, consumed_keys) do
    cond do
      Keyword.has_key?(field_opts, :default) ->
        case validate_schema(Keyword.fetch!(field_opts, :default), field_schema) do
          {:ok, default_value} ->
            {Map.put(normalized, name, default_value), errors, consumed_keys}

          {:error, reason} ->
            {normalized, Map.put(errors, name, reason), consumed_keys}
        end

      Keyword.get(field_opts, :optional, false) ->
        {Map.put(normalized, name, nil), errors, consumed_keys}

      true ->
        {normalized, Map.put(errors, name, :required), consumed_keys}
    end
  end

  defp append_extra_field_errors(value, consumed_keys, errors) do
    extra_fields =
      value
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(consumed_keys, &1))

    case extra_fields do
      [] -> errors
      _ -> Map.put(errors, Definition.internal_error_key(), Enum.sort(extra_fields))
    end
  end

  defp fetch_field_value(params, name, opts) do
    external_name = Keyword.get(opts, :field, name)

    cond do
      is_atom(external_name) and Map.has_key?(params, external_name) ->
        {:ok, Map.fetch!(params, external_name), external_name}

      is_atom(external_name) and Map.has_key?(params, Atom.to_string(external_name)) ->
        key = Atom.to_string(external_name)
        {:ok, Map.fetch!(params, key), key}

      is_binary(external_name) and Map.has_key?(params, external_name) ->
        {:ok, Map.fetch!(params, external_name), external_name}

      is_binary(external_name) and atomizable_key?(external_name) and
          Map.has_key?(params, String.to_atom(external_name)) ->
        key = String.to_atom(external_name)
        {:ok, Map.fetch!(params, key), key}

      true ->
        :missing
    end
  end

  defp atomizable_key?(key) do
    _ = String.to_existing_atom(key)
    true
  rescue
    ArgumentError -> false
  end

  defp field_opts({:compiled, _kind, _data, opts}), do: opts
  defp field_opts(schema), do: elem(Definition.split_schema_opts(schema), 1)

  defp field_schema_without_opts({:compiled, kind, data, _opts}), do: {:compiled, kind, data, []}
  defp field_schema_without_opts(schema), do: elem(Definition.split_schema_opts(schema), 0)

  defp compiled_base_schema(:map, schema_fields), do: {:compiled, :map, schema_fields, []}
  defp compiled_base_schema(:list, item_schema), do: {:compiled, :list, item_schema, []}

  defp compiled_base_schema(:terminal, resolved_schema),
    do: {:compiled, :terminal, resolved_schema, []}

  defp apply_constraints(value, base_schema, opts) do
    constraint_input = constraint_input(base_schema, value)

    with :ok <- validate_enum(constraint_input, opts),
         :ok <- validate_numeric(constraint_input, opts),
         :ok <- validate_length(constraint_input, opts),
         :ok <- validate_format(constraint_input, opts),
         {:ok, normalized_value} <- run_custom_validator(value, base_schema, opts) do
      {:ok, normalized_value}
    end
  end

  defp apply_list_constraints(original_items, normalized_items, item_errors, opts) do
    errors =
      item_errors
      |> maybe_put_self_error(check_min_items(original_items, opts))
      |> maybe_put_self_error(check_max_items(original_items, opts))
      |> maybe_put_self_error(check_unique_items(original_items, opts))

    case map_size(errors) do
      0 -> {:ok, normalized_items}
      _ -> {:error, errors}
    end
  end

  defp maybe_put_self_error(errors, :ok), do: errors
  defp maybe_put_self_error(errors, {:error, reason}), do: Map.put(errors, :__self__, reason)

  defp validate_enum(value, opts) do
    case Keyword.fetch(opts, :enum) do
      {:ok, enum_values} when is_list(enum_values) ->
        if value in enum_values, do: :ok, else: {:error, :not_in_enum}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp validate_numeric(value, opts) when is_number(value) do
    with :ok <- check_minimum(value, opts),
         :ok <- check_maximum(value, opts) do
      :ok
    end
  end

  defp validate_numeric(_value, _opts), do: :ok

  defp validate_length(value, opts) when is_binary(value) do
    length = String.length(value)

    with :ok <- check_min_length(length, opts),
         :ok <- check_max_length(length, opts) do
      :ok
    end
  end

  defp validate_length(_value, _opts), do: :ok

  defp validate_format(value, opts) when is_binary(value) do
    case Keyword.get(opts, :format) do
      nil -> :ok
      :email -> validate_email_format(value)
      :datetime -> validate_datetime_format(value)
      _other -> {:error, :invalid_schema}
    end
  end

  defp validate_format(_value, opts) do
    case Keyword.get(opts, :format) do
      nil -> :ok
      _other -> {:error, :invalid_type}
    end
  end

  defp validate_email_format(value) do
    if String.match?(value, ~r/^[^\s]+@[^\s]+\.[^\s]+$/), do: :ok, else: {:error, :invalid_format}
  end

  defp validate_datetime_format(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> :ok
      _ -> {:error, :invalid_format}
    end
  end

  defp run_custom_validator(value, base_schema, opts) do
    Validator.apply_custom(
      constraint_input(base_schema, value),
      value,
      Keyword.get(opts, :validate),
      Keyword.get(opts, :error, :invalid_value),
      &validate_schema(&1, base_schema)
    )
  end

  defp constraint_input({:compiled, :terminal, {:brand, _module}, _opts}, value),
    do: ExBrand.unwrap!(value)

  defp constraint_input({:compiled, _kind, _data, _opts}, value), do: value

  defp constraint_input(schema, value) do
    case Definition.resolve_terminal_schema(schema) do
      {:ok, {:brand, _module}} -> ExBrand.unwrap!(value)
      _ -> value
    end
  end

  defp wrap_error(reason, opts) do
    case Keyword.fetch(opts, :error) do
      {:ok, custom_error} -> custom_error
      :error -> reason
    end
  end

  defp check_minimum(value, opts) do
    case Keyword.fetch(opts, :minimum) do
      {:ok, minimum} when is_number(minimum) ->
        if value >= minimum, do: :ok, else: {:error, :less_than_minimum}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_maximum(value, opts) do
    case Keyword.fetch(opts, :maximum) do
      {:ok, maximum} when is_number(maximum) ->
        if value <= maximum, do: :ok, else: {:error, :greater_than_maximum}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_min_length(length, opts) do
    case Keyword.fetch(opts, :min_length) do
      {:ok, minimum} when is_integer(minimum) and minimum >= 0 ->
        if length >= minimum, do: :ok, else: {:error, :shorter_than_min_length}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_max_length(length, opts) do
    case Keyword.fetch(opts, :max_length) do
      {:ok, maximum} when is_integer(maximum) and maximum >= 0 ->
        if length <= maximum, do: :ok, else: {:error, :longer_than_max_length}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_min_items(items, opts) do
    case Keyword.fetch(opts, :min_items) do
      {:ok, minimum} when is_integer(minimum) and minimum >= 0 ->
        if length(items) >= minimum, do: :ok, else: {:error, :fewer_than_min_items}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_max_items(items, opts) do
    case Keyword.fetch(opts, :max_items) do
      {:ok, maximum} when is_integer(maximum) and maximum >= 0 ->
        if length(items) <= maximum, do: :ok, else: {:error, :more_than_max_items}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_unique_items(items, opts) do
    case Keyword.get(opts, :unique_items, false) do
      true -> if Enum.uniq(items) == items, do: :ok, else: {:error, :items_not_unique}
      false -> :ok
      _other -> {:error, :invalid_schema}
    end
  end
end
