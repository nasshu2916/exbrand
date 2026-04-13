defmodule ExBrand.Schema.Runtime.MapValidator do
  @moduledoc false

  alias ExBrand.Schema.Definition

  @type key_lookup_context() :: %{String.t() => atom()}

  @spec validate_map(
          map() | term(),
          map(),
          boolean(),
          (term(), term() -> {:ok, term()} | {:error, term()}),
          atom()
        ) ::
          {:ok, map()} | {:error, map()} | {:error, :invalid_type}
  def validate_map(value, schema_fields, fail_fast, validate_schema, extra_field_key)
      when is_map(value) and is_map(schema_fields) and is_boolean(fail_fast) and
             is_function(validate_schema, 2) and is_atom(extra_field_key) do
    key_context = build_key_lookup_context(value)

    if fail_fast do
      validate_map_fail_fast(value, schema_fields, key_context, validate_schema, extra_field_key)
    else
      validate_map_collect_all(
        value,
        schema_fields,
        key_context,
        validate_schema,
        extra_field_key
      )
    end
  end

  def validate_map(_value, _schema_fields, _fail_fast, _validate_schema, _extra_field_key),
    do: {:error, :invalid_type}

  @spec build_key_lookup_context(map()) :: key_lookup_context()
  def build_key_lookup_context(params) when is_map(params) do
    Enum.reduce(params, %{}, fn
      {key, _value}, acc when is_binary(key) ->
        case to_existing_atom_safe(key) do
          {:ok, atom_key} -> Map.put_new(acc, key, atom_key)
          :error -> acc
        end

      {key, _value}, acc when is_atom(key) ->
        Map.put_new(acc, Atom.to_string(key), key)

      {_key, _value}, acc ->
        acc
    end)
  end

  @spec fetch_compiled_field_value(map(), [Definition.runtime_lookup_entry()]) ::
          {:ok, term(), atom() | String.t()} | :missing
  def fetch_compiled_field_value(params, lookup) do
    fetch_compiled_field_value(params, lookup, build_key_lookup_context(params))
  end

  @spec fetch_compiled_field_value(
          map(),
          [Definition.runtime_lookup_entry()],
          key_lookup_context()
        ) ::
          {:ok, term(), atom() | String.t()} | :missing
  def fetch_compiled_field_value(_params, [], _key_context), do: :missing

  def fetch_compiled_field_value(params, [key | rest], key_context)
      when is_atom(key) or is_binary(key) do
    if Map.has_key?(params, key) do
      {:ok, Map.fetch!(params, key), key}
    else
      fetch_compiled_field_value(params, rest, key_context)
    end
  end

  def fetch_compiled_field_value(params, [{:existing_atom_binary, key} | rest], key_context) do
    with {:ok, atom_key} <- Map.fetch(key_context, key),
         true <- Map.has_key?(params, atom_key) do
      {:ok, Map.fetch!(params, atom_key), atom_key}
    else
      _ -> fetch_compiled_field_value(params, rest, key_context)
    end
  end

  @spec extra_fields(map(), MapSet.t()) :: [term()]
  def extra_fields(value, consumed_keys) do
    value
    |> Enum.reduce([], fn {key, _value}, acc ->
      if MapSet.member?(consumed_keys, key), do: acc, else: [key | acc]
    end)
    |> Enum.reverse()
  end

  defp validate_map_fail_fast(value, schema_fields, key_context, validate_schema, extra_field_key) do
    case Enum.reduce_while(schema_fields, {%{}, MapSet.new()}, fn {name, field_schema},
                                                                  {normalized, consumed_keys} ->
           validate_fail_fast_field(
             value,
             name,
             field_schema,
             key_context,
             validate_schema,
             normalized,
             consumed_keys
           )
         end) do
      {:error, errors} ->
        {:error, errors}

      {normalized, consumed_keys} ->
        case extra_fields(value, consumed_keys) do
          [] -> {:ok, normalized}
          fields -> {:error, %{extra_field_key => Enum.sort(fields)}}
        end
    end
  end

  defp validate_fail_fast_field(
         value,
         name,
         field_schema,
         key_context,
         validate_schema,
         normalized,
         consumed_keys
       ) do
    schema = field_schema.schema
    lookup = field_schema.lookup

    case fetch_compiled_field_value(value, lookup, key_context) do
      {:ok, field_value, used_key} ->
        validate_fail_fast_present_field(
          field_value,
          schema,
          name,
          validate_schema,
          normalized,
          consumed_keys,
          used_key
        )

      :missing ->
        {:halt, {:error, %{name => :required}}}
    end
  end

  defp validate_fail_fast_present_field(
         field_value,
         schema,
         name,
         validate_schema,
         normalized,
         consumed_keys,
         used_key
       ) do
    case validate_schema.(field_value, schema) do
      {:ok, normalized_value} ->
        {:cont,
         {Map.put(normalized, name, normalized_value), MapSet.put(consumed_keys, used_key)}}

      {:error, reason} ->
        {:halt, {:error, %{name => reason}}}
    end
  end

  defp validate_map_collect_all(
         value,
         schema_fields,
         key_context,
         validate_schema,
         extra_field_key
       ) do
    {normalized, errors, consumed_keys} =
      Enum.reduce(schema_fields, {%{}, nil, MapSet.new()}, fn {name, field_schema},
                                                              {normalized, errors, consumed_keys} ->
        schema = field_schema.schema
        lookup = field_schema.lookup

        case fetch_compiled_field_value(value, lookup, key_context) do
          {:ok, field_value, used_key} ->
            case validate_schema.(field_value, schema) do
              {:ok, normalized_value} ->
                {Map.put(normalized, name, normalized_value), errors,
                 MapSet.put(consumed_keys, used_key)}

              {:error, reason} ->
                {normalized, put_error(errors, name, reason), MapSet.put(consumed_keys, used_key)}
            end

          :missing ->
            {normalized, put_error(errors, name, :required), consumed_keys}
        end
      end)

    errors =
      case extra_fields(value, consumed_keys) do
        [] -> errors
        fields -> put_error(errors, extra_field_key, Enum.sort(fields))
      end

    if is_nil(errors), do: {:ok, normalized}, else: {:error, errors}
  end

  defp to_existing_atom_safe(key) when is_binary(key) do
    {:ok, String.to_existing_atom(key)}
  rescue
    ArgumentError -> :error
  end

  defp put_error(nil, key, reason), do: %{key => reason}
  defp put_error(errors, key, reason), do: Map.put(errors, key, reason)
end
