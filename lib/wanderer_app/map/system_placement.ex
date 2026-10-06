defmodule WandererApp.Map.SystemPlacement do
  @moduledoc """
  Chooses the position of a system that is added to a map without explicit coordinates: a tracked pilot
  jumps or warps into it, or it is added from the system dialog.

  Upstream answers this from a spatial index kept in `WandererApp.Cache`. That cache is generational and
  evicts entries that go untouched for two collection intervals, so after a quiet stretch the index is
  empty, every candidate counts as free, and the new system is drawn on top of whatever already sits next to
  the system the pilot came from. This module answers from the map state instead, which is the same data
  the clients render.

  Contract:

  - `occupied` holds the bounding box of every system the map currently draws, in
    `WandererApp.Map.PositionCalculator.get_system_bounding_rect/1` form. `occupied_boxes/1` builds it from
    `WandererApp.Map.list_systems!/1`.
  - Candidates are walked in upstream's order: ring by ring around the anchor, starting on the side the map's
    `layout` option prefers, so a chain grows exactly where upstream would draw it when nothing is in the way.
  - The returned position's box intersects no box in `occupied`. The one exception repeats upstream: when the
    first 100 rings around the anchor are all taken, the origin is returned.
  """

  alias WandererApp.Map.PositionCalculator

  @max_level 100
  @origin {0, 0}

  @type box :: [{number(), number()}]
  @type position :: %{x: number(), y: number()}

  @doc """
  Returns the first free position around `anchor` (a system with `position_x`/`position_y`, or `nil` to start
  from the origin). `opts` is the map's option set; only `:layout` is read.
  """
  @spec find(map() | nil, [box()], keyword() | map()) :: position()
  def find(anchor, occupied, opts) do
    {start_x, start_y} = start_point(anchor)
    {x, y} = search(start_x, start_y, occupied, opts, 1)
    %{x: x, y: y}
  end

  @doc """
  Bounding boxes of the systems a map draws. Hidden systems and systems without a numeric position are
  skipped.
  """
  @spec occupied_boxes([map()]) :: [box()]
  def occupied_boxes(systems) do
    systems
    |> Enum.filter(&drawn?/1)
    |> Enum.map(&PositionCalculator.get_system_bounding_rect/1)
  end

  @doc "True when a system drawn at `{x, y}` would intersect none of `occupied`."
  @spec free?({number(), number()}, [box()]) :: boolean()
  def free?({x, y}, occupied) do
    box = PositionCalculator.get_system_bounding_rect(%{position_x: x, position_y: y})
    not Enum.any?(occupied, &intersects?(box, &1))
  end

  defp drawn?(%{position_x: x, position_y: y} = system) when is_number(x) and is_number(y),
    do: Map.get(system, :visible, true) != false

  defp drawn?(_system), do: false

  defp start_point(%{position_x: x, position_y: y}) when is_number(x) and is_number(y), do: {x, y}
  defp start_point(_anchor), do: @origin

  defp search(_x, _y, _occupied, _opts, @max_level), do: @origin

  defp search(x, y, occupied, opts, level) do
    level
    |> PositionCalculator.get_available_positions(x, y, opts)
    |> Enum.find(&free?(&1, occupied))
    |> case do
      nil -> search(x, y, occupied, opts, level + 1)
      position -> position
    end
  end

  # Strict intersection: boxes that only touch along an edge are not in each other's way.
  defp intersects?([{ax1, ax2}, {ay1, ay2}], [{bx1, bx2}, {by1, by2}]),
    do: ax1 < bx2 and bx1 < ax2 and ay1 < by2 and by1 < ay2
end
