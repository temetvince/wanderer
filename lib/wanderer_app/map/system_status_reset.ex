defmodule WandererApp.Map.SystemStatusReset do
  @moduledoc """
  One-time wipe run when a map enables `clear_status_on_removal` (fork).

  Clears the status of every system of the map that is not custom named, drawn
  or not, so an existing map starts from the state the rule would have produced.
  Systems drawn on a currently loaded map are updated through the map server,
  which refreshes the in-memory state and connected clients; every other system
  is updated in the database only, which the map server reads when it loads.

  Precondition: the caller has verified the user may administer the map.
  """

  require Logger

  alias WandererApp.Map.SystemStatus

  @doc """
  Clears the status of every unnamed system of `map_id`.

  Returns `{:ok, count}` with the number of systems whose status was cleared.
  """
  def clear_unnamed(map_id) do
    with {:ok, systems} <- WandererApp.MapSystemRepo.get_all_by_map(map_id) do
      loaded? = match?({:ok, _}, WandererApp.Map.get_map(map_id))

      count =
        systems
        |> Enum.filter(&SystemStatus.clear?(&1, default_name(&1.solar_system_id)))
        |> Enum.reduce(0, fn system, acc ->
          case clear_one(map_id, system, loaded?) do
            :ok ->
              acc + 1

            {:error, error} ->
              Logger.error(
                "[SystemStatusReset] failed to clear status of system #{system.solar_system_id} on map #{map_id}: #{inspect(error)}"
              )

              acc
          end
        end)

      {:ok, count}
    end
  end

  @doc "The static solar system name for `solar_system_id`, or nil when unknown."
  def default_name(solar_system_id) do
    case WandererApp.CachedInfo.get_system_static_info(solar_system_id) do
      {:ok, %{solar_system_name: name}} -> name
      _ -> nil
    end
  end

  defp clear_one(map_id, %{visible: true, solar_system_id: solar_system_id}, true) do
    WandererApp.Map.Server.update_system_status(map_id, %{
      solar_system_id: solar_system_id,
      status: SystemStatus.clear()
    })

    :ok
  end

  defp clear_one(_map_id, system, _loaded?) do
    case WandererApp.MapSystemRepo.update_status(system, %{status: SystemStatus.clear()}) do
      {:ok, _system} -> :ok
      error -> {:error, error}
    end
  end
end
