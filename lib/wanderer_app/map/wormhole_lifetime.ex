defmodule WandererApp.Map.WormholeLifetime do
  @moduledoc """
  Resolves the initial time status of a wormhole connection from static EVE
  data alone: the classes of the two end systems, their static wormholes, and
  the wormhole type table (`priv/repo/data/wormholes.json`). No player input is
  needed and none is consulted.

  Tiers, first match wins:

    1. Frigate-sized hole (`ship_size_type` 0): 4.5h.
    2. A static of the source system leads to the target's class: that type's
       lifetime. Statics never respawn into the same system, so a jump into a
       system of a static's class is that static.
    3. A static of the target system leads to the source's class: that type's
       lifetime. The pilot came in through the K162 side.
    4. Every non-frigate type joining the two classes in either direction:
       the unanimous lifetime, otherwise the shortest one. Understating a
       wandering hole is the safe error.

  The result is a connection `time_status` bucket meaning "at most this much
  life remains"; the countdown in `ConnectionsImpl` steps it down from there.
  Statics resolve exactly. Wandering holes between classes that have both a
  16h and a 24h type stay ambiguous, and the shortest value is chosen.

  A jump through the hole later disproves a guess that was too short: see
  `correction/5`. The hole's age since it was first seen is a lower bound on
  its true age, so the shortest candidate longer than that age is the new
  lower bound on its lifetime, and the remaining time derived from it is an
  upper bound, which is the safe direction. EVE keeps a hole open for a
  short "closure imminent" window past its nominal lifetime, so a lifetime
  only counts as disproved once the age exceeds it by that grace period, and
  a candidate still inside its window is treated as alive with nothing left.

  Pure: callers pass system static info maps (`system_class`, `statics`,
  `is_shattered`) and the wormhole type list. Unknown classes, missing
  statics, and malformed type rows degrade to the next tier, never raise.
  """

  # Connection time_status values, shared with ConnectionsImpl and the
  # frontend TimeStatus enum.
  @time_status_default 0
  @time_status_eol_4_5 3
  @time_status_eol_16 4
  @time_status_eol_24 5
  @time_status_eol_48 6
  @time_status_eol_12 7

  @time_status_eol 1
  @time_status_eol_4 2

  @frigate_ship_size 0
  # Largest max_mass_per_jump of a frigate-only hole, in kg.
  @frigate_max_mass 5_000_000

  # How long EVE may keep a hole open past its nominal lifetime, in hours.
  @closure_grace_hours 0.5

  # Bucket boundaries in hours, ascending. A lifetime maps to the smallest
  # bucket that contains it. The 1h and 4h buckets only ever hold a remaining
  # time, never a type's full lifetime.
  @buckets [
    {1.0, @time_status_eol},
    {4.0, @time_status_eol_4},
    {4.5, @time_status_eol_4_5},
    {12.0, @time_status_eol_12},
    {16.0, @time_status_eol_16},
    {24.0, @time_status_eol_24},
    {48.0, @time_status_eol_48}
  ]

  # system_class (wormholeClasses.json wormholeClassID) -> src/dest keys used
  # in wormholes.json. Drifter and Jove classes share a collective key on the
  # source side.
  @class_keys %{
    1 => ["c1"],
    2 => ["c2"],
    3 => ["c3"],
    4 => ["c4"],
    5 => ["c5"],
    6 => ["c6"],
    7 => ["hs"],
    8 => ["ls"],
    9 => ["ns"],
    12 => ["thera"],
    13 => ["c13"],
    14 => ["sentinel", "drifter"],
    15 => ["barbican", "drifter"],
    16 => ["vidette", "drifter"],
    17 => ["conflux", "drifter"],
    18 => ["redoubt", "drifter"],
    19 => ["jove"],
    20 => ["jove"],
    21 => ["jove"],
    22 => ["jove"],
    23 => ["jove"],
    25 => ["pochven"]
  }

  @doc """
  The `time_status` for a new wormhole connection between `source` and
  `target`, given the connection's `ship_size_type` and the wormhole type
  list from `WandererApp.CachedInfo.get_wormhole_types/0`.

  Returns `0` (no lifetime) when no tier produces a value.
  """
  @spec time_status(map() | nil, map() | nil, integer() | nil, [map()]) :: integer()
  def time_status(source, target, ship_size_type, wormhole_types) do
    source
    |> lifetime_hours(target, ship_size_type, wormhole_types)
    |> bucket()
  end

  @doc """
  The resolved maximum lifetime in hours, or `nil` when unknown. Same tiers
  as `time_status/4`.
  """
  @spec lifetime_hours(map() | nil, map() | nil, integer() | nil, [map()]) :: float() | nil
  def lifetime_hours(_source, _target, @frigate_ship_size, _wormhole_types), do: 4.5

  def lifetime_hours(source, target, _ship_size_type, wormhole_types) do
    source = source || %{}
    target = target || %{}
    types_by_name = Map.new(wormhole_types, &{&1.name, &1})

    shortest(static_types(source, target, types_by_name)) ||
      shortest(static_types(target, source, types_by_name)) ||
      shortest(pair_types(source, target, wormhole_types))
  end

  @doc """
  Corrects a lifetime guess that a live jump has disproved.

  `age_hours` is how long the hole has been known to exist (first seen to
  now). When it exceeds the resolved lifetime by more than the closure grace
  period, returns `{time_status, remaining_hours}` for the shortest candidate
  lifetime the hole can still have. A candidate inside its grace window
  yields the EOL status with zero remaining. Returns `nil` when the guess
  still holds, when nothing is known, or when no candidate outlives the age.
  """
  @spec correction(map() | nil, map() | nil, integer() | nil, [map()], number()) ::
          {integer(), float()} | nil
  def correction(source, target, ship_size_type, wormhole_types, age_hours) do
    guess = lifetime_hours(source, target, ship_size_type, wormhole_types)

    if is_number(guess) and expired?(guess, age_hours) do
      source
      |> candidates(target, ship_size_type, wormhole_types)
      |> Enum.reject(&expired?(&1, age_hours))
      |> Enum.min(fn -> nil end)
      |> case do
        nil ->
          nil

        lifetime ->
          remaining = max(lifetime - age_hours, 0.0)
          {bucket(remaining), remaining}
      end
    end
  end

  @doc "Hours EVE may keep a hole open past its nominal lifetime."
  @spec closure_grace_hours() :: float()
  def closure_grace_hours, do: @closure_grace_hours

  defp expired?(lifetime, age_hours), do: age_hours > lifetime + @closure_grace_hours

  @doc """
  Every lifetime in hours the hole could have, from all tiers, ascending and
  without duplicates. Empty when nothing is known.
  """
  @spec candidates(map() | nil, map() | nil, integer() | nil, [map()]) :: [float()]
  def candidates(_source, _target, @frigate_ship_size, _wormhole_types), do: [4.5]

  def candidates(source, target, _ship_size_type, wormhole_types) do
    source = source || %{}
    target = target || %{}
    types_by_name = Map.new(wormhole_types, &{&1.name, &1})

    (static_types(source, target, types_by_name) ++
       static_types(target, source, types_by_name) ++
       pair_types(source, target, wormhole_types))
    |> Enum.map(&hours/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Maps a lifetime in hours to the smallest `time_status` bucket that contains it."
  @spec bucket(number() | nil) :: integer()
  def bucket(nil), do: @time_status_default

  def bucket(hours) do
    Enum.find_value(@buckets, @time_status_default, fn {limit, status} ->
      if hours <= limit, do: status
    end)
  end

  # Tier 2/3: statics of `from` whose destination includes `to`'s class.
  defp static_types(from, to, types_by_name) do
    to_keys = class_keys(to)

    from
    |> Map.get(:statics)
    |> List.wrap()
    |> Enum.map(&Map.get(types_by_name, &1))
    |> Enum.filter(&leads_to?(&1, to_keys))
  end

  # Tier 4: any non-frigate type joining the two classes, either direction.
  defp pair_types(source, target, wormhole_types) do
    source_keys = class_keys(source)
    target_keys = class_keys(target)

    wormhole_types
    |> Enum.reject(&frigate_type?/1)
    |> Enum.filter(fn type ->
      joins?(type, source_keys, target_keys) or joins?(type, target_keys, source_keys)
    end)
  end

  defp leads_to?(%{dest: dest}, keys) when is_list(dest), do: Enum.any?(dest, &(&1 in keys))
  defp leads_to?(_type, _keys), do: false

  defp joins?(%{src: src} = type, from_keys, to_keys) when is_list(src),
    do: Enum.any?(src, &(&1 in from_keys)) and leads_to?(type, to_keys)

  defp joins?(_type, _from_keys, _to_keys), do: false

  defp frigate_type?(%{max_mass_per_jump: mass}) when is_number(mass),
    do: mass <= @frigate_max_mass

  # K162 and rows without a mass carry no lifetime of their own.
  defp frigate_type?(_type), do: true

  defp shortest(types) do
    types
    |> Enum.map(&hours/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  defp hours(%{lifetime: lifetime}) when is_binary(lifetime) do
    case Float.parse(lifetime) do
      {value, _rest} -> value
      :error -> nil
    end
  end

  defp hours(%{lifetime: lifetime}) when is_number(lifetime), do: lifetime / 1
  defp hours(_type), do: nil

  defp class_keys(%{system_class: class} = info) when is_integer(class) do
    keys = Map.get(@class_keys, class, [])

    if Map.get(info, :is_shattered) && class in 1..6,
      do: keys ++ ["c#{class}-shattered"],
      else: keys
  end

  defp class_keys(_info), do: []
end
