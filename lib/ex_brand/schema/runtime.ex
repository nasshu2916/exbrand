defmodule ExBrand.Schema.Runtime do
  @moduledoc false

  alias ExBrand.Schema.Definition
  alias ExBrand.Schema.Runtime.{Config, ListValidator, MapValidator}
  alias ExBrand.Validator

  @type key_lookup_context() :: MapValidator.key_lookup_context()

  @spec validate(term(), ExBrand.Schema.compiled_schema()) :: {:ok, term()} | {:error, term()}
  def validate(value, {:compiled, kind, data, opts}),
    do: validate_compiled(value, kind, data, opts)

  def validate(_value, _schema) do
    raise ArgumentError, "schema must be compiled before runtime validation"
  end

  @spec set_runtime_config!(keyword(Config.runtime_option())) :: Config.t()
  def set_runtime_config!(opts), do: Config.set_runtime_config!(opts)

  @spec validate_compiled_root(term(), :map | :list | :terminal, term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def validate_compiled_root(value, kind, data, opts),
    do: validate_compiled(value, kind, data, opts)

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

  defp validate_compiled_typed_value(value, :map, schema_fields, opts) do
    MapValidator.validate_map(
      value,
      schema_fields,
      fail_fast?(opts),
      &validate_schema/2,
      Definition.internal_error_key()
    )
  end

  defp validate_compiled_typed_value(value, :list, item_schema, opts) do
    ListValidator.validate_list(
      value,
      item_schema,
      fail_fast?(opts),
      &validate_schema/2,
      compiled_list_checks(opts) || [],
      check_deferred?(:unique_items)
    )
  end

  defp validate_compiled_typed_value(value, :terminal, resolved_schema, _opts) do
    case resolved_schema do
      {:brand, module} -> module.new(value)
      {:schema, module} -> module.validate(value)
      {:base, base} -> Validator.validate_schema_base(value, base)
    end
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
  def schema_fail_fast_enabled?, do: Config.schema_fail_fast_enabled?()

  @spec build_key_lookup_context(map()) :: key_lookup_context()
  def build_key_lookup_context(params), do: MapValidator.build_key_lookup_context(params)

  @spec fetch_compiled_field_value(map(), [Definition.runtime_lookup_entry()]) ::
          {:ok, term(), atom() | String.t()} | :missing
  def fetch_compiled_field_value(params, lookup),
    do: MapValidator.fetch_compiled_field_value(params, lookup)

  @spec fetch_compiled_field_value(
          map(),
          [Definition.runtime_lookup_entry()],
          key_lookup_context()
        ) ::
          {:ok, term(), atom() | String.t()} | :missing
  def fetch_compiled_field_value(params, lookup, key_context),
    do: MapValidator.fetch_compiled_field_value(params, lookup, key_context)

  @spec accumulate_error(nil | map(), term(), term()) :: map()
  def accumulate_error(errors, key, reason), do: put_error(errors, key, reason)

  @spec extra_fields(map(), MapSet.t()) :: [term()]
  def extra_fields(value, consumed_keys), do: MapValidator.extra_fields(value, consumed_keys)

  defp apply_compiled_constraints(value, base_schema, metadata) do
    constraint_input = constraint_input(base_schema, value)
    generic_context = build_compiled_generic_context(constraint_input)

    with :ok <-
           run_compiled_generic_checks(constraint_input, metadata.generic_checks, generic_context),
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

  defp build_compiled_generic_context(value) when is_binary(value),
    do: %{string_length: String.length(value)}

  defp build_compiled_generic_context(_value), do: %{}

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

  defp check_deferred?(check), do: Config.deferred_check_enabled?(check)
  defp deep_nested_deferred?, do: check_deferred?(:deep_nested)

  defp put_error(nil, key, reason), do: %{key => reason}
  defp put_error(errors, key, reason), do: Map.put(errors, key, reason)
end
