defmodule WandererApp.Map.SystemPlacementTest do
  use ExUnit.Case, async: true

  alias WandererApp.Map.{PositionCalculator, SystemPlacement}

  # Node size and ring spacing as defined by PositionCalculator.
  @w 130
  @h 34
  @step_x 180
  @step_y 75

  defp box(x, y), do: PositionCalculator.get_system_bounding_rect(%{position_x: x, position_y: y})

  defp overlaps_any?(%{x: x, y: y}, occupied), do: not SystemPlacement.free?({x, y}, occupied)

  describe "find/3 on an empty map" do
    test "left_to_right places the first system to the right of the anchor" do
      anchor = %{position_x: 100, position_y: 200}

      assert SystemPlacement.find(anchor, [], layout: "left_to_right") ==
               %{x: 100 + @step_x, y: 200}
    end

    test "top_to_bottom places the first system below the anchor" do
      anchor = %{position_x: 100, position_y: 200}

      assert SystemPlacement.find(anchor, [], layout: "top_to_bottom") ==
               %{x: 100, y: 200 + @step_y}
    end

    test "a missing layout behaves like left_to_right" do
      anchor = %{position_x: 100, position_y: 200}

      assert SystemPlacement.find(anchor, [], %{}) == %{x: 100 + @step_x, y: 200}
    end

    test "no anchor starts from the origin" do
      assert SystemPlacement.find(nil, [], layout: "left_to_right") == %{x: @step_x, y: 0}
    end

    test "an anchor without a position starts from the origin" do
      anchor = %{position_x: nil, position_y: nil}

      assert SystemPlacement.find(anchor, [], layout: "top_to_bottom") == %{x: 0, y: @step_y}
    end
  end

  describe "find/3 around occupied slots" do
    test "skips the slot below a home that already has a neighbour there" do
      home = %{position_x: 100, position_y: 200}
      occupied = [box(100, 200), box(100, 200 + @step_y)]

      result = SystemPlacement.find(home, occupied, layout: "top_to_bottom")

      refute overlaps_any?(result, occupied)
      assert result == %{x: 100 - @step_x, y: 200 + @step_y}
    end

    test "a neighbour dragged off the grid still blocks every slot it touches" do
      home = %{position_x: 100, position_y: 200}
      # Sits across the below slot (100, 275) and the below-left slot (-80, 275).
      occupied = [box(100, 200), box(40, 260)]

      result = SystemPlacement.find(home, occupied, layout: "top_to_bottom")

      refute overlaps_any?(result, occupied)
      refute result in [%{x: 100, y: 275}, %{x: -80, y: 275}]
    end

    test "boxes that only touch along an edge do not block" do
      home = %{position_x: 0, position_y: 0}
      # Directly right of the first left_to_right slot (180, 0), sharing its right edge.
      occupied = [box(0, 0), box(@step_x + @w, 0)]

      assert SystemPlacement.find(home, occupied, layout: "left_to_right") == %{x: @step_x, y: 0}
    end

    test "moves out to the next ring when the first is full" do
      home = %{position_x: 0, position_y: 0}

      ring_one =
        for dx <- -1..1, dy <- -1..1, {dx, dy} != {0, 0}, do: box(dx * @step_x, dy * @step_y)

      result = SystemPlacement.find(home, [box(0, 0) | ring_one], layout: "left_to_right")

      refute overlaps_any?(result, ring_one)
      assert result == %{x: 2 * @step_x, y: 0}
    end

    test "never returns an overlapping position for dense, jittered occupancy" do
      home = %{position_x: 500, position_y: 500}

      occupied =
        for dx <- -3..3, dy <- -3..3, {dx, dy} != {0, 0}, rem(dx * 7 + dy * 3, 4) != 0 do
          box(500 + dx * @step_x + rem(dx * 13, @w), 500 + dy * @step_y + rem(dy * 11, @h))
        end

      for layout <- ["left_to_right", "top_to_bottom", nil] do
        result = SystemPlacement.find(home, [box(500, 500) | occupied], layout: layout)
        refute overlaps_any?(result, occupied), "#{layout} overlapped at #{inspect(result)}"
      end
    end
  end

  describe "occupied_boxes/1" do
    test "keeps drawn systems and skips hidden ones and ones without a position" do
      systems = [
        %{position_x: 10, position_y: 20, visible: true},
        %{position_x: 30, position_y: 40},
        %{position_x: 50, position_y: 60, visible: false},
        %{position_x: nil, position_y: nil, visible: true}
      ]

      assert SystemPlacement.occupied_boxes(systems) == [box(10, 20), box(30, 40)]
    end
  end
end
