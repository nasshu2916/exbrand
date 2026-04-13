defmodule ExBrand.Schema.Runtime.Config do
  @moduledoc false

  @allowed_deferred_checks [:enum, :format, :regex, :unique_items, :deep_nested]
  @persistent_config_key :ex_brand_schema_runtime_config_persistent

  @type deferred_check() :: :enum | :format | :regex | :unique_items | :deep_nested
  @type runtime_option() ::
          {:fail_fast, term()}
          | {:deferred_checks, term()}
  @type t() :: %{
          fail_fast: boolean(),
          deferred_checks: MapSet.t(deferred_check()),
          defer_enum?: boolean(),
          defer_format?: boolean(),
          defer_regex?: boolean(),
          defer_unique_items?: boolean(),
          defer_deep_nested?: boolean()
        }

  @spec set_runtime_config!(keyword(runtime_option())) :: t()
  def set_runtime_config!(opts) when is_list(opts) do
    opts
    |> Enum.each(&put_runtime_option!/1)
    |> then(fn _ -> load_runtime_config_from_env!() end)
  end

  @spec schema_fail_fast_enabled?() :: boolean()
  def schema_fail_fast_enabled? do
    runtime_config().fail_fast
  end

  @spec deferred_check_enabled?(deferred_check()) :: boolean()
  def deferred_check_enabled?(:enum), do: runtime_config().defer_enum?
  def deferred_check_enabled?(:format), do: runtime_config().defer_format?
  def deferred_check_enabled?(:regex), do: runtime_config().defer_regex?
  def deferred_check_enabled?(:unique_items), do: runtime_config().defer_unique_items?
  def deferred_check_enabled?(:deep_nested), do: runtime_config().defer_deep_nested?

  @spec runtime_config() :: t()
  def runtime_config, do: persistent_runtime_config()

  defp persistent_runtime_config do
    case :persistent_term.get(@persistent_config_key, :unset) do
      %{fail_fast: _fail_fast, deferred_checks: _deferred_checks} = config ->
        config

      _ ->
        load_runtime_config_from_env!()
    end
  end

  defp put_runtime_option!({:fail_fast, :unset}) do
    Application.delete_env(:ex_brand, :schema_fail_fast)
  end

  defp put_runtime_option!({:fail_fast, value}) do
    Application.put_env(:ex_brand, :schema_fail_fast, value)
  end

  defp put_runtime_option!({:deferred_checks, :unset}) do
    Application.delete_env(:ex_brand, :schema_deferred_checks)
  end

  defp put_runtime_option!({:deferred_checks, value}) do
    Application.put_env(:ex_brand, :schema_deferred_checks, value)
  end

  defp put_runtime_option!({key, _value}) do
    raise ArgumentError, "unknown runtime option: #{inspect(key)}"
  end

  defp load_runtime_config_from_env! do
    config =
      runtime_config_raw_from_env()
      |> normalize_runtime_config()

    :persistent_term.put(@persistent_config_key, config)
    config
  end

  defp runtime_config_raw_from_env do
    %{
      fail_fast: Application.get_env(:ex_brand, :schema_fail_fast, false),
      deferred_checks: Application.get_env(:ex_brand, :schema_deferred_checks, [])
    }
  end

  defp normalize_runtime_config(raw) do
    deferred_checks =
      raw.deferred_checks
      |> List.wrap()
      |> Enum.filter(&(&1 in @allowed_deferred_checks))
      |> MapSet.new()

    %{
      fail_fast:
        case raw.fail_fast do
          true -> true
          false -> false
          _other -> false
        end,
      deferred_checks: deferred_checks,
      defer_enum?: MapSet.member?(deferred_checks, :enum),
      defer_format?: MapSet.member?(deferred_checks, :format),
      defer_regex?: MapSet.member?(deferred_checks, :regex),
      defer_unique_items?: MapSet.member?(deferred_checks, :unique_items),
      defer_deep_nested?: MapSet.member?(deferred_checks, :deep_nested)
    }
  end
end
