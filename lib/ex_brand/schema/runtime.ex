defmodule ExBrand.Schema.Runtime do
  @moduledoc false

  alias ExBrand.Schema.Definition
  alias ExBrand.Schema.Runtime.Config
  alias ExBrand.Validator

  @spec validate(term(), term()) :: {:ok, term()} | {:error, term()}
  def validate(value, {:compiled, kind, data, opts}),
    do: with_runtime_config(fn -> validate_compiled(value, kind, data, opts) end)

  def validate(_value, _schema) do
    raise ArgumentError, "schema must be compiled before runtime validation"
  end

  @spec with_runtime_config((-> term())) :: term()
  def with_runtime_config(fun) when is_function(fun, 0), do: Config.with_runtime_config(fun)

  @spec validate_compiled_root(term(), :map | :list | :terminal, term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def validate_compiled_root(value, kind, data, opts) do
    with_runtime_config(fn -> validate_compiled(value, kind, data, opts) end)
  end

  @type key_lookup_context() :: %{String.t() => atom()}

  @spec validate_compiled_nested(term(), :map | :list | :terminal, term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def validate_compiled_nested(value, kind, data, opts) do
    if deep_nested_deferred?() and kind in [:map, :list] do
      case kind do
        :map when is_map(value) -> {:ok, value}
        :list when is_list(value) -> {:ok, value}
        _ -> {:error, :invalid_type}
      end
    else
      validate_compiled_root(value, kind, data, opts)
    end
  end

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

  defp validate_schema(value, {:compiled, kind, data, opts}),
    do: validate_compiled(value, kind, data, opts)

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

  defp validate_map(value, schema_fields, opts) when is_map(value) do
    mode = if fail_fast?(opts), do: :fail_fast, else: :collect_all
    policy = if reject_extra_fields?(opts), do: :strict, else: :relaxed
    key_context = build_key_lookup_context(value)
    validate_map_with_strategy(value, schema_fields, mode, policy, key_context)
  end

  defp validate_map(_value, _schema_fields, _opts), do: {:error, :invalid_type}

  defp validate_map_with_strategy(value, schema_fields, :fail_fast, :strict, key_context),
    do: validate_map_strict(value, schema_fields, true, key_context)

  defp validate_map_with_strategy(value, schema_fields, :collect_all, :strict, key_context),
    do: validate_map_strict(value, schema_fields, false, key_context)

  defp validate_map_with_strategy(value, schema_fields, :fail_fast, :relaxed, key_context),
    do: validate_map_relaxed(value, schema_fields, true, key_context)

  defp validate_map_with_strategy(value, schema_fields, :collect_all, :relaxed, key_context),
    do: validate_map_relaxed(value, schema_fields, false, key_context)

  defp validate_map_strict(value, schema_fields, true, key_context) do
    case Enum.reduce_while(schema_fields, {%{}, MapSet.new()}, fn {name, field_schema},
                                                                  {normalized, consumed_keys} ->
           {schema, field_opts, field_lookup, schema_without_opts} = field_metadata(field_schema)

           validate_strict_field(
             value,
             {name, schema, field_lookup, schema_without_opts, field_opts},
             normalized,
             consumed_keys,
             key_context
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

  defp validate_map_strict(value, schema_fields, false, key_context) do
    {normalized, errors, consumed_keys} =
      Enum.reduce(schema_fields, {%{}, nil, MapSet.new()}, fn {name, field_schema},
                                                              {normalized, errors, consumed_keys} ->
        {schema, field_opts, field_lookup, schema_without_opts} = field_metadata(field_schema)

        case fetch_field_value(value, field_lookup, key_context) do
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
         {name, schema, field_lookup, schema_without_opts, field_opts},
         normalized,
         consumed_keys,
         key_context
       ) do
    case fetch_field_value(value, field_lookup, key_context) do
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

  defp validate_map_relaxed(value, schema_fields, true, key_context) do
    Enum.reduce_while(schema_fields, {:ok, %{}}, fn {name, field_schema}, {:ok, normalized} ->
      {schema, field_opts, field_lookup, schema_without_opts} = field_metadata(field_schema)

      case fetch_field_value(value, field_lookup, key_context) do
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

  defp validate_map_relaxed(value, schema_fields, false, key_context) do
    {normalized, errors} =
      Enum.reduce(schema_fields, {%{}, nil}, fn {name, field_schema}, {normalized, errors} ->
        {schema, field_opts, field_lookup, schema_without_opts} = field_metadata(field_schema)

        case fetch_field_value(value, field_lookup, key_context) do
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

    checks = compiled_list_checks(opts) || []
    apply_compiled_list_constraints(value, normalized_items, item_errors, checks)
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

  defp to_existing_atom_safe(key) when is_binary(key) do
    {:ok, String.to_existing_atom(key)}
  rescue
    ArgumentError -> :error
  end

  defp field_metadata(%{
         schema: schema,
         schema_without_opts: schema_without_opts,
         opts: opts,
         lookup: lookup
       }) do
    {schema, opts, {:compiled, lookup}, schema_without_opts}
  end

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
    Config.schema_fail_fast_enabled?()
  end

  @spec schema_deferred_checks() :: MapSet.t(atom())
  def schema_deferred_checks, do: Config.schema_deferred_checks()

  defp check_deferred?(check) do
    MapSet.member?(schema_deferred_checks(), check)
  end

  defp deep_nested_deferred?, do: check_deferred?(:deep_nested)

  @spec build_key_lookup_context(map()) :: key_lookup_context()
  def build_key_lookup_context(params) when is_map(params) do
    Enum.reduce(params, %{}, fn
      {key, _value}, acc when is_binary(key) ->
        case to_existing_atom_safe(key) do
          {:ok, atom_key} -> Map.put_new(acc, key, atom_key)
          :error -> acc
        end

      {key, _value}, acc when is_atom(key) ->
        Map.put_new(acc, Atom.to_string(key), key)

      {_key, _value}, acc ->
        acc
    end)
  end

  defp fetch_field_value(params, {:compiled, lookup}, key_context) do
    fetch_compiled_field_value(params, lookup, key_context)
  end

  @spec fetch_compiled_field_value(map(), [Definition.runtime_lookup_entry()]) ::
          {:ok, term(), atom() | String.t()} | :missing
  def fetch_compiled_field_value(params, lookup) do
    fetch_compiled_field_value(params, lookup, build_key_lookup_context(params))
  end

  @spec fetch_compiled_field_value(
          map(),
          [Definition.runtime_lookup_entry()],
          key_lookup_context()
        ) ::
          {:ok, term(), atom() | String.t()} | :missing
  def fetch_compiled_field_value(_params, [], _key_context), do: :missing

  def fetch_compiled_field_value(params, [key | rest], key_context)
      when is_atom(key) or is_binary(key) do
    if Map.has_key?(params, key) do
      {:ok, Map.fetch!(params, key), key}
    else
      fetch_compiled_field_value(params, rest, key_context)
    end
  end

  def fetch_compiled_field_value(params, [{:existing_atom_binary, key} | rest], key_context) do
    with {:ok, atom_key} <- Map.fetch(key_context, key),
         true <- Map.has_key?(params, atom_key) do
      {:ok, Map.fetch!(params, atom_key), atom_key}
    else
      _ -> fetch_compiled_field_value(params, rest, key_context)
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
    |> Enum.reduce([], fn {key, _value}, acc ->
      if MapSet.member?(consumed_keys, key), do: acc, else: [key | acc]
    end)
    |> Enum.reverse()
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
    checks = compiled_list_checks(opts) || []
    context = build_compiled_list_context(original_items, checks)

    with :ok <- run_compiled_list_check(checks, :min_items, context),
         :ok <- run_compiled_list_check(checks, :max_items, context),
         :ok <- run_compiled_list_uniqueness_check(original_items, checks) do
      :ok
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
    if check_deferred?(:enum) do
      run_compiled_generic_checks(value, rest, context)
    else
      if value in enum_values,
        do: run_compiled_generic_checks(value, rest, context),
        else: {:error, :not_in_enum}
    end
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
    if check_deferred?(:format) or check_deferred?(:regex) do
      run_compiled_generic_checks(value, rest, context)
    else
      with :ok <- validate_email_format(value) do
        run_compiled_generic_checks(value, rest, context)
      end
    end
  end

  defp run_compiled_generic_checks(value, [{:format, :datetime} | rest], context) do
    if check_deferred?(:format) or check_deferred?(:regex) do
      run_compiled_generic_checks(value, rest, context)
    else
      with :ok <- validate_datetime_format(value) do
        run_compiled_generic_checks(value, rest, context)
      end
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
    if check_deferred?(:unique_items) do
      :ok
    else
      if :unique_items in checks do
        if unique_items?(items), do: :ok, else: {:error, :items_not_unique}
      else
        :ok
      end
    end
  end

  defp compiled_list_check_error(:min_items), do: {:error, :fewer_than_min_items}
  defp compiled_list_check_error(:max_items), do: {:error, :more_than_max_items}

  defp validate_email_format(value) do
    if String.match?(value, ~r/^[^\s]+@[^\s]+\.[^\s]+$/), do: :ok, else: {:error, :invalid_format}
  end

  defp validate_datetime_format(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> :ok
      _ -> {:error, :invalid_format}
    end
  end

  defp constraint_input({:compiled, :terminal, {:brand, _module}, _opts}, value),
    do: ExBrand.unwrap!(value)

  defp constraint_input({:compiled, _kind, _data, _opts}, value), do: value

  defp wrap_error(reason, opts) do
    case Keyword.fetch(opts, :error) do
      {:ok, custom_error} -> custom_error
      :error -> reason
    end
  end

  defp unique_items?(items) do
    Enum.reduce_while(items, MapSet.new(), fn item, seen ->
      if MapSet.member?(seen, item) do
        {:halt, false}
      else
        {:cont, MapSet.put(seen, item)}
      end
    end) != false
  end
end
