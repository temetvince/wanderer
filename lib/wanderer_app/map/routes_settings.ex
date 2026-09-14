defmodule WandererApp.Map.RoutesSettings do
  @moduledoc """
  Reads the routes settings a client sends with a `get_routes`,
  `get_user_routes` or `get_routes_by` event into the atom-keyed map that
  `WandererApp.Map.Routes` and `WandererApp.Map.RoutesBy` merge over their
  defaults.

  Contract: every known key that is present with a non-nil value is kept, and
  nothing else is. A payload missing a key (settings saved by an older client,
  an admin default-settings blob, a hand-edited export) therefore keeps every
  toggle it does carry, and only the absent ones fall back to the server
  defaults. Unknown keys are dropped so a client can never inject settings the
  route builder does not understand.
  """

  @keys %{
    "path_type" => :path_type,
    "include_mass_crit" => :include_mass_crit,
    "include_eol" => :include_eol,
    "include_frig" => :include_frig,
    "include_cruise" => :include_cruise,
    "avoid_wormholes" => :avoid_wormholes,
    "avoid_pochven" => :avoid_pochven,
    "avoid_edencom" => :avoid_edencom,
    "avoid_triglavian" => :avoid_triglavian,
    "include_thera" => :include_thera,
    "avoid" => :avoid
  }

  @doc """
  Converts a string-keyed settings payload into an atom-keyed map holding only
  the known, non-nil settings. Anything that is not a map yields `%{}`.
  """
  @spec from_params(term()) :: map()
  def from_params(params) when is_map(params) do
    Enum.reduce(@keys, %{}, fn {string_key, atom_key}, acc ->
      case Map.get(params, string_key) do
        nil -> acc
        value -> Map.put(acc, atom_key, value)
      end
    end)
  end

  def from_params(_), do: %{}
end
