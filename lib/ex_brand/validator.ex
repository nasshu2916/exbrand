defmodule ExBrand.Validator do
  @moduledoc """
  ExBrand の validator 実行と base type 検証を担当する補助モジュール。

  主に ExBrand 内部から利用される。
  """

  alias ExBrand.Base

  @doc """
  base type と validator を順に適用し、brand に格納する raw 値を返す。
  """
  @spec validate(term(), ExBrand.Base.spec(), (term() -> term()) | nil, term() | nil) ::
          {:ok, term()} | {:error, term()}
  def validate(value, base, validator, error) do
    with :ok <- validate_base(value, base) do
      validate_custom(value, base, validator, error)
    end
  end

  @doc """
  raw 値が指定した base type に適合するかを検証する。
  """
  @spec validate_base(term(), ExBrand.Base.spec()) :: :ok | {:error, term()}
  def validate_base(value, base), do: Base.validate(value, base)

  @doc """
  custom validator を適用し、必要なら正規化後の raw 値を返す。
  """
  @spec validate_custom(term(), ExBrand.Base.spec(), (term() -> term()) | nil, term() | nil) ::
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
