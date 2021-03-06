defmodule ExDgraph.Mutation do
  @moduledoc """
  Provides the functions for the callbacks from the DBConnection behaviour.
  """
  alias ExDgraph.{Exception, MutationStatement, QueryStatement, Transform}

  @doc false
  def mutation!(conn, statement) do
    case mutation_commit(conn, statement) do
      {:error, f} ->
        raise Exception, code: f.code, message: f.message

      r ->
        r
    end
  end

  @doc false
  def mutation(conn, statement) do
    case mutation_commit(conn, statement) do
      {:error, f} -> {:error, code: f.code, message: f.message}
      r -> {:ok, r}
    end
  end

  @doc false
  def set_map(conn, map) do
    map_with_tmp_uids = insert_tmp_uids(map)
    json = Poison.encode!(map_with_tmp_uids)

    case set_map_commit(conn, json, map_with_tmp_uids) do
      {:error, f} -> {:error, code: f.code, message: f.message}
      r -> {:ok, r}
    end
  end

  @doc false
  def set_map!(conn, map) do
    map_with_tmp_uids = insert_tmp_uids(map)
    json = Poison.encode!(map_with_tmp_uids)

    case set_map_commit(conn, json, map_with_tmp_uids) do
      {:error, f} ->
        raise Exception, code: f.code, message: f.message

      r ->
        r
    end
  end

  defp mutation_commit(conn, statement) do
    exec = fn conn ->
      q = %MutationStatement{statement: statement}

      case DBConnection.execute(conn, q, %{}) do
        {:ok, resp} -> Transform.transform_mutation(resp)
        other -> other
      end
    end

    # Response.transform(DBConnection.run(conn, exec, run_opts()))
    DBConnection.run(conn, exec, run_opts())
  end

  defp set_map_commit(conn, json, map_with_tmp_uids) do
    exec = fn conn ->
      q = %MutationStatement{set_json: json}

      case DBConnection.execute(conn, q, %{}) do
        {:ok, resp} ->
          parsed_response = Transform.transform_mutation(resp)
          # Now exchange the tmp ids for the ones returned from the db
          result_with_uids = replace_tmp_uids(map_with_tmp_uids, parsed_response.uids)
          Map.put(parsed_response, :result, result_with_uids)

        other ->
          other
      end
    end

    # Response.transform(DBConnection.run(conn, exec, run_opts()))
    DBConnection.run(conn, exec, run_opts())
  end

  defp insert_tmp_uids(map) when is_list(map), do: Enum.map(map, &insert_tmp_uids/1)

  defp insert_tmp_uids(map) when is_map(map) do
    map
    |> Map.update(:uid, "_:#{UUID.uuid4()}", fn existing_uuid -> existing_uuid end)
    |> Enum.reduce(%{}, fn
      {key, a_map = %{}}, a -> Map.merge(a, %{key => insert_tmp_uids(a_map)})
      {key, not_a_map}, a -> Map.merge(a, %{key => insert_tmp_uids(not_a_map)})
    end)
  end

  defp insert_tmp_uids(value), do: value

  defp replace_tmp_uids(map, uids) when is_list(map),
    do: Enum.map(map, &replace_tmp_uids(&1, uids))

  defp replace_tmp_uids(map, uids) when is_map(map) do
    map
    |> Map.update(:uid, map[:uid], fn existing_uuid ->
      case String.slice(existing_uuid, 0, 2) == "_:" do
        true -> uids[String.replace_leading(existing_uuid, "_:", "")]
        false -> existing_uuid
      end
    end)
    |> Enum.reduce(%{}, fn
      {key, a_map = %{}}, a -> Map.merge(a, %{key => replace_tmp_uids(a_map, uids)})
      {key, not_a_map}, a -> Map.merge(a, %{key => replace_tmp_uids(not_a_map, uids)})
    end)
  end

  defp replace_tmp_uids(value, uids), do: value

  defp get_real_uid(tmp_value, uids) do
  end

  defp run_opts do
    [pool: ExDgraph.config(:pool)]
  end
end
