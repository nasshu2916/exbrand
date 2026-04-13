defmodule ExBrand.Builder.Config do
  @moduledoc false

  @spec signature_verification_enabled?() :: boolean()
  def signature_verification_enabled? do
    Application.get_env(:ex_brand, :signature_verification, false)
  end
end
