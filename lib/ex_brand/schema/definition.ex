defmodule ExBrand.Schema.Definition do
  @moduledoc false

  alias ExBrand.Base

  @field_alias_keys [:required, :from]
  @schema_option_keys [
    :default,
    :enum,
    :error,
    :field,
    :format,
    :max_items,
    :max_length,
    :maximum,
    :min_items,
    :min_length,
    :minimum,
    :nullable,
    :optional,
    :tolerant,
    :unique_items,
    :validate
  ]
  @generic_constraint_keys [:default, :enum, :error, :nullable, :optional, :field, :validate]
  @map_constraint_keys [:tolerant | @generic_constraint_keys]
  @list_constraint_keys [:min_items, :max_items, :unique_items | @generic_constraint_keys]
  @string_constraint_keys [:format, :min_length, :max_length | @generic_constraint_keys]
  @numeric_constraint_keys [:minimum, :maximum | @generic_constraint_keys]

  @constraint_keys %{
    any: @generic_constraint_keys,
    boolean: @generic_constraint_keys,
    integer: @numeric_constraint_keys,
    number: @numeric_constraint_keys,
    null: @generic_constraint_keys,
    string: @string_constraint_keys,
    binary: @string_constraint_keys
  }

  @spec schema_option_keys() :: [atom(), ...]
  def schema_option_keys, do: @schema_option_keys

  @spec internal_error_key() :: :__extra_fields__
  def internal_error_key, do: :__extra_fields__

  @spec expand_schema(term(), Macro.Env.t()) :: term()
  def expand_schema({schema, opts}, env) when is_list(opts),
    do: {expand_schema(schema, env), opts}

  def expand_schema(schema, env) when is_list(schema),
    do: Enum.map(schema, &expand_schema(&1, env))

  def expand_schema(schema, env) when is_map(schema),
    do: Map.new(schema, fn {k, v} -> {k, expand_schema(v, env)} end)

  def expand_schema({:__aliases__, _, _} = schema, env), do: Macro.expand(schema, env)
  def expand_schema(schema, _env), do: schema

  @spec split_schema_opts(term()) :: {term(), keyword()}
  def split_schema_opts({schema, opts}) when is_list(opts), do: {schema, opts}
  def split_schema_opts(schema), do: {schema, []}

  @type runtime_node_kind() :: :list | :map | :terminal
  @type runtime_terminal() :: {:base, term()} | {:brand, module()} | {:schema, module()}
  @type runtime_node() ::
          {:compiled, runtime_node_kind(), runtime_terminal() | runtime_node() | map(), keyword()}

  @spec compile_runtime_schema!(term()) :: runtime_node()
  def compile_runtime_schema!(schema) do
    {base_schema, opts} = split_schema_opts(schema)

    cond do
      is_map(base_schema) ->
        compiled_fields =
          Map.new(base_schema, fn {name, field_schema} ->
            {name, compile_runtime_schema!(field_schema)}
          end)

        {:compiled, :map, compiled_fields, opts}

      is_list(base_schema) ->
        case base_schema do
          [item_schema] ->
            {:compiled, :list, compile_runtime_schema!(item_schema), opts}

          _ ->
            raise ArgumentError, "list schema must contain exactly one item schema"
        end

      true ->
        case resolve_terminal_schema(base_schema) do
          {:ok, resolved_schema} -> {:compiled, :terminal, resolved_schema, opts}
          :error -> raise ArgumentError, "invalid schema: #{inspect(schema)}"
        end
    end
  end

  @spec compiled_runtime_schema?(term()) :: boolean()
  def compiled_runtime_schema?({:compiled, kind, _data, opts})
      when kind in [:list, :map, :terminal] and is_list(opts),
      do: true

  def compiled_runtime_schema?(_schema), do: false

  @spec merge_field_opts(term(), keyword()) :: {term(), keyword()}
  def merge_field_opts(schema, opts) do
    {base_schema, schema_opts} = split_schema_opts(schema)
    merged_opts = Enum.reverse(Enum.reverse(schema_opts), normalize_field_opts(opts))
    {base_schema, merged_opts}
  end

  @spec normalize_field_opts(keyword()) :: keyword()
  def normalize_field_opts(opts) do
    Enum.flat_map(opts, fn
      {:required, false} -> [optional: true]
      {:required, true} -> [optional: false]
      {:from, field_name} -> [field: field_name]
      {key, value} when key in @schema_option_keys -> [{key, value}]
      {key, _value} when key in @field_alias_keys -> []
      {key, _value} -> raise ArgumentError, "unsupported field option: #{inspect(key)}"
    end)
  end

  @spec resolve_terminal_schema(term()) ::
          {:ok, {:base, term()} | {:brand, module()} | {:schema, module()}} | :error
  def resolve_terminal_schema(schema) when is_atom(schema) do
    cond do
      schema in [:any, :boolean, :integer, :number, :null, :string, :binary] ->
        {:ok, {:base, schema}}

      brand_module?(schema) ->
        {:ok, {:brand, schema}}

      schema_module?(schema) ->
        {:ok, {:schema, schema}}

      true ->
        {:ok, {:base, Base.normalize!(schema)}}
    end
  rescue
    ArgumentError -> :error
  end

  def resolve_terminal_schema({schema, opts}) when is_list(opts) do
    {_schema_opts, type_opts} = Keyword.split(opts, [:required, :from | @schema_option_keys])

    cond do
      schema_module?(schema) ->
        if type_opts == [], do: {:ok, {:schema, schema}}, else: :error

      brand_module?(schema) ->
        if type_opts == [], do: {:ok, {:brand, schema}}, else: :error

      true ->
        {:ok, {:base, Base.normalize!({schema, type_opts})}}
    end
  rescue
    ArgumentError -> :error
  end

  def resolve_terminal_schema(_schema), do: :error

  @spec validate_constraint_values!(keyword(), String.t()) :: :ok
  def validate_constraint_values!(opts, path) do
    Enum.each(opts, fn
      {:default, _value} ->
        :ok

      {:enum, value} when is_list(value) ->
        :ok

      {:error, _value} ->
        :ok

      {:field, value} when is_atom(value) or is_binary(value) ->
        :ok

      {:format, value} when value in [:email, :datetime] ->
        :ok

      {:max_items, value} when is_integer(value) and value >= 0 ->
        :ok

      {:max_length, value} when is_integer(value) and value >= 0 ->
        :ok

      {:maximum, value} when is_number(value) ->
        :ok

      {:min_items, value} when is_integer(value) and value >= 0 ->
        :ok

      {:min_length, value} when is_integer(value) and value >= 0 ->
        :ok

      {:minimum, value} when is_number(value) ->
        :ok

      {:nullable, value} when is_boolean(value) ->
        :ok

      {:optional, value} when is_boolean(value) ->
        :ok

      {:tolerant, value} when is_boolean(value) ->
        :ok

      {:unique_items, value} when is_boolean(value) ->
        :ok

      {:validate, value} when is_function(value, 1) ->
        :ok

      {key, value} ->
        raise ArgumentError,
              "invalid constraint value at #{path}: #{inspect(key)} => #{inspect(value)}"
    end)

    :ok
  end

  @spec ensure_allowed_constraints!(keyword(), [atom()], String.t(), atom()) :: :ok
  def ensure_allowed_constraints!(opts, allowed_keys, path, schema_kind) do
    invalid_keys =
      opts
      |> Keyword.keys()
      |> Enum.uniq()
      |> Enum.reject(&(&1 in allowed_keys))

    case invalid_keys do
      [] ->
        :ok

      keys ->
        joined = Enum.map_join(keys, ", ", &inspect/1)
        raise ArgumentError, "unsupported constraints for #{schema_kind} at #{path}: #{joined}"
    end
  end

  @spec validate_terminal_schema_definition!(term(), keyword(), String.t()) :: :ok
  def validate_terminal_schema_definition!(base_schema, opts, path) do
    case infer_constraint_profile(base_schema) do
      {:ok, {:scalar, scalar_type}} ->
        ensure_allowed_constraints!(
          opts,
          Map.fetch!(@constraint_keys, scalar_type),
          path,
          scalar_type
        )

      {:ok, {:brand, profile}} ->
        ensure_allowed_constraints!(
          opts,
          allowed_constraint_keys_for_profile(profile),
          path,
          :brand
        )

      {:ok, {:nested_schema, _module}} ->
        ensure_allowed_constraints!(opts, @generic_constraint_keys, path, :schema)

      :error ->
        raise ArgumentError, "invalid schema at #{path}: #{inspect(base_schema)}"
    end
  end

  @typep scalar_profile ::
           :any | :binary | :boolean | :custom_base | :integer | :null | :number | :string
  @typep map_constraint_key ::
           :default | :enum | :error | :field | :nullable | :optional | :tolerant | :validate
  @typep list_constraint_key ::
           :default
           | :enum
           | :error
           | :field
           | :max_items
           | :min_items
           | :nullable
           | :optional
           | :unique_items
           | :validate

  @spec infer_constraint_profile(term()) ::
          {:ok,
           {:scalar, scalar_profile()} | {:brand, scalar_profile()} | {:nested_schema, atom()}}
          | :error
  def infer_constraint_profile(schema) do
    case resolve_terminal_schema(schema) do
      {:ok, {:base, base}} -> {:ok, {:scalar, scalar_profile_for_base(base)}}
      {:ok, {:brand, module}} -> {:ok, {:brand, scalar_profile_for_brand(module)}}
      {:ok, {:schema, module}} -> {:ok, {:nested_schema, module}}
      :error -> :error
    end
  end

  @spec allowed_constraint_keys_for_profile(scalar_profile()) :: [atom(), ...]
  def allowed_constraint_keys_for_profile(:custom_base), do: @generic_constraint_keys
  def allowed_constraint_keys_for_profile(profile), do: Map.fetch!(@constraint_keys, profile)

  @spec scalar_profile_for_brand(module()) :: scalar_profile()
  def scalar_profile_for_brand(module) do
    case module.__base__() do
      :integer -> :integer
      :string -> :string
      :binary -> :binary
      :any -> :any
      :boolean -> :boolean
      :number -> :number
      :null -> :null
      {_module, _opts} -> :custom_base
      _other -> :custom_base
    end
  end

  @spec scalar_profile_for_base(term()) :: scalar_profile()
  def scalar_profile_for_base(base)
      when base in [:any, :boolean, :integer, :number, :null, :string, :binary],
      do: base

  def scalar_profile_for_base({_module, _opts}), do: :custom_base
  def scalar_profile_for_base(_base), do: :custom_base

  @spec brand_module?(term()) :: boolean()
  def brand_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__meta__, 0) and
      function_exported?(module, :cast, 1)
  end

  def brand_module?(_module), do: false

  @spec schema_module?(term()) :: boolean()
  def schema_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__schema__, 0) and
      function_exported?(module, :validate, 1)
  end

  def schema_module?(_module), do: false

  @spec map_constraint_keys() :: [map_constraint_key(), ...]
  def map_constraint_keys, do: @map_constraint_keys

  @spec list_constraint_keys() :: [list_constraint_key(), ...]
  def list_constraint_keys, do: @list_constraint_keys
end
