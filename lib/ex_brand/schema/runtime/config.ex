defmodule ExBrand.Schema.Runtime.Config do
  @moduledoc false

  @runtime_config_key :ex_brand_schema_runtime_config

  @type t() :: %{
          fail_fast: boolean(),
          deferred_checks: MapSet.t(atom())
        }

  @spec with_runtime_config((-> term())) :: term()
  def with_runtime_config(fun) when is_function(fun, 0) do
    previous_config = Process.get(@runtime_config_key, :unset)
    Process.put(@runtime_config_key, runtime_config_from_env())

    try do
      fun.()
    after
      case previous_config do
        :unset -> Process.delete(@runtime_config_key)
        value -> Process.put(@runtime_config_key, value)
      end
    end
  end

  @spec schema_fail_fast_enabled?() :: boolean()
  def schema_fail_fast_enabled? do
    runtime_config().fail_fast
  end

  @spec schema_deferred_checks() :: MapSet.t(atom())
  def schema_deferred_checks do
    runtime_config().deferred_checks
  end

  @spec runtime_config() :: t()
  def runtime_config do
    case Process.get(@runtime_config_key) do
      nil -> runtime_config_from_env()
      config -> config
    end
  end

  @spec runtime_config_from_env() :: t()
  def runtime_config_from_env do
    %{
      fail_fast:
        case Application.get_env(:ex_brand, :schema_fail_fast, false) do
          true -> true
          false -> false
          _other -> false
        end,
      deferred_checks:
        Application.get_env(:ex_brand, :schema_deferred_checks, [])
        |> List.wrap()
        |> Enum.filter(&(&1 in [:enum, :format, :regex, :unique_items, :deep_nested]))
        |> MapSet.new()
    }
  end
end
