defmodule WandererApp.Map.TemporaryNotes do
  @moduledoc """
  A system's temporary notes (fork).

  A free-text note that, unlike `description`, does not outlive the system's
  time on the map: it is dropped the moment the system is removed (by a user or
  by the inactivity cleanup). There is no column for it; it lives in the
  system's `labels` field, which is already a JSON object
  (`{"labels": [...], "customLabel": "..."}`) that every writer decodes,
  changes and re-encodes, under the key `"tempNotes"`. The map UI
  (`LabelsManager`) reads and writes the same key.

  Pure: no IO. Every function tolerates nil, empty and non-JSON `labels`.
  """

  @key "tempNotes"

  @doc "The key inside the labels JSON object."
  def key, do: @key

  @doc "The temporary notes stored in `labels`, or nil when there is none."
  def get(labels) do
    case decode(labels) do
      {:ok, %{@key => value}} when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  @doc "Whether `labels` carries a temporary notes."
  def present?(labels), do: not is_nil(get(labels))

  @doc """
  `labels` without its temporary notes. Returns the input unchanged when
  it carries none (including nil and non-JSON values), so callers can compare
  the result with the input to decide whether a write is needed.
  """
  def strip(labels) do
    case decode(labels) do
      {:ok, %{@key => _} = decoded} -> decoded |> Map.delete(@key) |> Jason.encode!()
      _ -> labels
    end
  end

  defp decode(labels) when is_binary(labels) and labels != "" do
    case Jason.decode(labels) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _ -> :error
    end
  end

  defp decode(_labels), do: :error
end
