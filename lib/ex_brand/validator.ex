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
    normalized_base = Base.normalize!(base)

    with :ok <- validate_base_normalized(value, normalized_base) do
      validate_custom(value, normalized_base, validator, error)
    end
  end

  @doc """
  raw 値が指定した base type に適合するかを検証する。
  """
  @spec validate_base(term(), ExBrand.Base.spec()) :: :ok | {:error, term()}
  def validate_base(value, base) do
    base
    |> Base.normalize!()
    |> validate_base_normalized(value)
  end

  @doc """
  custom validator を適用し、必要なら正規化後の raw 値を返す。
  """
  @spec validate_custom(term(), ExBrand.Base.spec(), (term() -> term()) | nil, term() | nil) ::
          {:ok, term()} | {:error, term()}
  def validate_custom(value, base, validator, error) do
    apply_custom(value, value, validator, error, &validate_normalized(&1, base))
  end

  @doc """
  schema などの呼び出し側で使える共通 base 検証を行う。

  `:any`, `:boolean`, `:number`, `:null` のような schema 専用 scalar も扱う。
  """
  @spec validate_schema_base(term(), term()) :: {:ok, term()} | {:error, term()}
  def validate_schema_base(value, :any), do: {:ok, value}
  def validate_schema_base(value, :boolean) when is_boolean(value), do: {:ok, value}
  def validate_schema_base(_value, :boolean), do: {:error, :invalid_type}
  def validate_schema_base(value, :number) when is_number(value), do: {:ok, value}
  def validate_schema_base(_value, :number), do: {:error, :invalid_type}
  def validate_schema_base(nil, :null), do: {:ok, nil}
  def validate_schema_base(_value, :null), do: {:error, :invalid_type}

  def validate_schema_base(value, base) do
    normalized_base = Base.normalize!(base)

    case validate_base_normalized(value, normalized_base) do
      :ok -> {:ok, value}
      {:error, reason} -> {:error, reason}
    end
  rescue
    ArgumentError -> {:error, :invalid_schema}
  end

  @doc """
  schema などが validator 戻り値の解釈だけを共通利用するときに使う。
  """
  @spec apply_custom(
          term(),
          term(),
          (term() -> term()) | nil,
          term() | nil,
          (term() -> {:ok, term()} | {:error, term()})
        ) :: {:ok, term()} | {:error, term()}
  def apply_custom(_input_value, success_value, nil, _error, _validate_normalized) do
    {:ok, success_value}
  end

  def apply_custom(input_value, success_value, validator, error, validate_normalized)
      when is_function(validator, 1) and is_function(validate_normalized, 1) do
    run_validator(input_value, success_value, validator, error, validate_normalized)
  end

  defp run_validator(input_value, success_value, validator, error, validate_normalized) do
    case validator.(input_value) do
      true -> {:ok, success_value}
      false -> {:error, error || :invalid_value}
      :ok -> {:ok, success_value}
      {:ok, normalized_value} -> validate_normalized.(normalized_value)
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_validator_result, other}}
    end
  end

  defp validate_normalized(value, base) do
    case validate_base_normalized(value, base) do
      :ok -> {:ok, value}
      {:error, :invalid_type} -> {:error, {:invalid_normalized_type, value}}
    end
  end

  defp validate_base_normalized(value, base), do: Base.validate_normalized(base, value)
end
