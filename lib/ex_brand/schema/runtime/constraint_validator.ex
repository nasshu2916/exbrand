defmodule ExBrand.Schema.Runtime.ConstraintValidator do
  @moduledoc false

  alias ExBrand.Schema.Runtime.Config
  alias ExBrand.Validator

  @spec apply_constraints(term(), tuple(), map(), (term(), tuple() -> term())) ::
          {:ok, term()} | {:error, term()}
  def apply_constraints(value, base_schema, metadata, validate_schema)
      when is_function(validate_schema, 2) do
    constraint_input = constraint_input(base_schema, value)
    generic_context = build_generic_context(constraint_input)

    with :ok <- run_generic_checks(constraint_input, metadata.generic_checks, generic_context),
         {:ok, normalized_value} <-
           run_custom_validator(
             value,
             base_schema,
             metadata.validator,
             metadata.validator_error,
             validate_schema
           ) do
      {:ok, normalized_value}
    end
  end

  defp run_custom_validator(value, base_schema, validator, error, validate_schema) do
    Validator.apply_custom(
      constraint_input(base_schema, value),
      value,
      validator,
      error,
      &validate_schema.(&1, base_schema)
    )
  end

  defp build_generic_context(value) when is_binary(value),
    do: %{string_length: String.length(value)}

  defp build_generic_context(_value), do: %{}

  defp run_generic_checks(_value, [], _context), do: :ok

  defp run_generic_checks(value, [{:enum, enum_values} | rest], context) do
    if deferred?(:enum) do
      run_generic_checks(value, rest, context)
    else
      if value in enum_values,
        do: run_generic_checks(value, rest, context),
        else: {:error, :not_in_enum}
    end
  end

  defp run_generic_checks(value, [{:minimum, minimum} | rest], context) do
    if value >= minimum,
      do: run_generic_checks(value, rest, context),
      else: {:error, :less_than_minimum}
  end

  defp run_generic_checks(value, [{:maximum, maximum} | rest], context) do
    if value <= maximum,
      do: run_generic_checks(value, rest, context),
      else: {:error, :greater_than_maximum}
  end

  defp run_generic_checks(value, [{:min_length, minimum} | rest], %{string_length: length}) do
    if length >= minimum,
      do: run_generic_checks(value, rest, %{string_length: length}),
      else: {:error, :shorter_than_min_length}
  end

  defp run_generic_checks(value, [{:max_length, maximum} | rest], %{string_length: length}) do
    if length <= maximum,
      do: run_generic_checks(value, rest, %{string_length: length}),
      else: {:error, :longer_than_max_length}
  end

  defp run_generic_checks(value, [{:format, :email} | rest], context) do
    if deferred?(:format) or deferred?(:regex) do
      run_generic_checks(value, rest, context)
    else
      with :ok <- validate_email_format(value) do
        run_generic_checks(value, rest, context)
      end
    end
  end

  defp run_generic_checks(value, [{:format, :datetime} | rest], context) do
    if deferred?(:format) or deferred?(:regex) do
      run_generic_checks(value, rest, context)
    else
      with :ok <- validate_datetime_format(value) do
        run_generic_checks(value, rest, context)
      end
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

  defp constraint_input({:compiled, :terminal, {:brand, _module}, _opts}, value),
    do: ExBrand.unwrap!(value)

  defp constraint_input({:compiled, _kind, _data, _opts}, value), do: value

  defp deferred?(check), do: Config.deferred_check_enabled?(check)
end
