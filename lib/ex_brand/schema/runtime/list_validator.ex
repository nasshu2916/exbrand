defmodule ExBrand.Schema.Runtime.ListValidator do
  @moduledoc false

  @spec validate_list(
          term(),
          term(),
          boolean(),
          (term(), term() -> {:ok, term()} | {:error, term()}),
          [term()],
          boolean()
        ) :: {:ok, [term()]} | {:error, map()} | {:error, :invalid_type}
  def validate_list(value, item_schema, fail_fast, validate_schema, checks, defer_unique?)
      when is_list(value) and is_boolean(fail_fast) and is_function(validate_schema, 2) and
             is_list(checks) and is_boolean(defer_unique?) do
    if fail_fast do
      validate_list_fail_fast(value, item_schema, validate_schema, checks, defer_unique?)
    else
      validate_list_collect_all(value, item_schema, validate_schema, checks, defer_unique?)
    end
  end

  def validate_list(_value, _item_schema, _fail_fast, _validate_schema, _checks, _defer_unique?),
    do: {:error, :invalid_type}

  defp validate_list_fail_fast(value, item_schema, validate_schema, checks, defer_unique?) do
    with {:ok, normalized_items_reversed} <-
           validate_list_items_fail_fast(value, item_schema, validate_schema),
         :ok <- validate_list_constraints_fail_fast(value, checks, defer_unique?) do
      {:ok, Enum.reverse(normalized_items_reversed)}
    else
      {:error, {index, reason}} -> {:error, %{index => reason}}
      {:error, reason} -> {:error, %{__self__: reason}}
    end
  end

  defp validate_list_collect_all(value, item_schema, validate_schema, checks, defer_unique?) do
    {normalized_items, item_errors} =
      value
      |> Enum.with_index()
      |> Enum.reduce({[], nil}, fn {item, index}, {normalized_items, item_errors} ->
        case validate_schema.(item, item_schema) do
          {:ok, normalized_item} -> {[normalized_item | normalized_items], item_errors}
          {:error, reason} -> {normalized_items, put_error(item_errors, index, reason)}
        end
      end)

    normalized_items = Enum.reverse(normalized_items)
    apply_list_constraints(value, normalized_items, item_errors, checks, defer_unique?)
  end

  defp validate_list_items_fail_fast(value, item_schema, validate_schema) do
    Enum.reduce_while(Enum.with_index(value), {:ok, []}, fn {item, index},
                                                            {:ok, normalized_items} ->
      case validate_schema.(item, item_schema) do
        {:ok, normalized_item} ->
          {:cont, {:ok, [normalized_item | normalized_items]}}

        {:error, reason} ->
          {:halt, {:error, {index, reason}}}
      end
    end)
  end

  defp validate_list_constraints_fail_fast(original_items, checks, defer_unique?) do
    context = build_list_context(original_items, checks)

    with :ok <- run_list_check(checks, :min_items, context),
         :ok <- run_list_check(checks, :max_items, context),
         :ok <- run_uniqueness_check(original_items, checks, defer_unique?) do
      :ok
    end
  end

  defp apply_list_constraints(
         original_items,
         normalized_items,
         item_errors,
         checks,
         defer_unique?
       ) do
    context = build_list_context(original_items, checks)

    errors =
      item_errors
      |> maybe_put_self_error(run_list_check(checks, :min_items, context))
      |> maybe_put_self_error(run_list_check(checks, :max_items, context))
      |> maybe_put_self_error(run_uniqueness_check(original_items, checks, defer_unique?))

    if is_nil(errors), do: {:ok, normalized_items}, else: {:error, errors}
  end

  defp build_list_context(items, checks) do
    if Enum.any?(checks, fn
         {:min_items, _value} -> true
         {:max_items, _value} -> true
         _ -> false
       end) do
      %{item_count: length(items)}
    else
      %{}
    end
  end

  defp run_list_check([], _kind, _context), do: :ok

  defp run_list_check([{:min_items, value} | rest], :min_items, %{item_count: item_count}) do
    if item_count >= value,
      do: run_list_check(rest, :min_items, %{item_count: item_count}),
      else: {:error, :fewer_than_min_items}
  end

  defp run_list_check([{:max_items, value} | rest], :max_items, %{item_count: item_count}) do
    if item_count <= value,
      do: run_list_check(rest, :max_items, %{item_count: item_count}),
      else: {:error, :more_than_max_items}
  end

  defp run_list_check([_other | rest], kind, context),
    do: run_list_check(rest, kind, context)

  defp run_uniqueness_check(_items, _checks, true), do: :ok

  defp run_uniqueness_check(items, checks, false) do
    if :unique_items in checks do
      if unique_items?(items), do: :ok, else: {:error, :items_not_unique}
    else
      :ok
    end
  end

  defp unique_items?(items) do
    Enum.reduce_while(items, MapSet.new(), fn item, seen ->
      if MapSet.member?(seen, item) do
        {:halt, false}
      else
        {:cont, MapSet.put(seen, item)}
      end
    end) != false
  end

  defp maybe_put_self_error(errors, :ok), do: errors
  defp maybe_put_self_error(nil, {:error, reason}), do: %{__self__: reason}
  defp maybe_put_self_error(errors, {:error, reason}), do: Map.put(errors, :__self__, reason)

  defp put_error(nil, key, reason), do: %{key => reason}
  defp put_error(errors, key, reason), do: Map.put(errors, key, reason)
end
