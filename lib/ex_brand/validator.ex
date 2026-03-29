defmodule ExBrand.Validator do
  @spec validate(term(), atom(), (term() -> term()) | nil, term() | nil) ::
          {:ok, term()} | {:error, term()}
  def validate(value, base, validator, error) do
    with :ok <- validate_base(value, base) do
      validate_custom(value, base, validator, error)
    end
  end

  @spec validate_base(term(), atom()) :: :ok | {:error, :invalid_type}
  def validate_base(value, :integer) when is_integer(value), do: :ok
  def validate_base(value, :binary) when is_binary(value), do: :ok
  def validate_base(value, :string) when is_binary(value), do: :ok
  def validate_base(_, _), do: {:error, :invalid_type}

  @spec validate_custom(term(), atom(), (term() -> term()) | nil, term() | nil) ::
          {:ok, term()} | {:error, term()}
  def validate_custom(value, _base, nil, _error), do: {:ok, value}

  def validate_custom(value, base, validator, error) when is_function(validator, 1) do
    run_validator(value, base, validator, error)
  end

  defp run_validator(value, base, validator, error) do
    case validator.(value) do
      true -> {:ok, value}
      false -> {:error, error || :invalid_value}
      :ok -> {:ok, value}
      {:ok, normalized_value} -> validate_normalized(normalized_value, base)
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_validator_result, other}}
    end
  end

  defp validate_normalized(value, base) do
    case validate_base(value, base) do
      :ok -> {:ok, value}
      {:error, :invalid_type} -> {:error, {:invalid_normalized_type, value}}
    end
  end
end
