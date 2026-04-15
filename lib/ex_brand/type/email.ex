defmodule ExBrand.Type.Email do
  @moduledoc """
  email 文字列を扱う組み込み custom type。
  """

  @behaviour ExBrand.Base

  @email_pattern ~r/^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  @impl true
  def type_ast(_opts), do: quote(do: String.t())

  @impl true
  def ecto_type(_opts), do: :string

  @impl true
  def validate(value, _opts) when is_binary(value) do
    if String.match?(value, @email_pattern), do: :ok, else: {:error, :invalid_email}
  end

  @impl true
  def validate(_value, _opts), do: {:error, :invalid_type}
end
