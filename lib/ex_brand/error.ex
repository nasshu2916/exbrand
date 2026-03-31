defmodule ExBrand.Error do
  @moduledoc """
  `new!/1` 系 API が失敗したときに送出される例外。
  """

  defexception [:message, :reason, :module, :value]

  @doc """
  `reason`, `module`, `value` から例外を構築する。
  """
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
    "invalid brand value for #{brand_label(module)}: #{inspect(reason)} (got #{inspect(value)})"
  end

  defp brand_label(module) do
    if function_exported?(module, :__name__, 0) do
      module.__name__()
    else
      inspect(module)
    end
  end
end
