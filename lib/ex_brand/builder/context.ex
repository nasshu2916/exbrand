defmodule ExBrand.Builder.Context do
  @moduledoc false

  alias ExBrand.Builder.Config

  @type derive_spec() :: nil | [term(), ...]
  @type t() :: %__MODULE__{
          module: module(),
          raw_type: Macro.t(),
          derive: derive_spec(),
          base: ExBrand.Base.spec(),
          error: term(),
          name: String.t(),
          signature_verification: boolean(),
          secret: binary() | nil,
          validate: term(),
          generator: term()
        }
  defstruct [
    :module,
    :raw_type,
    :derive,
    :base,
    :error,
    :name,
    :signature_verification,
    :secret,
    :validate,
    :generator
  ]

  @spec from_opts(module(), keyword()) :: t()
  def from_opts(module, opts) when is_list(opts) do
    base = Keyword.fetch!(opts, :base)
    signature_verification = Config.signature_verification_enabled?()

    %__MODULE__{
      module: module,
      raw_type: ExBrand.Base.type_ast!(base),
      derive: normalize_derive(Keyword.get(opts, :derive)),
      base: base,
      error: Keyword.get(opts, :error),
      name: normalize_name(Keyword.get(opts, :name), module),
      signature_verification: signature_verification,
      secret: build_secret(signature_verification),
      validate: Keyword.get(opts, :validate),
      generator: Keyword.get(opts, :generator)
    }
  end

  @spec build_secret(boolean()) :: binary() | nil
  defp build_secret(true), do: :crypto.strong_rand_bytes(32)
  defp build_secret(false), do: nil

  @spec normalize_derive(atom() | maybe_improper_list()) :: derive_spec()
  defp normalize_derive(nil), do: nil
  defp normalize_derive(derive) when is_atom(derive), do: normalize_derive([derive])

  defp normalize_derive(derive) when is_list(derive) do
    derive
    |> List.wrap()
    |> Enum.reject(&(&1 == Inspect))
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp normalize_derive(other) do
    raise ArgumentError, "derive must be a protocol or list of protocols, got: #{inspect(other)}"
  end

  @spec normalize_name(nil | String.t() | atom(), module()) :: String.t()
  defp normalize_name(nil, module) do
    module
    |> Module.split()
    |> List.last()
  end

  defp normalize_name(name, _module) when is_binary(name), do: name
  defp normalize_name(name, _module) when is_atom(name), do: Atom.to_string(name)

  defp normalize_name(other, _module) do
    raise ArgumentError, "name must be a string or atom, got: #{inspect(other)}"
  end
end
