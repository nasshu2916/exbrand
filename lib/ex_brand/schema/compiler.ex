defmodule ExBrand.Schema.Compiler do
  @moduledoc false

  alias ExBrand.Schema.Definition

  @spec build_field_ast!({atom(), term(), keyword()}) :: Macro.t()
  def build_field_ast!(field_definition) do
    field_definition
    |> build_field_definition!()
    |> build_field_ast()
  end

  @spec build_field_definition!({atom(), term(), keyword()}) :: {atom(), term()}
  def build_field_definition!({name, schema, opts}) do
    unless is_atom(name) do
      raise ArgumentError, "field name must be an atom, got: #{inspect(name)}"
    end

    unless Keyword.keyword?(opts) do
      raise ArgumentError, "field options must be a keyword list, got: #{inspect(opts)}"
    end

    merged_schema = Definition.merge_field_opts(schema, opts)
    validate_schema_definition!(merged_schema, "field #{inspect(name)}")

    {name, merged_schema}
  end

  @spec build_field_ast({atom(), term()}) :: Macro.t()
  def build_field_ast({name, merged_schema}) do
    quote do
      {unquote(name), unquote(Macro.escape(merged_schema))}
    end
  end

  @spec validate_schema_definition!(term(), String.t()) :: :ok
  def validate_schema_definition!(schema, path) do
    {base_schema, opts} = Definition.split_schema_opts(schema)
    Definition.validate_constraint_values!(opts, path)

    cond do
      is_map(base_schema) ->
        Definition.ensure_allowed_constraints!(opts, Definition.map_constraint_keys(), path, :map)

        Enum.each(base_schema, fn {field_name, field_schema} ->
          validate_schema_definition!(field_schema, "#{path}.#{field_name}")
        end)

      is_list(base_schema) ->
        case base_schema do
          [item_schema] ->
            Definition.ensure_allowed_constraints!(
              opts,
              Definition.list_constraint_keys(),
              path,
              :list
            )

            validate_schema_definition!(item_schema, "#{path}[]")

          _ ->
            raise ArgumentError,
                  "invalid schema at #{path}: list schema must contain exactly one item schema"
        end

      true ->
        Definition.validate_terminal_schema_definition!(base_schema, opts, path)
    end

    :ok
  end
end
