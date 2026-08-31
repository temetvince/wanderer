defmodule WandererApp.Map.Server.AutoLabelImpl do
  @moduledoc """
  Server-side auto-labeling of jumped wormhole systems.

  Runs when a signature is linked to a target system and applies the
  map-level auto-label options (system custom label, system tag, temporary
  name) for every user, regardless of any per-user client settings. All
  chain state is derived from the labels currently on the map (see
  `WandererApp.Map.AutoLabel`), so it survives client restarts, users
  without settings, and manual renames.
  """

  require Logger

  alias WandererApp.Api.MapSystemSignature
  alias WandererApp.Map.AutoLabel
  alias WandererApp.Map.Server.SignaturesImpl

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

    enabled_targets =
      @targets
      |> Enum.map(fn {kind, key} -> {kind, Map.get(options, key, "disabled")} end)
      |> Enum.filter(fn {_kind, format} -> AutoLabel.valid_format?(format) end)

    case enabled_targets do
      [] ->
        :ok

      _ ->
        # Serialize per map so two simultaneous jumps can't be handed the
        # same free slot.
        :global.trans({{:map_auto_label, map_id}, self()}, fn ->
          do_auto_label(map_id, source_system, target_system, signature_eve_id, options, enabled_targets)
        end)
    end
  rescue
    e ->
      Logger.error("[auto_label] Failed to auto-label system: #{Exception.message(e)}")
      :ok
  end

  defp do_auto_label(map_id, source_system, target_system, signature_eve_id, options, enabled_targets) do
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
        not is_nil(SignaturesImpl.find_forward_signature(target_system.id, source_system.solar_system_id))

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

  defp assign_label(map_id, source_system, target_system, signature, enabled_targets, separator, start_at_zero) do
    {primary_kind, primary_format} = List.first(enabled_targets)

    # A source system's label only acts as a chain prefix when that system is
    # itself a chain child. A root system with a custom name (e.g. a home
    # labeled "HTT") starts a fresh chain, so its holes get A, B, C - not
    # "HTTA".
    chain_child? = chain_child?(map_id, source_system)
    prefix = if chain_child?, do: effective_value(source_system, primary_kind), else: ""

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

    update_signature(signature, index, prefix, separator, start_at_zero, Map.get(rendered, :temp_name))

    Enum.each(rendered, fn {kind, value} ->
      apply_target(map_id, target_system, kind, value)
    end)

    :ok
  end

  # Occupied slots are parsed from labels actually in use on the map:
  #  - systems linked from the source system's other signatures (siblings)
  #  - for chain formats, every map system whose label parses under the
  #    prefix (catches renames and leftovers from closed holes)
  # The target system itself never counts against its own assignment.
  defp occupied_slots(map_id, source_system, target_system, kind, format, prefix, separator, start_at_zero) do
    {:ok, systems} = WandererApp.Map.list_systems(map_id)
    systems_by_solar_id = Map.new(systems, fn system -> {system.solar_system_id, system} end)

    sibling_systems =
      source_system.id
      |> MapSystemSignature.by_system_id!()
      |> Enum.filter(fn sig ->
        sig.group == "Wormhole" and not is_nil(sig.linked_system_id)
      end)
      |> Enum.map(fn sig -> Map.get(systems_by_solar_id, sig.linked_system_id) end)
      |> Enum.reject(&is_nil/1)

    chain_systems =
      if AutoLabel.chained?(format) do
        systems
      else
        []
      end

    (sibling_systems ++ chain_systems)
    |> Enum.uniq_by(& &1.solar_system_id)
    |> Enum.reject(fn system ->
      system.solar_system_id == target_system.solar_system_id or
        system.solar_system_id == source_system.solar_system_id
    end)
    |> Enum.reduce(MapSet.new(), fn system, acc ->
      case AutoLabel.parse_slot(format, effective_value(system, kind), prefix, separator, start_at_zero) do
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
      |> Map.put("bookmark_index_chained", AutoLabel.render("chain_index", index, prefix, separator, start_at_zero))
      |> Map.put(
        "bookmark_index_chained_letters",
        AutoLabel.render("chain_index_letters", index, prefix, separator, start_at_zero)
      )

    updates = %{custom_info: Jason.encode!(custom_info)}

    updates =
      if not is_nil(temp_name_value) and temp_name_value != "" and empty?(signature.temporary_name) do
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

  # A system is a chain child when some signature on this map links to it
  # carrying chain metadata (bookmark_index) - which the server writes on
  # every labeled jump. A home or staging system never qualifies: nothing
  # links into it except return holes, whose bookmark_index is deliberately
  # stripped. Renames don't affect this - metadata only answers "is this part
  # of a chain", while the current label supplies the prefix text.
  defp chain_child?(map_id, source_system) do
    {:ok, systems} = WandererApp.Map.list_systems(map_id)
    map_system_ids = MapSet.new(systems, & &1.id)

    source_system.solar_system_id
    |> MapSystemSignature.by_linked_system_id!()
    |> Enum.any?(fn sig ->
      not sig.deleted and
        MapSet.member?(map_system_ids, sig.system_id) and
        sig |> decode_custom_info() |> Map.has_key?("bookmark_index")
    end)
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
