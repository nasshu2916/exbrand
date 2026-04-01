defmodule ExBrand.Base do
  @moduledoc """
  ExBrand の base type 解決と custom base 拡張を担当する。

  組み込みの `:integer` / `:binary` / `:string` に加えて、
  利用側は callback を実装した module を `base:` に渡せる。
  """

  @type builtin() :: :integer | :binary | :string
  @type spec() :: builtin() | module() | {module(), keyword()}

  @callback type_ast(keyword()) :: Macro.t()
  @callback validate(term(), keyword()) :: :ok | {:error, term()}
  @callback ecto_type(keyword()) :: term()

  @doc """
  base 指定を正規化し、ExBrand で扱える形か検証する。
  """
  @spec normalize!(term()) :: spec()
  def normalize!(base) when base in [:integer, :binary, :string], do: base
  def normalize!(base) when is_atom(base), do: normalize_custom_module!(base)

  def normalize!({module, opts}) when is_atom(module) and is_list(opts) do
    if Keyword.keyword?(opts) do
      normalize_custom_module!(module, opts)
    else
      raise ArgumentError,
            "custom base options must be a keyword list, got: #{inspect(opts)}"
    end
  end

  def normalize!(other) do
    raise ArgumentError, "unsupported base type: #{inspect(other)}"
  end

  @doc """
  base に対応する raw type の AST を返す。
  """
  @spec type_ast!(spec()) :: Macro.t()
  def type_ast!(base) do
    case normalize!(base) do
      :integer -> quote(do: integer())
      :binary -> quote(do: binary())
      :string -> quote(do: String.t())
      module when is_atom(module) -> module.type_ast([])
      {module, opts} -> module.type_ast(opts)
    end
  end

  @doc """
  base type の検証を行う。
  """
  @spec validate(term(), spec()) :: :ok | {:error, term()}
  def validate(value, base) do
    case normalize!(base) do
      :integer when is_integer(value) -> :ok
      :binary when is_binary(value) -> :ok
      :string when is_binary(value) -> :ok
      :integer -> {:error, :invalid_type}
      :binary -> {:error, :invalid_type}
      :string -> {:error, :invalid_type}
      module when is_atom(module) -> module.validate(value, [])
      {module, opts} -> module.validate(value, opts)
    end
  end

  @doc """
  Ecto integration で使う type を返す。
  """
  @spec ecto_type!(spec()) :: term()
  def ecto_type!(base) do
    case normalize!(base) do
      :integer -> :integer
      :binary -> :binary
      :string -> :string
      module when is_atom(module) -> module.ecto_type([])
      {module, opts} -> module.ecto_type(opts)
    end
  end

  defp normalize_custom_module!(module, opts \\ []) do
    ensure_custom_base_loaded!(module)
    ensure_custom_base_callbacks!(module)

    case opts do
      [] -> module
      _ -> {module, opts}
    end
  end

  defp ensure_custom_base_loaded!(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "custom base module #{inspect(module)} could not be loaded: #{inspect(reason)}"
    end
  end

  defp ensure_custom_base_callbacks!(module) do
    Enum.each(
      [{:type_ast, 1}, {:validate, 2}, {:ecto_type, 1}],
      fn {name, arity} ->
        unless function_exported?(module, name, arity) do
          raise ArgumentError,
                "custom base module #{inspect(module)} must export #{name}/#{arity}"
        end
      end
    )
  end
end
