defmodule WandererApp.Map.Server.AutoLabelImpl do
  @moduledoc """
  Server-side auto-labeling of jumped wormhole systems.

  Runs when a tracked character jumps a wormhole connection
  (`maybe_auto_label_jump/3`) and when a signature is linked to a target
  system (`maybe_auto_label/4`), applying the map-level auto-label options
  (system custom label, system tag, temporary name) for every user,
  regardless of any per-user client settings. All chain state is derived
  from the labels currently on the map (see `WandererApp.Map.AutoLabel`), so
  it survives client restarts, users without settings, and manual renames.

  Labels are only ever filled in when empty, so the two triggers compose: a
  jump names the system, and a signature linked later to the same hole
  reuses that slot for its bookmark metadata. Gate connections never label.
  """

  require Logger

  alias WandererApp.Api.MapSystemSignature
  alias WandererApp.Map.AutoLabel
  alias WandererApp.Map.Server.SignaturesImpl

  # Mirrors ConnectionsImpl's connection types (not exported there).
  @connection_type_stargate 1

  # {target kind, map option key} in priority order: the first enabled kind
  # drives the chain computation (prefix + occupied slots).
  @targets [
    {:label, "auto_label_jumped_label"},
    {:tag, "auto_label_jumped_tag"},
    {:temp_name, "auto_label_jumped_temp_name"}
  ]

  @doc """
  Computes and applies auto-labels for `target_system` after `signature_eve_id`
  (a signature in `source_system`) was linked to it. No-op unless the map has
  at least one auto-label format option enabled. Never raises.
  """
  def maybe_auto_label(map_id, source_system, target_system, signature_eve_id) do
    {:ok, options} = WandererApp.Map.get_options(map_id)

    case enabled_targets(options) do
      [] ->
        :ok

      enabled_targets ->
        # Serialize per map so two simultaneous jumps can't be handed the
        # same free slot.
        :global.trans({{:map_auto_label, map_id}, self()}, fn ->
          do_auto_label(
            map_id,
            source_system,
            target_system,
            signature_eve_id,
            options,
            enabled_targets
          )
        end)
    end
  rescue
    e ->
      Logger.error("[auto_label] Failed to auto-label system: #{Exception.message(e)}")
      :ok
  end

  @doc """
  Computes and applies auto-labels for the system a character just jumped
  into, without any signature: `target_solar_system_id` was reached from
  `source_solar_system_id`. No-op unless the map has an auto-label format
  option enabled, both systems are on the map, the connection between them
  is a wormhole (gate hops never label), and the target still has an empty
  value for some enabled kind. Never raises.

  Return holes need no special handling here: jumping back reuses the
  existing connection, and the system on the far side already has its
  label, which is never overwritten.
  """
  def maybe_auto_label_jump(map_id, source_solar_system_id, target_solar_system_id) do
    {:ok, options} = WandererApp.Map.get_options(map_id)
    enabled_targets = enabled_targets(options)

    with [_ | _] <- enabled_targets,
         {:ok, %{} = connection} <-
           WandererApp.Map.find_connection(map_id, source_solar_system_id, target_solar_system_id),
         true <- connection.type != @connection_type_stargate do
      start_at_zero = truthy_option?(options, "auto_label_start_at_zero")
      separator = Map.get(options, "auto_label_separator", "")

      :global.trans({{:map_auto_label, map_id}, self()}, fn ->
        # Re-read both systems inside the lock so a fleet jumping the same
        # hole at once sees the label the first jump assigned.
        source_system =
          WandererApp.Map.find_system_by_location(map_id, %{
            solar_system_id: source_solar_system_id
          })

        target_system =
          WandererApp.Map.find_system_by_location(map_id, %{
            solar_system_id: target_solar_system_id
          })

        unlabeled? =
          not is_nil(target_system) and
            Enum.any?(enabled_targets, fn {kind, _format} ->
              empty?(effective_value(target_system, kind))
            end)

        if not is_nil(source_system) and unlabeled? do
          assign_label(
            map_id,
            source_system,
            target_system,
            nil,
            enabled_targets,
            separator,
            start_at_zero
          )
        else
          :ok
        end
      end)
    else
      _ -> :ok
    end
  rescue
    e ->
      Logger.error("[auto_label] Failed to auto-label jumped system: #{Exception.message(e)}")
      :ok
  end

  defp enabled_targets(options) do
    @targets
    |> Enum.map(fn {kind, key} -> {kind, Map.get(options, key, "disabled")} end)
    |> Enum.filter(fn {_kind, format} -> AutoLabel.valid_format?(format) end)
  end

  defp do_auto_label(
         map_id,
         source_system,
         target_system,
         signature_eve_id,
         options,
         enabled_targets
       ) do
    signature =
      source_system.id
      |> MapSystemSignature.by_system_id!()
      |> Enum.find(fn sig -> sig.eve_id == signature_eve_id end)

    if is_nil(signature) do
      :ok
    else
      start_at_zero = truthy_option?(options, "auto_label_start_at_zero")
      separator = Map.get(options, "auto_label_separator", "")

      return_hole? =
        not is_nil(
          SignaturesImpl.find_forward_signature(target_system.id, source_system.solar_system_id)
        )

      if return_hole? and truthy_option?(options, "auto_label_ignore_return_hole") do
        handle_return_hole(signature, options, enabled_targets)
      else
        assign_label(
          map_id,
          source_system,
          target_system,
          signature,
          enabled_targets,
          separator,
          start_at_zero
        )
      end
    end
  end

  # A return hole leads back to where we came from: it must not consume a
  # chain slot (its destination already has a label). Optionally mark it with
  # the configured symbol.
  defp handle_return_hole(signature, options, enabled_targets) do
    symbol = Map.get(options, "auto_label_return_hole_symbol", "")

    custom_info =
      signature
      |> decode_custom_info()
      |> Map.delete("bookmark_index")
      |> Map.put("bookmark_index_chained", symbol)
      |> Map.put("bookmark_index_chained_letters", symbol)

    updates = %{custom_info: Jason.encode!(custom_info)}

    updates =
      if Keyword.has_key?(enabled_targets, :temp_name) and empty?(signature.temporary_name) and
           symbol != "" do
        Map.put(updates, :temporary_name, symbol)
      else
        updates
      end

    {:ok, _} = MapSystemSignature.update(signature, updates)
    :ok
  end

  defp assign_label(
         map_id,
         source_system,
         target_system,
         signature,
         enabled_targets,
         separator,
         start_at_zero
       ) do
    {primary_kind, primary_format} = List.first(enabled_targets)

    # A source system's label only acts as a chain prefix when that system is
    # itself a chain child - resolved label-consistently and recursively by
    # AutoLabel.chain_prefix/7, so a named root (e.g. a home labeled "HTT")
    # starts fresh chains even when stale legacy signatures carry chain
    # metadata into it.
    prefix =
      chain_prefix_for(
        map_id,
        source_system,
        primary_kind,
        primary_format,
        separator,
        start_at_zero
      )

    chain_child? = prefix != ""

    index =
      case AutoLabel.parse_slot(
             primary_format,
             effective_value(target_system, primary_kind),
             prefix,
             separator,
             start_at_zero
           ) do
        # The target already holds a valid slot under this prefix (e.g. a
        # relink of the same hole): keep it instead of assigning a new one.
        {:ok, existing_index} ->
          existing_index

        :error ->
          occupied =
            occupied_slots(
              map_id,
              source_system,
              target_system,
              primary_kind,
              primary_format,
              prefix,
              separator,
              start_at_zero
            )

          AutoLabel.next_index(occupied, start_at_zero)
      end

    # Each target kind renders with its own prefix (the source system's value
    # of that kind), so e.g. tags chain off tags and labels off labels.
    rendered =
      Map.new(enabled_targets, fn {kind, format} ->
        kind_prefix =
          cond do
            kind == primary_kind -> prefix
            chain_child? -> effective_value(source_system, kind)
            true -> ""
          end

        {kind, AutoLabel.render(format, index, kind_prefix, separator, start_at_zero)}
      end)

    # A jump has no signature yet; the one linked later reuses this slot.
    if not is_nil(signature) do
      update_signature(
        signature,
        index,
        prefix,
        separator,
        start_at_zero,
        Map.get(rendered, :temp_name)
      )
    end

    Enum.each(rendered, fn {kind, value} ->
      apply_target(map_id, target_system, kind, value)
    end)

    :ok
  end

  # Occupied slots are parsed from labels actually in use on the map:
  #  - systems linked from the source system's other signatures, and systems
  #    on the far end of its wormhole connections (siblings)
  #  - for chain formats, every map system whose label parses under the
  #    prefix (catches renames and leftovers from closed holes)
  # The target system itself never counts against its own assignment.
  defp occupied_slots(
         map_id,
         source_system,
         target_system,
         kind,
         format,
         prefix,
         separator,
         start_at_zero
       ) do
    {:ok, systems} = WandererApp.Map.list_systems(map_id)
    systems_by_solar_id = Map.new(systems, fn system -> {system.solar_system_id, system} end)

    signature_siblings =
      source_system.id
      |> MapSystemSignature.by_system_id!()
      |> Enum.filter(fn sig ->
        sig.group == "Wormhole" and not is_nil(sig.linked_system_id)
      end)
      |> Enum.map(fn sig -> Map.get(systems_by_solar_id, sig.linked_system_id) end)
      |> Enum.reject(&is_nil/1)

    connection_siblings =
      map_id
      |> wormhole_neighbours(source_system.solar_system_id)
      |> Enum.map(fn solar_id -> Map.get(systems_by_solar_id, solar_id) end)
      |> Enum.reject(&is_nil/1)

    chain_systems =
      if AutoLabel.chained?(format) do
        systems
      else
        []
      end

    (signature_siblings ++ connection_siblings ++ chain_systems)
    |> Enum.uniq_by(& &1.solar_system_id)
    |> Enum.reject(fn system ->
      system.solar_system_id == target_system.solar_system_id or
        system.solar_system_id == source_system.solar_system_id
    end)
    |> Enum.reduce(MapSet.new(), fn system, acc ->
      case AutoLabel.parse_slot(
             format,
             effective_value(system, kind),
             prefix,
             separator,
             start_at_zero
           ) do
        {:ok, index} -> MapSet.put(acc, index)
        :error -> acc
      end
    end)
  end

  defp update_signature(signature, index, prefix, separator, start_at_zero, temp_name_value) do
    custom_info =
      signature
      |> decode_custom_info()
      |> Map.put("bookmark_index", index)
      |> Map.put(
        "bookmark_index_chained",
        AutoLabel.render("chain_index", index, prefix, separator, start_at_zero)
      )
      |> Map.put(
        "bookmark_index_chained_letters",
        AutoLabel.render("chain_index_letters", index, prefix, separator, start_at_zero)
      )

    updates = %{custom_info: Jason.encode!(custom_info)}

    updates =
      if not is_nil(temp_name_value) and temp_name_value != "" and
           empty?(signature.temporary_name) do
        Map.put(updates, :temporary_name, temp_name_value)
      else
        updates
      end

    {:ok, _} = MapSystemSignature.update(signature, updates)
    :ok
  end

  # Only ever fills empty targets: a value someone set by hand (or a label
  # assigned earlier) is never overwritten.
  defp apply_target(map_id, target_system, kind, value) do
    if empty?(effective_value(target_system, kind)) and value != "" do
      case kind do
        :tag ->
          WandererApp.Map.Server.update_system_tag(map_id, %{
            solar_system_id: target_system.solar_system_id,
            tag: value
          })

        :temp_name ->
          WandererApp.Map.Server.update_system_temporary_name(map_id, %{
            solar_system_id: target_system.solar_system_id,
            temporary_name: value
          })

        :label ->
          labels =
            case Jason.decode(target_system.labels || "") do
              {:ok, %{} = decoded} -> decoded
              _ -> %{"labels" => [], "customLabel" => ""}
            end

          WandererApp.Map.Server.update_system_labels(map_id, %{
            solar_system_id: target_system.solar_system_id,
            labels: labels |> Map.put("customLabel", value) |> Jason.encode!()
          })
      end
    end

    :ok
  end

  # Wires AutoLabel.chain_prefix/7 to this map's data: labels come from the
  # map cache; parent candidates are systems whose non-deleted signature on
  # this map links into the given system carrying chain metadata
  # (bookmark_index), plus its wormhole neighbours, so jump-labeled systems
  # without any signature still resolve. Label consistency picks the real
  # parent among the candidates.
  defp chain_prefix_for(map_id, source_system, kind, format, separator, start_at_zero) do
    {:ok, systems} = WandererApp.Map.list_systems(map_id)
    by_solar_id = Map.new(systems, fn system -> {system.solar_system_id, system} end)
    by_uuid = Map.new(systems, fn system -> {system.id, system} end)
    map_system_uuids = MapSet.new(systems, & &1.id)

    label_fn = fn solar_id ->
      case Map.get(by_solar_id, solar_id) do
        nil -> ""
        system -> effective_value(system, kind)
      end
    end

    parents_fn = fn solar_id ->
      signature_parents =
        solar_id
        |> MapSystemSignature.by_linked_system_id!()
        |> Enum.filter(fn sig ->
          not sig.deleted and
            MapSet.member?(map_system_uuids, sig.system_id) and
            sig |> decode_custom_info() |> Map.has_key?("bookmark_index")
        end)
        |> Enum.map(fn sig -> Map.get(by_uuid, sig.system_id) end)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(& &1.solar_system_id)

      (signature_parents ++ wormhole_neighbours(map_id, solar_id))
      |> Enum.filter(&Map.has_key?(by_solar_id, &1))
      |> Enum.uniq()
    end

    AutoLabel.chain_prefix(
      source_system.solar_system_id,
      label_fn,
      parents_fn,
      format,
      separator,
      start_at_zero
    )
  end

  # Solar system ids on the far end of the wormhole connections touching
  # `solar_system_id`. Gate connections never take part in chains.
  defp wormhole_neighbours(map_id, solar_system_id) do
    map_id
    |> WandererApp.Map.find_connections(solar_system_id)
    |> Enum.reject(fn connection -> connection.type == @connection_type_stargate end)
    |> Enum.map(fn connection ->
      if connection.solar_system_source == solar_system_id,
        do: connection.solar_system_target,
        else: connection.solar_system_source
    end)
    |> Enum.uniq()
  end

  defp effective_value(system, :label) do
    case Jason.decode(system.labels || "") do
      {:ok, %{"customLabel" => custom}} when is_binary(custom) -> String.trim(custom)
      _ -> ""
    end
  end

  defp effective_value(system, :tag), do: String.trim(system.tag || "")
  defp effective_value(system, :temp_name), do: String.trim(system.temporary_name || "")

  defp decode_custom_info(%{custom_info: nil}), do: %{}

  defp decode_custom_info(%{custom_info: custom_info}) do
    case Jason.decode(custom_info) do
      {:ok, %{} = decoded} -> decoded
      _ -> %{}
    end
  end

  defp truthy_option?(options, key), do: Map.get(options, key, "false") in ["true", true]

  defp empty?(value), do: value in [nil, ""]
end
