defmodule ExBrand.Builder do
  @moduledoc """
  ExBrand の brand module を生成する内部モジュール。
  """

  alias ExBrand.DSL

  @doc false
  @spec resolve_generator(term()) :: term()
  def resolve_generator(generator) when is_function(generator, 0), do: generator.()
  def resolve_generator(generator), do: generator

  @doc """
  親モジュール配下に生成する brand module の AST を返す。
  """
  @spec build_nested_brand(module(), Macro.t() | atom(), atom(), keyword()) :: Macro.t()
  def build_nested_brand(parent, name, base, opts) do
    module = Module.concat(parent, DSL.expand_name!(name))
    build_brand_module(module, Keyword.put(opts, :base, DSL.expand_base!(base)))
  end

  @doc """
  呼び出し元モジュール自身を brand module として構築する AST を返す。
  """
  @spec build_brand_inline(module(), keyword()) :: Macro.t()
  def build_brand_inline(module, opts) do
    normalized_opts = Keyword.update!(opts, :base, &DSL.expand_base!/1)

    quote do
      unquote(build_brand_body(module, normalized_opts))
      unquote_splicing(build_protocol_impls(module))
    end
  end

  defp build_brand_module(module, opts) do
    quote do
      defmodule unquote(module) do
        unquote(build_brand_body(module, opts))
      end

      unquote_splicing(build_protocol_impls(module))
    end
  end

  defp build_brand_body(module, opts) do
    base = Keyword.fetch!(opts, :base)
    raw_type = raw_type_ast(base)
    validate = Keyword.get(opts, :validate)
    error = Keyword.get(opts, :error)
    generator = Keyword.get(opts, :generator)
    name = normalize_name(Keyword.get(opts, :name), module)
    signature_verification = signature_verification_enabled?()
    secret = if signature_verification, do: generate_brand_secret(), else: nil
    derive = normalize_derive(Keyword.get(opts, :derive))

    quote do
      @moduledoc """
      `#{inspect(unquote(module))}` は ExBrand によって生成された brand module である。

      raw 値の生成には `new/1` または `new!/1` を使い、
      境界値の受け入れには `cast/1` または `cast!/1` を使い、
      取り出しには `unwrap/1` を使う。
      """

      if unquote(derive) do
        @derive unquote(derive)
      end

      unquote(signature_struct_ast(signature_verification))

      @type raw() :: unquote(raw_type)
      @type meta() :: %{
              module: module(),
              name: String.t(),
              base: :integer | :binary | :string,
              validator: function() | nil,
              generator: term() | nil,
              error: term() | nil
            }
      unquote(signature_type_ast(signature_verification))

      @base unquote(base)
      @error_reason unquote(error)
      @brand_name unquote(name)
      @signature_verification unquote(signature_verification)

      if @signature_verification do
        @brand_secret unquote(secret)
      end

      defp __validator__, do: unquote(validate)
      defp __generator__, do: unquote(generator)

      unquote(signature_helpers_ast(signature_verification))

      @doc """
      raw 値から brand 値を生成する。

      validator が正規化値を返した場合は、その値を内部に保持する。
      """
      @spec new(raw()) :: {:ok, t()} | {:error, term()}
      def new(value) do
        case ExBrand.Validator.validate(value, @base, __validator__(), @error_reason) do
          {:ok, normalized_value} ->
            {:ok, unquote(build_brand_struct_ast(signature_verification))}

          {:error, reason} ->
            {:error, reason}
        end
      end

      @doc """
      `new/1` の bang 版。

      生成に失敗した場合は `ExBrand.Error` を raise する。
      """
      @spec new!(raw()) :: t()
      def new!(value) do
        case new(value) do
          {:ok, brand} ->
            brand

          {:error, reason} ->
            raise ExBrand.Error, reason: reason, module: __MODULE__, value: value
        end
      end

      @doc """
      raw 値または同一 brand 値を受け取り、brand 値へ正規化する。

      すでに brand 値を受け取った場合も、内部 raw 値を再検証する。
      """
      @spec cast(raw() | t()) :: {:ok, t()} | {:error, term()}
      def cast(%__MODULE__{} = value) do
        value
        |> unwrap()
        |> new()
      end

      def cast(value), do: new(value)

      @doc """
      `cast/1` の bang 版。

      変換に失敗した場合は `ExBrand.Error` を raise する。
      """
      @spec cast!(raw() | t()) :: t()
      def cast!(value) do
        case cast(value) do
          {:ok, brand} ->
            brand

          {:error, reason} ->
            raise ExBrand.Error, reason: reason, module: __MODULE__, value: value
        end
      end

      @doc """
      brand 値から raw 値を明示的に取り出す。
      """
      @spec unwrap(t()) :: raw()

      def unwrap(%__MODULE__{__value__: value} = brand) do
        if __valid_signature__(brand) do
          value
        else
          raise ArgumentError, "invalid forged or mutated brand value for #{__name__()}"
        end
      end

      @doc """
      raw 値がその brand として受理可能かを返す。
      """
      @spec valid?(raw()) :: boolean()
      def valid?(value) do
        match?({:ok, _brand}, new(value))
      end

      @doc """
      property-based testing 向けの generator を返す。

      `generator:` に 0 引数関数を渡した場合は、その場で評価する。
      """
      @spec gen() :: term()
      def gen, do: ExBrand.Builder.resolve_generator(__generator__())

      @doc """
      渡された値が当該 brand の struct かを返す。
      """
      @spec is_brand?(term()) :: boolean()
      def is_brand?(%__MODULE__{} = brand), do: __valid_signature__(brand)
      def is_brand?(_), do: false

      @doc """
      この brand の base type を返す。
      """
      @spec __base__() :: :integer | :binary | :string
      def __base__, do: @base

      @doc """
      この brand の表示名を返す。
      """
      @spec __name__() :: String.t()
      def __name__, do: @brand_name

      @doc """
      この brand の定義メタデータを返す。
      """
      @spec __meta__() :: meta()
      def __meta__ do
        %{
          module: __MODULE__,
          name: @brand_name,
          base: @base,
          validator: __validator__(),
          generator: __generator__(),
          error: @error_reason
        }
      end

      @doc """
      この brand の reflection 情報を返す。

      `__meta__/0` の alias として使える。
      """
      @spec __brand__() :: meta()
      def __brand__, do: __meta__()
    end
  end

  defp build_protocol_impls(module) do
    [
      build_inspect_impl(module),
      build_string_chars_impl(module),
      build_json_encoder_impl(module),
      build_jason_encoder_impl(module),
      build_phoenix_param_impl(module)
    ]
  end

  defp build_inspect_impl(module) do
    quote do
      defimpl Inspect, for: unquote(module) do
        import Inspect.Algebra

        def inspect(value, opts) do
          concat([
            "#",
            unquote(module).__name__(),
            "<",
            to_doc(unquote(module).unwrap(value), opts),
            ">"
          ])
        end
      end
    end
  end

  defp build_string_chars_impl(module) do
    quote do
      defimpl String.Chars, for: unquote(module) do
        def to_string(value) do
          value
          |> unquote(module).unwrap()
          |> Kernel.to_string()
        end
      end
    end
  end

  defp build_jason_encoder_impl(module) do
    quote do
      if Code.ensure_loaded?(Jason.Encoder) do
        defimpl Jason.Encoder, for: unquote(module) do
          def encode(value, opts) do
            value
            |> unquote(module).unwrap()
            |> Jason.Encoder.encode(opts)
          end
        end
      end
    end
  end

  defp build_json_encoder_impl(module) do
    quote do
      if Code.ensure_loaded?(JSON.Encoder) do
        defimpl JSON.Encoder, for: unquote(module) do
          def encode(value, encoder) do
            value
            |> unquote(module).unwrap()
            |> JSON.Encoder.encode(encoder)
          end
        end
      end
    end
  end

  defp build_phoenix_param_impl(module) do
    quote do
      if Code.ensure_loaded?(Phoenix.Param) do
        defimpl Phoenix.Param, for: unquote(module) do
          def to_param(value) do
            value
            |> unquote(module).unwrap()
            |> Phoenix.Param.to_param()
          end
        end
      end
    end
  end

  defp raw_type_ast(:integer), do: quote(do: integer())
  defp raw_type_ast(:binary), do: quote(do: binary())
  defp raw_type_ast(:string), do: quote(do: String.t())

  defp signature_struct_ast(true) do
    quote do
      @enforce_keys [:__value__, :__signature__]
      defstruct [:__value__, :__signature__]
    end
  end

  defp signature_struct_ast(false) do
    quote do
      @enforce_keys [:__value__]
      defstruct [:__value__]
    end
  end

  defp signature_type_ast(true) do
    quote do
      @opaque t() :: %__MODULE__{__value__: raw(), __signature__: integer()}
    end
  end

  defp signature_type_ast(false) do
    quote do
      @opaque t() :: %__MODULE__{__value__: raw()}
    end
  end

  defp signature_helpers_ast(true) do
    quote do
      defp __sign__(value), do: :erlang.phash2({@brand_secret, value})

      defp __valid_signature__(%__MODULE__{__value__: value, __signature__: signature}) do
        signature == __sign__(value)
      end
    end
  end

  defp signature_helpers_ast(false) do
    quote do
      defp __valid_signature__(%__MODULE__{}), do: true
    end
  end

  defp build_brand_struct_ast(true) do
    quote do
      %__MODULE__{
        __value__: normalized_value,
        __signature__: __sign__(normalized_value)
      }
    end
  end

  defp build_brand_struct_ast(false) do
    quote do
      %__MODULE__{__value__: normalized_value}
    end
  end

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

  defp generate_brand_secret do
    :crypto.strong_rand_bytes(32)
  end

  defp signature_verification_enabled? do
    Application.get_env(:ex_brand, :signature_verification, false)
  end
end
