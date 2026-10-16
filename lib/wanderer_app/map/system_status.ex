defmodule WandererApp.Map.SystemStatus do
  @moduledoc """
  Lifetime of a map system's `status` across removal from the map (fork).

  Upstream keeps `status` forever: removing a system only hides it, so the
  status is back when the system is drawn again. With the map option
  `clear_status_on_removal` enabled, that is reserved for systems someone has
  named. A system whose name is the default solar system name has its status
  cleared the moment it leaves the map, by a user or by the inactivity cleanup;
  a system with a custom name keeps its status. Enabling the option also clears
  the status of every unnamed system the map already has, drawn or not (see
  `WandererApp.Map.SystemStatusReset`).

  A system counts as custom named when its `custom_name` is set, or when its
  `name` is set and differs from the default name the caller passes in (the
  static solar system name). The map UI writes the "Custom name" field into
  `name` and writes the default name back when the field is cleared, so the
  comparison with the static name is what tells the two apart.

  Pure: no IO. The caller resolves the default name and the map options.
  """

  @clear 0
  @option_key "clear_status_on_removal"

  @doc "The status value meaning no status."
  def clear, do: @clear

  @doc "The map option key that turns the rule on (stored as `\"true\"`/`\"false\"`)."
  def option_key, do: @option_key

  @doc "Whether the map `options` enable the rule. Off unless explicitly `\"true\"`."
  def enabled?(options) when is_map(options),
    do: Map.get(options, @option_key, "false") in ["true", true]

  def enabled?(_options), do: false

  @doc "Whether `status` marks the system at all (anything but clear or nil)."
  def set?(status), do: not is_nil(status) and status != @clear

  @doc """
  Whether `system` carries a user-given name: a non-blank `custom_name`, or a
  non-blank `name` different from `default_name`.
  """
  def custom_named?(system, default_name) do
    custom_name = system |> Map.get(:custom_name) |> normalize()
    name = system |> Map.get(:name) |> normalize()
    default = normalize(default_name)

    custom_name != "" or (name != "" and name != default)
  end

  @doc """
  Whether `system` should lose its status now: it has one and is not custom
  named. The caller decides whether the rule applies (`enabled?/1`).
  """
  def clear?(system, default_name),
    do: set?(Map.get(system, :status)) and not custom_named?(system, default_name)

  @doc """
  The status `system` keeps after it is removed from the map: its current
  status when it is custom named, clear otherwise.
  """
  def after_removal(system, default_name) do
    if custom_named?(system, default_name), do: Map.get(system, :status), else: @clear
  end

  defp normalize(nil), do: ""
  defp normalize(value) when is_binary(value), do: String.trim(value)
  defp normalize(value), do: value |> to_string() |> String.trim()
end
