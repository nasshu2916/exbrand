defmodule ExBrand.Error do
  defexception [:message, :reason, :module, :value]

  @impl true
  def exception(opts) do
    reason = Keyword.fetch!(opts, :reason)
    module = Keyword.fetch!(opts, :module)
    value = Keyword.fetch!(opts, :value)

    %__MODULE__{
      message: build_message(module, reason, value),
      reason: reason,
      module: module,
      value: value
    }
  end

  defp build_message(module, reason, value) do
    "invalid brand value for #{inspect(module)}: #{inspect(reason)} (got #{inspect(value)})"
  end
end
