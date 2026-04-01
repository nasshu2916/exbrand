defmodule ExBrand.Schema do
  @moduledoc """
  `simple_schema` 風の宣言的な schema DSL と実行時バリデーションを提供する。

  主な制約は型指定の tuple にまとめて記述できる。

      field :age, {:integer, minimum: 18}
      field :email, {:string, format: :email}
      field :tags, {[{:string, min_length: 1}], min_items: 1}

  field option として渡していた `required:`, `default:`, `from:`, `validate:`, `error:`
  も後方互換のため引き続き利用できる。
  """

  alias ExBrand.Base

  @type scalar_schema() ::
          :any | :boolean | :integer | :number | :null | :string | :binary
  @type schema() ::
          scalar_schema()
          | module()
          | {schema(), keyword()}
          | [schema()]
          | %{atom() => schema()}
  @type schema_definition() :: schema()

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
  @internal_error_key :__extra_fields__

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

  @doc """
  Schema DSL を導入する。
  """
  defmacro __using__(opts \\ []) do
    tolerant = Keyword.get(opts, :tolerant, false)

    quote bind_quoted: [tolerant: tolerant] do
      import ExBrand.Schema, only: [field: 2, field: 3]

      Module.register_attribute(__MODULE__, :ex_brand_schema_fields, accumulate: true)
      Module.put_attribute(__MODULE__, :ex_brand_schema_tolerant, tolerant)
      @before_compile ExBrand.Schema
    end
  end

  @doc """
  schema field を 1 つ定義する。
  """
  defmacro field(name, schema, opts \\ []) do
    expanded_schema = expand_schema(schema, __CALLER__)

    quote do
      @ex_brand_schema_fields {
        unquote(Macro.escape(name)),
        unquote(Macro.escape(expanded_schema)),
        unquote(Macro.escape(opts))
      }
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    tolerant = Module.get_attribute(env.module, :ex_brand_schema_tolerant)

    fields_ast =
      env.module
      |> Module.get_attribute(:ex_brand_schema_fields)
      |> Enum.reverse()
      |> Enum.map(&build_field_ast!/1)

    schema_ast =
      quote do
        {
          %{unquote_splicing(fields_ast)},
          tolerant: unquote(tolerant)
        }
      end

    quote do
      @doc """
      schema 定義を返す。
      """
      @spec __schema__() :: ExBrand.Schema.schema_definition()
      def __schema__, do: unquote(schema_ast)

      @doc """
      入力値を schema 定義に従って検証し、正規化済みの値を返す。
      """
      @spec validate(term()) :: {:ok, term()} | {:error, term()}
      def validate(params) do
        ExBrand.Schema.validate(params, __schema__())
      end

      @doc """
      `validate/1` の bang 版。
      """
      @spec validate!(term()) :: term()
      def validate!(params) do
        ExBrand.Schema.validate!(params, __MODULE__, __schema__())
      end

      @doc """
      入力値が schema に適合するかを返す。
      """
      @spec valid?(term()) :: boolean()
      def valid?(params) do
        match?({:ok, _result}, validate(params))
      end
    end
  end

  @doc """
  schema 定義に従って値を検証する。
  """
  @spec validate(term(), schema_definition()) :: {:ok, term()} | {:error, term()}
  def validate(value, schema) do
    validate_schema(value, schema)
  end

  @doc """
  schema 定義に従って値を検証し、失敗時は例外を送出する。
  """
  @spec validate!(term(), module(), schema_definition()) :: term()
  def validate!(value, module, schema) do
    case validate(value, schema) do
      {:ok, normalized_value} ->
        normalized_value

      {:error, reason} ->
        raise ArgumentError,
              "invalid schema value for #{inspect(module)}: #{inspect(reason)}"
    end
  end

  defp build_field_ast!({name, schema, opts}) do
    unless is_atom(name) do
      raise ArgumentError, "field name must be an atom, got: #{inspect(name)}"
    end

    unless Keyword.keyword?(opts) do
      raise ArgumentError, "field options must be a keyword list, got: #{inspect(opts)}"
    end

    merged_schema = merge_field_opts(schema, opts)
    validate_schema_definition!(merged_schema, "field #{inspect(name)}")

    quote do
      {unquote(name), unquote(Macro.escape(merged_schema))}
    end
  end

  defp merge_field_opts(schema, opts) do
    {base_schema, schema_opts} = split_schema_opts(schema)
    merged_opts = Enum.reverse(Enum.reverse(schema_opts), normalize_field_opts(opts))
    {base_schema, merged_opts}
  end

  defp split_schema_opts({schema, opts}) when is_list(opts) do
    {schema, opts}
  end

  defp split_schema_opts(schema), do: {schema, []}

  defp normalize_field_opts(opts) do
    Enum.flat_map(opts, fn
      {:required, false} -> [optional: true]
      {:required, true} -> [optional: false]
      {:from, field_name} -> [field: field_name]
      {key, value} when key in @schema_option_keys -> [{key, value}]
      {key, _value} when key in @field_alias_keys -> []
      {key, _value} -> raise ArgumentError, "unsupported field option: #{inspect(key)}"
    end)
  end

  defp validate_schema_definition!(schema, path) do
    {base_schema, opts} = split_schema_opts(schema)
    validate_constraint_values!(opts, path)

    cond do
      is_map(base_schema) ->
        ensure_allowed_constraints!(opts, @map_constraint_keys, path, :map)

        Enum.each(base_schema, fn {field_name, field_schema} ->
          validate_schema_definition!(field_schema, "#{path}.#{field_name}")
        end)

      is_list(base_schema) ->
        case base_schema do
          [item_schema] ->
            ensure_allowed_constraints!(opts, @list_constraint_keys, path, :list)
            validate_schema_definition!(item_schema, "#{path}[]")

          _ ->
            raise ArgumentError,
                  "invalid schema at #{path}: list schema must contain exactly one item schema"
        end

      true ->
        validate_terminal_schema_definition!(base_schema, opts, path)
    end
  end

  defp validate_terminal_schema_definition!(base_schema, opts, path) do
    case infer_constraint_profile(base_schema) do
      {:ok, {:scalar, scalar_type}} ->
        allowed_keys = Map.fetch!(@constraint_keys, scalar_type)
        ensure_allowed_constraints!(opts, allowed_keys, path, scalar_type)

      {:ok, {:brand, profile}} ->
        allowed_keys = allowed_constraint_keys_for_profile(profile)
        ensure_allowed_constraints!(opts, allowed_keys, path, :brand)

      {:ok, {:nested_schema, _module}} ->
        ensure_allowed_constraints!(opts, @generic_constraint_keys, path, :schema)

      :error ->
        raise ArgumentError, "invalid schema at #{path}: #{inspect(base_schema)}"
    end
  end

  defp validate_constraint_values!(opts, path) do
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
  end

  defp ensure_allowed_constraints!(opts, allowed_keys, path, schema_kind) do
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

        raise ArgumentError,
              "unsupported constraints for #{schema_kind} at #{path}: #{joined}"
    end
  end

  defp allowed_constraint_keys_for_profile(profile) do
    case profile do
      :any -> @generic_constraint_keys
      :boolean -> Map.fetch!(@constraint_keys, :boolean)
      :integer -> Map.fetch!(@constraint_keys, :integer)
      :number -> Map.fetch!(@constraint_keys, :number)
      :null -> Map.fetch!(@constraint_keys, :null)
      :string -> Map.fetch!(@constraint_keys, :string)
      :binary -> Map.fetch!(@constraint_keys, :binary)
      :custom_base -> @generic_constraint_keys
    end
  end

  defp infer_constraint_profile(schema) do
    case resolve_terminal_schema(schema) do
      {:ok, {:base, base}} ->
        {:ok, {:scalar, scalar_profile_for_base(base)}}

      {:ok, {:brand, module}} ->
        {:ok, {:brand, scalar_profile_for_brand(module)}}

      {:ok, {:schema, module}} ->
        {:ok, {:nested_schema, module}}

      :error ->
        :error
    end
  end

  defp scalar_profile_for_brand(module) do
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

  defp scalar_profile_for_base(base)
       when base in [:any, :boolean, :integer, :number, :null, :string, :binary],
       do: base

  defp scalar_profile_for_base({_module, _opts}), do: :custom_base
  defp scalar_profile_for_base(_base), do: :custom_base

  defp validate_schema(value, schema) do
    {base_schema, opts} = split_schema_opts(schema)

    cond do
      Keyword.get(opts, :nullable, false) and is_nil(value) ->
        {:ok, nil}

      true ->
        with {:ok, typed_value} <- validate_typed_value(value, base_schema, opts),
             {:ok, constrained_value} <- apply_constraints(typed_value, base_schema, opts) do
          {:ok, constrained_value}
        else
          {:error, reason} -> {:error, wrap_error(reason, opts)}
        end
    end
  end

  defp validate_typed_value(value, schema, opts) when is_map(schema) do
    validate_map(value, schema, opts)
  end

  defp validate_typed_value(value, [item_schema], opts) do
    validate_list(value, item_schema, opts)
  end

  defp validate_typed_value(_value, [], _opts), do: {:error, :invalid_schema}

  defp validate_typed_value(value, schema, _opts) do
    case resolve_terminal_schema(schema) do
      {:ok, {:brand, module}} ->
        module.cast(value)

      {:ok, {:schema, module}} ->
        module.validate(value)

      {:ok, {:base, base}} ->
        validate_base_value(value, base)

      :error ->
        {:error, :invalid_schema}
    end
  end

  defp validate_map(value, schema_fields, opts) when is_map(value) do
    tolerant = Keyword.get(opts, :tolerant, false)

    {normalized, errors, consumed_keys} =
      Enum.reduce(schema_fields, {%{}, %{}, MapSet.new()}, fn {name, field_schema},
                                                              {normalized, errors, consumed_keys} ->
        {field_schema_base, field_opts} = split_schema_opts(field_schema)

        case fetch_field_value(value, name, field_opts) do
          {:ok, field_value, used_key} ->
            case validate_schema(
                   field_value,
                   {field_schema_base, Keyword.delete(field_opts, :field)}
                 ) do
              {:ok, normalized_value} ->
                {
                  Map.put(normalized, name, normalized_value),
                  errors,
                  MapSet.put(consumed_keys, used_key)
                }

              {:error, reason} ->
                {
                  normalized,
                  Map.put(errors, name, reason),
                  MapSet.put(consumed_keys, used_key)
                }
            end

          :missing ->
            handle_missing_field(
              name,
              field_schema_base,
              field_opts,
              normalized,
              errors,
              consumed_keys
            )
        end
      end)

    errors =
      if tolerant do
        errors
      else
        append_extra_field_errors(value, consumed_keys, errors)
      end

    case map_size(errors) do
      0 -> {:ok, normalized}
      _ -> {:error, errors}
    end
  end

  defp validate_map(_value, _schema_fields, _opts), do: {:error, :invalid_type}

  defp validate_list(value, item_schema, opts) when is_list(value) do
    {normalized_items, item_errors} =
      value
      |> Enum.with_index()
      |> Enum.reduce({[], %{}}, fn {item, index}, {normalized_items, item_errors} ->
        case validate_schema(item, item_schema) do
          {:ok, normalized_item} ->
            {[normalized_item | normalized_items], item_errors}

          {:error, reason} ->
            {normalized_items, Map.put(item_errors, index, reason)}
        end
      end)

    normalized_items = Enum.reverse(normalized_items)

    case apply_list_constraints(value, normalized_items, item_errors, opts) do
      {:ok, normalized_value} -> {:ok, normalized_value}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_list(_value, _item_schema, _opts), do: {:error, :invalid_type}

  defp handle_missing_field(name, field_schema, field_opts, normalized, errors, consumed_keys) do
    cond do
      Keyword.has_key?(field_opts, :default) ->
        case validate_schema(Keyword.fetch!(field_opts, :default), field_schema) do
          {:ok, default_value} ->
            {Map.put(normalized, name, default_value), errors, consumed_keys}

          {:error, reason} ->
            {normalized, Map.put(errors, name, reason), consumed_keys}
        end

      Keyword.get(field_opts, :optional, false) ->
        {Map.put(normalized, name, nil), errors, consumed_keys}

      true ->
        {normalized, Map.put(errors, name, :required), consumed_keys}
    end
  end

  defp append_extra_field_errors(value, consumed_keys, errors) do
    extra_fields =
      value
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(consumed_keys, &1))

    case extra_fields do
      [] -> errors
      _ -> Map.put(errors, @internal_error_key, Enum.sort(extra_fields))
    end
  end

  defp fetch_field_value(params, name, opts) do
    external_name = Keyword.get(opts, :field, name)

    cond do
      is_atom(external_name) and Map.has_key?(params, external_name) ->
        {:ok, Map.fetch!(params, external_name), external_name}

      is_atom(external_name) and Map.has_key?(params, Atom.to_string(external_name)) ->
        key = Atom.to_string(external_name)
        {:ok, Map.fetch!(params, key), key}

      is_binary(external_name) and Map.has_key?(params, external_name) ->
        {:ok, Map.fetch!(params, external_name), external_name}

      is_binary(external_name) and atomizable_key?(external_name) and
          Map.has_key?(params, String.to_atom(external_name)) ->
        key = String.to_atom(external_name)
        {:ok, Map.fetch!(params, key), key}

      true ->
        :missing
    end
  end

  defp atomizable_key?(key) do
    try do
      _ = String.to_existing_atom(key)
      true
    rescue
      ArgumentError -> false
    end
  end

  defp validate_base_value(value, :any), do: {:ok, value}
  defp validate_base_value(value, :boolean) when is_boolean(value), do: {:ok, value}
  defp validate_base_value(_value, :boolean), do: {:error, :invalid_type}
  defp validate_base_value(value, :number) when is_number(value), do: {:ok, value}
  defp validate_base_value(_value, :number), do: {:error, :invalid_type}
  defp validate_base_value(nil, :null), do: {:ok, nil}
  defp validate_base_value(_value, :null), do: {:error, :invalid_type}

  defp validate_base_value(value, base) do
    case Base.normalize!(base) do
      normalized_base ->
        case ExBrand.Validator.validate(value, normalized_base, nil, nil) do
          {:ok, normalized_value} -> {:ok, normalized_value}
          {:error, reason} -> {:error, reason}
        end
    end
  rescue
    ArgumentError ->
      {:error, :invalid_schema}
  end

  defp apply_constraints(value, base_schema, opts) do
    constraint_input = constraint_input(base_schema, value)

    with :ok <- validate_enum(constraint_input, opts),
         :ok <- validate_numeric(constraint_input, opts),
         :ok <- validate_length(constraint_input, opts),
         :ok <- validate_format(constraint_input, opts),
         {:ok, normalized_value} <- run_custom_validator(value, base_schema, opts) do
      {:ok, normalized_value}
    end
  end

  defp apply_list_constraints(original_items, normalized_items, item_errors, opts) do
    errors =
      item_errors
      |> maybe_put_self_error(check_min_items(original_items, opts))
      |> maybe_put_self_error(check_max_items(original_items, opts))
      |> maybe_put_self_error(check_unique_items(original_items, opts))

    case map_size(errors) do
      0 -> {:ok, normalized_items}
      _ -> {:error, errors}
    end
  end

  defp maybe_put_self_error(errors, :ok), do: errors

  defp maybe_put_self_error(errors, {:error, reason}) do
    Map.put(errors, :__self__, reason)
  end

  defp validate_enum(value, opts) do
    case Keyword.fetch(opts, :enum) do
      {:ok, enum_values} when is_list(enum_values) ->
        if value in enum_values, do: :ok, else: {:error, :not_in_enum}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp validate_numeric(value, opts) when is_number(value) do
    with :ok <- check_minimum(value, opts),
         :ok <- check_maximum(value, opts) do
      :ok
    end
  end

  defp validate_numeric(_value, _opts), do: :ok

  defp validate_length(value, opts) when is_binary(value) do
    length = String.length(value)

    with :ok <- check_min_length(length, opts),
         :ok <- check_max_length(length, opts) do
      :ok
    end
  end

  defp validate_length(_value, _opts), do: :ok

  defp validate_format(value, opts) when is_binary(value) do
    case Keyword.get(opts, :format) do
      nil -> :ok
      :email -> validate_email_format(value)
      :datetime -> validate_datetime_format(value)
      _other -> {:error, :invalid_schema}
    end
  end

  defp validate_format(_value, opts) do
    case Keyword.get(opts, :format) do
      nil -> :ok
      _other -> {:error, :invalid_type}
    end
  end

  defp validate_email_format(value) do
    if String.match?(value, ~r/^[^\s]+@[^\s]+\.[^\s]+$/) do
      :ok
    else
      {:error, :invalid_format}
    end
  end

  defp validate_datetime_format(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} -> :ok
      _ -> {:error, :invalid_format}
    end
  end

  defp run_custom_validator(value, base_schema, opts) do
    case Keyword.get(opts, :validate) do
      nil ->
        {:ok, value}

      validator when is_function(validator, 1) ->
        validator_input = constraint_input(base_schema, value)

        case validator.(validator_input) do
          true -> {:ok, value}
          false -> {:error, Keyword.get(opts, :error, :invalid_value)}
          :ok -> {:ok, value}
          {:ok, normalized_value} -> validate_schema(normalized_value, base_schema)
          {:error, reason} -> {:error, reason}
          other -> {:error, {:invalid_validator_result, other}}
        end
    end
  end

  defp constraint_input(schema, value) do
    case resolve_terminal_schema(schema) do
      {:ok, {:brand, _module}} -> ExBrand.unwrap(value)
      _ -> value
    end
  end

  defp wrap_error(reason, opts) do
    case Keyword.fetch(opts, :error) do
      {:ok, custom_error} -> custom_error
      :error -> reason
    end
  end

  defp check_minimum(value, opts) do
    case Keyword.fetch(opts, :minimum) do
      {:ok, minimum} when is_number(minimum) ->
        if value >= minimum, do: :ok, else: {:error, :less_than_minimum}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_maximum(value, opts) do
    case Keyword.fetch(opts, :maximum) do
      {:ok, maximum} when is_number(maximum) ->
        if value <= maximum, do: :ok, else: {:error, :greater_than_maximum}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_min_length(length, opts) do
    case Keyword.fetch(opts, :min_length) do
      {:ok, minimum} when is_integer(minimum) and minimum >= 0 ->
        if length >= minimum, do: :ok, else: {:error, :shorter_than_min_length}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_max_length(length, opts) do
    case Keyword.fetch(opts, :max_length) do
      {:ok, maximum} when is_integer(maximum) and maximum >= 0 ->
        if length <= maximum, do: :ok, else: {:error, :longer_than_max_length}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_min_items(items, opts) do
    case Keyword.fetch(opts, :min_items) do
      {:ok, minimum} when is_integer(minimum) and minimum >= 0 ->
        if length(items) >= minimum, do: :ok, else: {:error, :fewer_than_min_items}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_max_items(items, opts) do
    case Keyword.fetch(opts, :max_items) do
      {:ok, maximum} when is_integer(maximum) and maximum >= 0 ->
        if length(items) <= maximum, do: :ok, else: {:error, :more_than_max_items}

      {:ok, _other} ->
        {:error, :invalid_schema}

      :error ->
        :ok
    end
  end

  defp check_unique_items(items, opts) do
    case Keyword.get(opts, :unique_items, false) do
      true ->
        if Enum.uniq(items) == items, do: :ok, else: {:error, :items_not_unique}

      false ->
        :ok

      _other ->
        {:error, :invalid_schema}
    end
  end

  defp resolve_terminal_schema(schema) when is_atom(schema) do
    cond do
      schema in [:any, :boolean, :integer, :number, :null, :string, :binary] ->
        {:ok, {:base, schema}}

      brand_module?(schema) ->
        {:ok, {:brand, schema}}

      schema_module?(schema) ->
        {:ok, {:schema, schema}}

      true ->
        case Base.normalize!(schema) do
          normalized_base -> {:ok, {:base, normalized_base}}
        end
    end
  rescue
    ArgumentError ->
      :error
  end

  defp resolve_terminal_schema({schema, opts}) when is_list(opts) do
    {schema_opts, type_opts} =
      Keyword.split(opts, [:required, :from | @schema_option_keys])

    cond do
      schema_module?(schema) ->
        if type_opts == [], do: {:ok, {:schema, schema}}, else: :error

      brand_module?(schema) ->
        if type_opts == [], do: {:ok, {:brand, schema}}, else: :error

      true ->
        case Base.normalize!({schema, type_opts}) do
          normalized_base ->
            if schema_opts == opts do
              {:ok, {:base, normalized_base}}
            else
              {:ok, {:base, normalized_base}}
            end
        end
    end
  rescue
    ArgumentError ->
      :error
  end

  defp resolve_terminal_schema(_schema), do: :error

  defp expand_schema({schema, opts}, env) when is_list(opts) do
    {expand_schema(schema, env), opts}
  end

  defp expand_schema(schema, env) when is_list(schema) do
    Enum.map(schema, &expand_schema(&1, env))
  end

  defp expand_schema(schema, env) when is_map(schema) do
    Map.new(schema, fn {key, value} -> {key, expand_schema(value, env)} end)
  end

  defp expand_schema({:__aliases__, _, _} = schema, env), do: Macro.expand(schema, env)
  defp expand_schema(schema, _env), do: schema

  defp brand_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__brand__, 0) and
      function_exported?(module, :cast, 1)
  end

  defp brand_module?(_module), do: false

  defp schema_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__schema__, 0) and
      function_exported?(module, :validate, 1)
  end

  defp schema_module?(_module), do: false
end
