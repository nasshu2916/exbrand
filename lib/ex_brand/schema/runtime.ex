defmodule ExBrand.Schema.Runtime do
  @moduledoc false

  alias ExBrand.Schema.Definition
  alias ExBrand.Validator

  @spec validate(term(), term()) :: {:ok, term()} | {:error, term()}
  def validate(value, schema), do: validate_schema(value, schema)

  @spec validate_compiled_root(term(), :map | :list | :terminal, term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def validate_compiled_root(value, kind, data, opts),
    do: validate_compiled(value, kind, data, opts)

  @spec validate_compiled(term(), :map | :list | :terminal, term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def validate_compiled(value, kind, data, opts) do
    metadata = compiled_runtime_metadata(opts) || empty_compiled_runtime_metadata()

    if Keyword.get(opts, :nullable, false) and is_nil(value) do
      {:ok, nil}
    else
      with {:ok, typed_value} <- validate_compiled_typed_value(value, kind, data, opts),
           {:ok, constrained_value} <-
             apply_compiled_constraints(typed_value, compiled_base_schema(kind, data), metadata) do
        {:ok, constrained_value}
      else
        {:error, reason} -> {:error, wrap_error(reason, opts)}
      end
    end
  end

  defp validate_schema(value, {:compiled, kind, data, opts}) do
    validate_compiled(value, kind, data, opts)
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
    fail_fast = fail_fast?(opts)

    if reject_extra_fields?(opts) do
      validate_map_strict(value, schema_fields, fail_fast)
    else
      validate_map_relaxed(value, schema_fields, fail_fast)
    end
  end

  defp validate_map(_value, _schema_fields, _opts), do: {:error, :invalid_type}

  defp validate_map_strict(value, schema_fields, true) do
    case Enum.reduce_while(schema_fields, {%{}, MapSet.new()}, fn {name, field_schema},
                                                                  {normalized, consumed_keys} ->
           {schema, field_opts, field_lookup, schema_without_opts} =
             field_metadata(field_schema, name)

           validate_strict_field(
             value,
             name,
             schema,
             field_lookup,
             schema_without_opts,
             field_opts,
             normalized,
             consumed_keys
           )
         end) do
      {:error, errors} ->
        {:error, errors}

      {normalized, consumed_keys} ->
        case extra_fields(value, consumed_keys) do
          [] -> {:ok, normalized}
          fields -> {:error, %{Definition.internal_error_key() => Enum.sort(fields)}}
        end
    end
  end

  defp validate_map_strict(value, schema_fields, false) do
    {normalized, errors, consumed_keys} =
      Enum.reduce(schema_fields, {%{}, nil, MapSet.new()}, fn {name, field_schema},
                                                              {normalized, errors, consumed_keys} ->
        {schema, field_opts, field_lookup, schema_without_opts} =
          field_metadata(field_schema, name)

        case fetch_field_value(value, field_lookup) do
          {:ok, field_value, used_key} ->
            case validate_schema(field_value, schema) do
              {:ok, normalized_value} ->
                {Map.put(normalized, name, normalized_value), errors,
                 MapSet.put(consumed_keys, used_key)}

              {:error, reason} ->
                {normalized, put_error(errors, name, reason), MapSet.put(consumed_keys, used_key)}
            end

          :missing ->
            case resolve_missing_field(schema_without_opts, field_opts) do
              {:ok, default_or_nil} ->
                {Map.put(normalized, name, default_or_nil), errors, consumed_keys}

              {:error, reason} ->
                {normalized, put_error(errors, name, reason), consumed_keys}
            end
        end
      end)

    errors = append_extra_field_errors(value, consumed_keys, errors)
    maybe_error_or_ok(errors, normalized)
  end

  defp validate_strict_field(
         value,
         name,
         schema,
         field_lookup,
         schema_without_opts,
         field_opts,
         normalized,
         consumed_keys
       ) do
    case fetch_field_value(value, field_lookup) do
      {:ok, field_value, used_key} ->
        validate_present_strict_field(
          field_value,
          schema,
          name,
          normalized,
          consumed_keys,
          used_key
        )

      :missing ->
        validate_missing_strict_field(
          schema_without_opts,
          field_opts,
          name,
          normalized,
          consumed_keys
        )
    end
  end

  defp validate_present_strict_field(
         field_value,
         schema,
         name,
         normalized,
         consumed_keys,
         used_key
       ) do
    case validate_schema(field_value, schema) do
      {:ok, normalized_value} ->
        {:cont,
         {Map.put(normalized, name, normalized_value), MapSet.put(consumed_keys, used_key)}}

      {:error, reason} ->
        {:halt, {:error, %{name => reason}}}
    end
  end

  defp validate_missing_strict_field(
         schema_without_opts,
         field_opts,
         name,
         normalized,
         consumed_keys
       ) do
    case resolve_missing_field(schema_without_opts, field_opts) do
      {:ok, default_or_nil} ->
        {:cont, {Map.put(normalized, name, default_or_nil), consumed_keys}}

      {:error, reason} ->
        {:halt, {:error, %{name => reason}}}
    end
  end

  defp validate_map_relaxed(value, schema_fields, true) do
    Enum.reduce_while(schema_fields, {:ok, %{}}, fn {name, field_schema}, {:ok, normalized} ->
      {schema, field_opts, field_lookup, schema_without_opts} = field_metadata(field_schema, name)

      case fetch_field_value(value, field_lookup) do
        {:ok, field_value, _used_key} ->
          case validate_schema(field_value, schema) do
            {:ok, normalized_value} ->
              {:cont, {:ok, Map.put(normalized, name, normalized_value)}}

            {:error, reason} ->
              {:halt, {:error, %{name => reason}}}
          end

        :missing ->
          case resolve_missing_field(schema_without_opts, field_opts) do
            {:ok, default_or_nil} ->
              {:cont, {:ok, Map.put(normalized, name, default_or_nil)}}

            {:error, reason} ->
              {:halt, {:error, %{name => reason}}}
          end
      end
    end)
  end

  defp validate_map_relaxed(value, schema_fields, false) do
    {normalized, errors} =
      Enum.reduce(schema_fields, {%{}, nil}, fn {name, field_schema}, {normalized, errors} ->
        {schema, field_opts, field_lookup, schema_without_opts} =
          field_metadata(field_schema, name)

        case fetch_field_value(value, field_lookup) do
          {:ok, field_value, _used_key} ->
            case validate_schema(field_value, schema) do
              {:ok, normalized_value} ->
                {Map.put(normalized, name, normalized_value), errors}

              {:error, reason} ->
                {normalized, put_error(errors, name, reason)}
            end

          :missing ->
            case resolve_missing_field(schema_without_opts, field_opts) do
              {:ok, default_or_nil} ->
                {Map.put(normalized, name, default_or_nil), errors}

              {:error, reason} ->
                {normalized, put_error(errors, name, reason)}
            end
        end
      end)

    maybe_error_or_ok(errors, normalized)
  end

  defp validate_list(value, item_schema, opts) when is_list(value) do
    fail_fast = fail_fast?(opts)

    if fail_fast do
      validate_list_fail_fast(value, item_schema, opts)
    else
      validate_list_collect_all(value, item_schema, opts)
    end
  end

  defp validate_list(_value, _item_schema, _opts), do: {:error, :invalid_type}

  defp validate_list_fail_fast(value, item_schema, opts) do
    with {:ok, normalized_items_reversed} <- validate_list_items_fail_fast(value, item_schema),
         :ok <- validate_list_constraints_fail_fast(value, opts) do
      {:ok, Enum.reverse(normalized_items_reversed)}
    else
      {:error, {index, reason}} -> {:error, %{index => reason}}
      {:error, reason} -> {:error, %{__self__: reason}}
    end
  end

  defp validate_list_collect_all(value, item_schema, opts) do
    {normalized_items, item_errors} =
      value
      |> Enum.with_index()
      |> Enum.reduce({[], nil}, fn {item, index}, {normalized_items, item_errors} ->
        case validate_schema(item, item_schema) do
          {:ok, normalized_item} -> {[normalized_item | normalized_items], item_errors}
          {:error, reason} -> {normalized_items, put_error(item_errors, index, reason)}
        end
      end)

    normalized_items = Enum.reverse(normalized_items)

    result =
      case compiled_list_checks(opts) do
        nil ->
          apply_list_constraints(value, normalized_items, item_errors, opts)

        checks ->
          apply_compiled_list_constraints(value, normalized_items, item_errors, checks)
      end

    result
  end

  defp append_extra_field_errors(value, consumed_keys, errors) do
    case extra_fields(value, consumed_keys) do
      [] -> errors
      fields -> put_error(errors, Definition.internal_error_key(), Enum.sort(fields))
    end
  end

  defp reject_extra_fields?(opts) do
    not (Keyword.get(opts, :tolerant, false) or Keyword.get(opts, :allow_extra_fields, false))
  end

  defp atomizable_key?(key) do
    _ = String.to_existing_atom(key)
    true
  rescue
    ArgumentError -> false
  end

  defp field_metadata(
         %{schema: schema, schema_without_opts: schema_without_opts, opts: opts, lookup: lookup},
         _name
       ) do
    {schema, opts, {:compiled, lookup}, schema_without_opts}
  end

  defp field_metadata(field_schema, name) do
    schema = field_schema(field_schema)
    opts = field_opts(field_schema)
    {schema, opts, field_lookup(field_schema, name, opts), field_schema_without_opts(schema)}
  end

  defp field_schema(%{schema: schema}), do: schema
  defp field_schema(schema), do: schema

  defp field_lookup(%{lookup: lookup}, _name, _opts), do: {:compiled, lookup}
  defp field_lookup(_schema, name, opts), do: {:raw, name, opts}

  defp field_opts(%{schema: schema}), do: field_opts(schema)
  defp field_opts({:compiled, _kind, _data, opts}), do: opts
  defp field_opts(schema), do: elem(Definition.split_schema_opts(schema), 1)

  defp field_schema_without_opts(%{schema: schema}), do: field_schema_without_opts(schema)
  defp field_schema_without_opts({:compiled, kind, data, _opts}), do: {:compiled, kind, data, []}
  defp field_schema_without_opts(schema), do: elem(Definition.split_schema_opts(schema), 0)

  defp compiled_base_schema(:map, schema_fields), do: {:compiled, :map, schema_fields, []}
  defp compiled_base_schema(:list, item_schema), do: {:compiled, :list, item_schema, []}

  defp compiled_base_schema(:terminal, resolved_schema),
    do: {:compiled, :terminal, resolved_schema, []}

  defp compiled_runtime_metadata(opts), do: Definition.compiled_runtime_metadata(opts)

  defp compiled_list_checks(opts) do
    case compiled_runtime_metadata(opts) do
      nil -> nil
      metadata -> metadata.list_checks
    end
  end

  defp fail_fast?(opts) do
    _ = opts
    schema_fail_fast_enabled?()
  end

  defp empty_compiled_runtime_metadata do
    %{
      generic_checks: [],
      list_checks: [],
      validator: nil,
      validator_error: :invalid_value
    }
  end

  @spec schema_fail_fast_enabled?() :: boolean()
  def schema_fail_fast_enabled? do
    case Application.get_env(:ex_brand, :schema_fail_fast, false) do
      true -> true
      false -> false
      _other -> false
    end
  end

  defp fetch_field_value(params, {:compiled, lookup}) do
    fetch_compiled_field_value(params, lookup)
  end

  defp fetch_field_value(params, {:raw, name, opts}) do
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

  @spec fetch_compiled_field_value(map(), [Definition.runtime_lookup_entry()]) ::
          {:ok, term(), atom() | String.t()} | :missing
  def fetch_compiled_field_value(_params, []), do: :missing

  def fetch_compiled_field_value(params, [key | rest]) when is_atom(key) or is_binary(key) do
    if Map.has_key?(params, key) do
      {:ok, Map.fetch!(params, key), key}
    else
      fetch_compiled_field_value(params, rest)
    end
  end

  def fetch_compiled_field_value(params, [{:existing_atom_binary, key} | rest]) do
    with true <- atomizable_key?(key),
         atom_key <- String.to_atom(key),
         true <- Map.has_key?(params, atom_key) do
      {:ok, Map.fetch!(params, atom_key), atom_key}
    else
      _ -> fetch_compiled_field_value(params, rest)
    end
  end

  defp apply_compiled_constraints(value, base_schema, metadata) do
    constraint_input = constraint_input(base_schema, value)
    generic_context = build_compiled_generic_context(constraint_input)

    with :ok <-
           run_compiled_generic_checks(
             constraint_input,
             metadata.generic_checks,
             generic_context
           ),
         {:ok, normalized_value} <-
           run_compiled_custom_validator(
             value,
             base_schema,
             metadata.validator,
             metadata.validator_error
           ) do
      {:ok, normalized_value}
    end
  end

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

    maybe_error_or_ok(errors, normalized_items)
  end

  defp apply_compiled_list_constraints(original_items, normalized_items, item_errors, checks) do
    list_context = build_compiled_list_context(original_items, checks)

    errors =
      item_errors
      |> maybe_put_self_error(run_compiled_list_check(checks, :min_items, list_context))
      |> maybe_put_self_error(run_compiled_list_check(checks, :max_items, list_context))
      |> maybe_put_self_error(run_compiled_list_uniqueness_check(original_items, checks))

    maybe_error_or_ok(errors, normalized_items)
  end

  defp maybe_put_self_error(errors, :ok), do: errors
  defp maybe_put_self_error(nil, {:error, reason}), do: %{__self__: reason}
  defp maybe_put_self_error(errors, {:error, reason}), do: Map.put(errors, :__self__, reason)

  defp maybe_error_or_ok(nil, ok_value), do: {:ok, ok_value}
  defp maybe_error_or_ok(errors, _ok_value), do: {:error, errors}

  @spec accumulate_error(nil | map(), term(), term()) :: map()
  def accumulate_error(errors, key, reason), do: put_error(errors, key, reason)

  defp put_error(nil, key, reason), do: %{key => reason}
  defp put_error(errors, key, reason), do: Map.put(errors, key, reason)

  @spec resolve_missing_field(term(), keyword()) :: {:ok, term()} | {:error, term()}
  def resolve_missing_field(field_schema, field_opts) do
    cond do
      Keyword.has_key?(field_opts, :default) ->
        validate_schema(Keyword.fetch!(field_opts, :default), field_schema)

      Keyword.get(field_opts, :optional, false) ->
        {:ok, nil}

      true ->
        {:error, :required}
    end
  end

  @spec extra_fields(map(), MapSet.t()) :: [term()]
  def extra_fields(value, consumed_keys) do
    value
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(consumed_keys, &1))
  end

  defp validate_list_items_fail_fast(value, item_schema) do
    Enum.reduce_while(Enum.with_index(value), {:ok, []}, fn {item, index},
                                                            {:ok, normalized_items} ->
      case validate_schema(item, item_schema) do
        {:ok, normalized_item} ->
          {:cont, {:ok, [normalized_item | normalized_items]}}

        {:error, reason} ->
          {:halt, {:error, {index, reason}}}
      end
    end)
  end

  defp validate_list_constraints_fail_fast(original_items, opts) do
    case compiled_list_checks(opts) do
      nil ->
        with :ok <- check_min_items(original_items, opts),
             :ok <- check_max_items(original_items, opts),
             :ok <- check_unique_items(original_items, opts) do
          :ok
        end

      checks ->
        context = build_compiled_list_context(original_items, checks)

        with :ok <- run_compiled_list_check(checks, :min_items, context),
             :ok <- run_compiled_list_check(checks, :max_items, context),
             :ok <- run_compiled_list_uniqueness_check(original_items, checks) do
          :ok
        end
    end
  end

  defp build_compiled_generic_context(value) when is_binary(value),
    do: %{string_length: String.length(value)}

  defp build_compiled_generic_context(_value), do: %{}

  defp build_compiled_list_context(items, checks) do
    if Enum.any?(checks, fn
         {:min_items, _value} -> true
         {:max_items, _value} -> true
         _ -> false
       end) do
      %{item_count: length(items)}
    else
      %{}
    end
  end

  defp run_compiled_generic_checks(_value, [], _context), do: :ok

  defp run_compiled_generic_checks(value, [{:enum, enum_values} | rest], context) do
    if value in enum_values,
      do: run_compiled_generic_checks(value, rest, context),
      else: {:error, :not_in_enum}
  end

  defp run_compiled_generic_checks(value, [{:minimum, minimum} | rest], context) do
    if value >= minimum,
      do: run_compiled_generic_checks(value, rest, context),
      else: {:error, :less_than_minimum}
  end

  defp run_compiled_generic_checks(value, [{:maximum, maximum} | rest], context) do
    if value <= maximum,
      do: run_compiled_generic_checks(value, rest, context),
      else: {:error, :greater_than_maximum}
  end

  defp run_compiled_generic_checks(value, [{:min_length, minimum} | rest], %{
         string_length: length
       }) do
    if length >= minimum,
      do: run_compiled_generic_checks(value, rest, %{string_length: length}),
      else: {:error, :shorter_than_min_length}
  end

  defp run_compiled_generic_checks(value, [{:max_length, maximum} | rest], %{
         string_length: length
       }) do
    if length <= maximum,
      do: run_compiled_generic_checks(value, rest, %{string_length: length}),
      else: {:error, :longer_than_max_length}
  end

  defp run_compiled_generic_checks(value, [{:format, :email} | rest], context) do
    with :ok <- validate_email_format(value) do
      run_compiled_generic_checks(value, rest, context)
    end
  end

  defp run_compiled_generic_checks(value, [{:format, :datetime} | rest], context) do
    with :ok <- validate_datetime_format(value) do
      run_compiled_generic_checks(value, rest, context)
    end
  end

  defp run_compiled_custom_validator(value, base_schema, validator, error) do
    Validator.apply_custom(
      constraint_input(base_schema, value),
      value,
      validator,
      error,
      &validate_schema(&1, base_schema)
    )
  end

  defp run_compiled_list_check([], _kind, _context), do: :ok

  defp run_compiled_list_check([{:min_items, value} | rest], :min_items, %{item_count: item_count}) do
    if item_count >= value,
      do: run_compiled_list_check(rest, :min_items, %{item_count: item_count}),
      else: compiled_list_check_error(:min_items)
  end

  defp run_compiled_list_check([{:max_items, value} | rest], :max_items, %{item_count: item_count}) do
    if item_count <= value,
      do: run_compiled_list_check(rest, :max_items, %{item_count: item_count}),
      else: compiled_list_check_error(:max_items)
  end

  defp run_compiled_list_check([_other | rest], kind, context),
    do: run_compiled_list_check(rest, kind, context)

  defp run_compiled_list_uniqueness_check(items, checks) do
    if :unique_items in checks do
      if Enum.uniq(items) == items, do: :ok, else: {:error, :items_not_unique}
    else
      :ok
    end
  end

  defp compiled_list_check_error(:min_items), do: {:error, :fewer_than_min_items}
  defp compiled_list_check_error(:max_items), do: {:error, :more_than_max_items}

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
