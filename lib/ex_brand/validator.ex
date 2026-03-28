defmodule ExBrand.Validator do
  @spec validate(term(), atom(), (term() -> term()) | nil, term() | nil) :: :ok | {:error, term()}
  def validate(value, base, validator, error) do
    with :ok <- validate_base(value, base) do
      validate_custom(value, validator, error)
    end
  end

  @spec validate_base(term(), atom()) :: :ok | {:error, :invalid_type}
  def validate_base(value, :integer) when is_integer(value), do: :ok
  def validate_base(value, :binary) when is_binary(value), do: :ok
  def validate_base(value, :string) when is_binary(value), do: :ok
  def validate_base(_, _), do: {:error, :invalid_type}

  @spec validate_custom(term(), (term() -> term()) | nil, term() | nil) :: :ok | {:error, term()}
  def validate_custom(_value, nil, _error), do: :ok

  def validate_custom(value, validator, error) when is_function(validator, 1) do
    run_validator(value, validator, error)
  end

  defp run_validator(value, validator, error) do
    case validator.(value) do
      true -> :ok
      false -> {:error, error || :invalid_value}
      :ok -> :ok
      {:ok, ^value} -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_validator_result, other}}
    end
  end
end
