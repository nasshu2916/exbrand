defmodule ExBrand.Ecto do
  @moduledoc """
  ExBrand の Ecto 統合向け補助関数を提供する。

  主に自動生成される `Ecto.Type` / `Ecto.ParameterizedType` 実装から利用される。
  """

  @doc """
  brand の base type を Ecto type として返す。
  """
  @spec type_for(module()) :: term()
  def type_for(brand), do: ExBrand.Base.ecto_type!(brand.__base__())

  @doc """
  Ecto 境界の cast を ExBrand の `cast/1` に委譲する。
  """
  @spec cast(module(), term()) :: {:ok, term()} | :error
  def cast(brand, value) do
    brand
    |> safe_call(fn module -> module.cast(value) end)
    |> normalize_brand_result()
  end

  @doc """
  DB から読み出した raw 値を brand に load する。
  """
  @spec load(module(), term()) :: {:ok, term()} | :error
  def load(brand, value) do
    brand
    |> safe_call(fn module -> module.load(value) end)
    |> normalize_brand_result()
  end

  @doc """
  brand 値または raw 値を dump 用の raw 値へ変換する。
  """
  @spec dump(module(), term()) :: {:ok, term()} | :error
  def dump(brand, value) do
    brand
    |> safe_call(fn module -> module.dump(value) end)
    |> normalize_brand_result()
  end

  @doc """
  `Ecto.ParameterizedType` の load を処理する。
  """
  @spec parameterized_load(module(), term(), (term() -> {:ok, term()} | :error)) ::
          {:ok, term()} | :error
  def parameterized_load(brand, value, loader) when is_function(loader, 1) do
    with {:ok, loaded_value} <- loader.(value) do
      load(brand, loaded_value)
    end
  end

  @doc """
  `Ecto.ParameterizedType` の dump を処理する。
  """
  @spec parameterized_dump(module(), term(), (term() -> {:ok, term()} | :error)) ::
          {:ok, term()} | :error
  def parameterized_dump(brand, value, dumper) when is_function(dumper, 1) do
    with {:ok, dumped_value} <- dump(brand, value) do
      dumper.(dumped_value)
    end
  end

  @doc """
  Ecto の equality 判定で使う比較を行う。
  """
  @spec equal?(module(), term(), term()) :: boolean()
  def equal?(brand, left, right) do
    case {cast(brand, left), cast(brand, right)} do
      {{:ok, left_brand}, {:ok, right_brand}} -> left_brand == right_brand
      _ -> false
    end
  end

  defp safe_call(brand, fun) do
    fun.(brand)
  rescue
    ArgumentError -> :error
  end

  defp normalize_brand_result({:ok, brand}), do: {:ok, brand}
  defp normalize_brand_result({:error, _reason}), do: :error
  defp normalize_brand_result(:error), do: :error
end
