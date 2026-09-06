defmodule WandererApp.Map.WormholeLifetimeTest do
  use ExUnit.Case, async: true

  alias WandererApp.Map.WormholeLifetime

  # time_status values
  @default 0
  @eol_4_5 3
  @eol_16 4
  @eol_24 5
  @eol_48 6
  @eol_12 7

  @frigate 0
  @large 2

  # wormholes.json src/dest key -> system_class id
  @class_ids %{
    "c1" => 1,
    "c2" => 2,
    "c3" => 3,
    "c4" => 4,
    "c5" => 5,
    "c6" => 6,
    "hs" => 7,
    "ls" => 8,
    "ns" => 9,
    "thera" => 12,
    "c13" => 13,
    "sentinel" => 14,
    "barbican" => 15,
    "vidette" => 16,
    "conflux" => 17,
    "redoubt" => 18,
    "drifter" => 14,
    "jove" => 19,
    "pochven" => 25
  }

  setup_all do
    %{types: WandererApp.EveDataService.load_wormhole_types()}
  end

  defp system(class, opts \\ []) do
    %{
      system_class: class,
      statics: Keyword.get(opts, :statics, []),
      is_shattered: Keyword.get(opts, :shattered, false)
    }
  end

  defp system_for_key("c" <> _ = key, statics) do
    case String.split(key, "-shattered") do
      [base, ""] -> system(Map.fetch!(@class_ids, base), statics: statics, shattered: true)
      [_] -> system(Map.fetch!(@class_ids, key), statics: statics)
    end
  end

  defp system_for_key(key, statics), do: system(Map.fetch!(@class_ids, key), statics: statics)

  defp expected_status(%{lifetime: lifetime}) do
    {hours, _} = Float.parse(lifetime)
    WormholeLifetime.bucket(hours)
  end

  describe "bucket/1" do
    test "maps a lifetime to the smallest bucket that contains it" do
      assert WormholeLifetime.bucket(0.5) == 1
      assert WormholeLifetime.bucket(4.0) == 2
      assert WormholeLifetime.bucket(4.5) == @eol_4_5
      assert WormholeLifetime.bucket(12.0) == @eol_12
      assert WormholeLifetime.bucket(16.0) == @eol_16
      assert WormholeLifetime.bucket(24.0) == @eol_24
      assert WormholeLifetime.bucket(48.0) == @eol_48
      assert WormholeLifetime.bucket(13) == @eol_16
    end

    test "unknown or out-of-range lifetimes are the default" do
      assert WormholeLifetime.bucket(nil) == @default
      assert WormholeLifetime.bucket(100) == @default
    end
  end

  describe "tier 1: frigate holes" do
    test "frigate ship size is 4.5h whatever the systems are", %{types: types} do
      c5 = system(5, statics: ["H296"])
      assert WormholeLifetime.time_status(c5, system(5), @frigate, types) == @eol_4_5
      assert WormholeLifetime.time_status(nil, nil, @frigate, types) == @eol_4_5
    end
  end

  describe "tier 2: the source's static" do
    test "C5 home with a C5 static jumping into a C5 is 24h", %{types: types} do
      home = system(5, statics: ["H296", "V911"])
      assert WormholeLifetime.time_status(home, system(5), @large, types) == @eol_24
    end

    test "C5 home with a C4 static (E175) jumping into a C4 is 16h", %{types: types} do
      home = system(5, statics: ["E175", "H296"])
      assert WormholeLifetime.time_status(home, system(4), @large, types) == @eol_16
    end

    test "C2 with a high-sec static (B274) into high-sec is 24h", %{types: types} do
      assert WormholeLifetime.time_status(system(2, statics: ["B274"]), system(7), @large, types) ==
               @eol_24
    end

    test "C5 with a null static (K346) into null is 16h", %{types: types} do
      assert WormholeLifetime.time_status(system(5, statics: ["K346"]), system(9), @large, types) ==
               @eol_16
    end

    test "Pochven static (C729) into k-space is 12h", %{types: types} do
      pochven = system(25, statics: ["C729"])
      assert WormholeLifetime.time_status(pochven, system(7), @large, types) == @eol_12
      assert WormholeLifetime.time_status(pochven, system(25), @large, types) == @eol_12
    end

    test "shattered C4 with a low-sec static (U210) into low-sec is 24h", %{types: types} do
      shattered = system(4, statics: ["U210"], shattered: true)
      assert WormholeLifetime.time_status(shattered, system(8), @large, types) == @eol_24
    end

    test "every static type resolves exactly from its own system", %{types: types} do
      for type <- types, type.static, src <- type.src, dest <- type.dest do
        source = system_for_key(src, [type.name])
        target = system_for_key(dest, [])

        assert WormholeLifetime.time_status(source, target, @large, types) ==
                 expected_status(type),
               "#{type.name} #{src}->#{dest}"
      end
    end
  end

  describe "tier 3: the target's static (arrived through its K162)" do
    test "C5 home into a C4 whose static leads to C5 (H900) is 24h", %{types: types} do
      home = system(5, statics: ["H296"])
      neighbour = system(4, statics: ["H900", "X877"])
      assert WormholeLifetime.time_status(home, neighbour, @large, types) == @eol_24
    end

    test "the source's own static wins over the target's", %{types: types} do
      home = system(5, statics: ["E175"])
      neighbour = system(4, statics: ["H900"])
      assert WormholeLifetime.time_status(home, neighbour, @large, types) == @eol_16
    end

    test "every static type resolves exactly from the far side", %{types: types} do
      for type <- types, type.static, src <- type.src, dest <- type.dest do
        source = system_for_key(dest, [])
        target = system_for_key(src, [type.name])

        assert WormholeLifetime.time_status(source, target, @large, types) ==
                 expected_status(type),
               "#{type.name} K162 #{dest}->#{src}"
      end
    end
  end

  describe "tier 4: class-pair table" do
    test "C5 home into high-sec with no matching static is 24h", %{types: types} do
      home = system(5, statics: ["H296"])
      assert WormholeLifetime.time_status(home, system(7), @large, types) == @eol_24
    end

    test "C5 into C4 with no matching static on either side takes the shorter type",
         %{types: types} do
      home = system(5, statics: ["H296"])
      neighbour = system(4, statics: ["N766", "X877"])
      assert WormholeLifetime.time_status(home, neighbour, @large, types) == @eol_16
    end

    test "ambiguous wandering pairs pick the shortest lifetime", %{types: types} do
      # L614 (24h) vs Y790 (16h)
      assert WormholeLifetime.time_status(system(1), system(5), @large, types) == @eol_16
      # F135 (16h) vs N770 (24h)
      assert WormholeLifetime.time_status(system(12), system(5), @large, types) == @eol_16
    end

    test "k-space pairs get a lifetime", %{types: types} do
      assert WormholeLifetime.time_status(system(7), system(7), @large, types) == @eol_16
      assert WormholeLifetime.time_status(system(8), system(9), @large, types) == @eol_24
    end

    test "drifter hole into C5 is 24h", %{types: types} do
      assert WormholeLifetime.time_status(system(14), system(5), @large, types) == @eol_24
    end

    test "direction does not matter", %{types: types} do
      assert WormholeLifetime.time_status(system(6), system(7), @large, types) ==
               WormholeLifetime.time_status(system(7), system(6), @large, types)
    end

    test "frigate-only types never feed the pair table", %{types: types} do
      # C1-C1 has E004 (frigate, 4.5h) and H121 (16h)
      assert WormholeLifetime.time_status(system(1), system(1), @large, types) == @eol_16
    end
  end

  describe "candidates/4" do
    test "lists every lifetime the pair could have, ascending", %{types: types} do
      home = system(5, statics: ["H296"])
      neighbour = system(4, statics: ["H900", "X877"])
      assert WormholeLifetime.candidates(home, neighbour, @large, types) == [16.0, 24.0]
      assert WormholeLifetime.candidates(system(6), system(7), @large, types) == [24.0, 48.0]
      assert WormholeLifetime.candidates(system(5), system(5), @frigate, types) == [4.5]
      assert WormholeLifetime.candidates(nil, nil, @large, types) == []
    end
  end

  describe "correction/5: a jump after the guessed lifetime ran out" do
    test "holds while the guess is still possible, grace window included", %{types: types} do
      home = system(5, statics: ["H296"])
      neighbour = system(4, statics: ["N766", "X877"])
      assert WormholeLifetime.correction(home, neighbour, @large, types, 15.9) == nil
      assert WormholeLifetime.correction(home, neighbour, @large, types, 16.0) == nil
      assert WormholeLifetime.correction(home, neighbour, @large, types, 16.4) == nil
      assert {@eol_12, _} = WormholeLifetime.correction(home, neighbour, @large, types, 16.6)
    end

    test "promotes to the shortest candidate that outlives the known age", %{types: types} do
      # guessed 16h (E175 vs H900); alive at 17h -> it is the 24h hole with 7h left
      home = system(5, statics: ["H296"])
      neighbour = system(4, statics: ["N766", "X877"])

      assert {@eol_12, remaining} =
               WormholeLifetime.correction(home, neighbour, @large, types, 17)

      assert_in_delta remaining, 7.0, 0.001
    end

    test "the remaining time picks the bucket", %{types: types} do
      home = system(5, statics: ["H296"])
      neighbour = system(4, statics: ["N766", "X877"])
      assert {@eol_4_5, _} = WormholeLifetime.correction(home, neighbour, @large, types, 19.9)
      assert {2, _} = WormholeLifetime.correction(home, neighbour, @large, types, 20)
      assert {1, _} = WormholeLifetime.correction(home, neighbour, @large, types, 23.5)
    end

    test "a candidate inside its closure window is alive with nothing left", %{types: types} do
      # guessed 16h (E175 vs H900). At 24.4h the 24h hole may still be
      # closing, so it is EOL with nothing left rather than given up on.
      home = system(5, statics: ["H296"])
      neighbour = system(4, statics: ["N766", "X877"])
      assert {1, remaining} = WormholeLifetime.correction(home, neighbour, @large, types, 24.4)
      assert remaining == 0.0
      assert WormholeLifetime.correction(home, neighbour, @large, types, 24.6) == nil
    end

    test "a guess inside its own closure window is not corrected", %{types: types} do
      # C6 to high-sec: D792 24h, then B041/B520 48h
      assert WormholeLifetime.correction(system(6), system(7), @large, types, 24.4) == nil
    end

    test "steps through several candidates", %{types: types} do
      assert {@eol_24, _} = WormholeLifetime.correction(system(6), system(7), @large, types, 24.6)
      assert {2, _} = WormholeLifetime.correction(system(6), system(7), @large, types, 44)
    end

    test "gives up when no candidate outlives the age", %{types: types} do
      assert WormholeLifetime.correction(system(6), system(7), @large, types, 49) == nil
      assert WormholeLifetime.correction(system(5), system(5), @frigate, types, 5.1) == nil
    end

    test "the grace period is half an hour" do
      assert WormholeLifetime.closure_grace_hours() == 0.5
    end

    test "nothing to correct when nothing was guessed", %{types: types} do
      assert WormholeLifetime.correction(nil, nil, @large, types, 30) == nil
    end
  end

  describe "unknown input" do
    test "missing or unmapped systems fall through to the default", %{types: types} do
      assert WormholeLifetime.time_status(nil, nil, @large, types) == @default

      assert WormholeLifetime.time_status(%{system_class: nil}, system(7), @large, types) ==
               @default

      assert WormholeLifetime.time_status(system(10_100), system(7), @large, types) == @default
    end

    test "unknown static names are ignored", %{types: types} do
      home = system(5, statics: ["XXXX"])
      assert WormholeLifetime.time_status(home, system(7), @large, types) == @eol_24
    end

    test "an empty type table yields the default" do
      assert WormholeLifetime.time_status(system(5), system(5), @large, []) == @default
    end
  end
end
