defmodule WandererApp.Map.AutoLabel do
  @moduledoc """
  Pure functions for computing auto-labels ("chain labels") for wormhole
  systems as they are jumped and linked.

  The model: the label of a newly linked system is derived from the label of
  the system it was jumped from (the prefix) plus the lowest free slot index
  among that source system's existing children. A system with no label starts
  a new root chain (letters at depth one for letter formats).

  Occupied slots are parsed from the labels currently on the map rather than
  from stored bookmark metadata, so manual renames are respected: renaming a
  system from B to C frees the B slot and blocks C from being handed out
  again at that depth.

  Formats:

    * `"index"`               - plain numeric index per system (1, 2, 3)
    * `"index_letter"`        - plain letter index per system (A, B, C)
    * `"chain_index"`         - numeric chain (1, 11, 12, 121)
    * `"chain_index_letters"` - letter roots, numeric children (A, A1, A21)
    * `"chain_letters_only"`  - letters at every depth (A, AA, ABA)
  """

  @chain_formats ~w(chain_index chain_index_letters chain_letters_only)
  @formats ~w(index index_letter) ++ @chain_formats

  @doc "All supported (enabled) format values."
  def formats, do: @formats

  @doc "Whether the value names a supported, enabled format."
  def valid_format?(format), do: format in @formats

  @doc "Whether the format builds hierarchical chain labels."
  def chained?(format), do: format in @chain_formats

  @doc """
  Converts a 1-based index to bijective base-26 letters (1 -> A, 26 -> Z,
  27 -> AA). With `start_at_zero`, the index is treated as 0-based (0 -> A).
  """
  def number_to_letters(num, start_at_zero \\ false) do
    num = if start_at_zero, do: num + 1, else: num
    do_number_to_letters(num, "")
  end

  defp do_number_to_letters(num, acc) when num <= 0, do: acc

  defp do_number_to_letters(num, acc) do
    mod = rem(num - 1, 26)
    do_number_to_letters(div(num - mod, 26), <<?A + mod::utf8>> <> acc)
  end

  @doc """
  Inverse of `number_to_letters/2`. Returns `{:ok, index}` for a pure-letter
  string, `:error` otherwise.
  """
  def letters_to_number(letters, start_at_zero \\ false)
  def letters_to_number(nil, _start_at_zero), do: :error

  def letters_to_number(letters, start_at_zero) do
    letters = letters |> String.trim() |> String.upcase()

    if letters != "" and letters =~ ~r/^[A-Z]+$/ do
      num =
        letters
        |> String.to_charlist()
        |> Enum.reduce(0, fn char, acc -> acc * 26 + (char - ?A + 1) end)

      {:ok, if(start_at_zero, do: num - 1, else: num)}
    else
      :error
    end
  end

  @doc """
  Renders the label for slot `index` under `prefix` (the source system's
  label, `""` for a root chain).
  """
  def render(format, index, prefix, separator, start_at_zero)

  def render("index", index, _prefix, _separator, _start_at_zero), do: Integer.to_string(index)

  def render("index_letter", index, _prefix, _separator, start_at_zero),
    do: number_to_letters(index, start_at_zero)

  def render("chain_index", index, "", _separator, _start_at_zero), do: Integer.to_string(index)

  def render("chain_index", index, prefix, separator, _start_at_zero),
    do: prefix <> separator <> Integer.to_string(index)

  def render("chain_index_letters", index, "", _separator, start_at_zero),
    do: number_to_letters(index, start_at_zero)

  def render("chain_index_letters", index, prefix, separator, _start_at_zero),
    do: prefix <> separator <> Integer.to_string(index)

  def render("chain_letters_only", index, "", _separator, start_at_zero),
    do: number_to_letters(index, start_at_zero)

  def render("chain_letters_only", index, prefix, separator, start_at_zero),
    do: prefix <> separator <> number_to_letters(index, start_at_zero)

  @doc """
  Parses an existing label back into the slot index it occupies under
  `prefix`. Returns `{:ok, index}` when the label is a sibling slot of that
  prefix, `:error` otherwise (including labels of other chains, free-form
  names, and empty labels).
  """
  def parse_slot(format, label, prefix, separator, start_at_zero)

  def parse_slot(_format, label, _prefix, _separator, _start_at_zero)
      when label in [nil, ""],
      do: :error

  def parse_slot("index", label, _prefix, _separator, _start_at_zero),
    do: parse_digits(String.trim(label))

  def parse_slot("index_letter", label, _prefix, _separator, start_at_zero),
    do: letters_to_number(label, start_at_zero)

  def parse_slot(format, label, "", _separator, start_at_zero) when format in @chain_formats do
    case format do
      "chain_index" -> parse_digits(String.trim(label))
      _letter_rooted -> letters_to_number(label, start_at_zero)
    end
  end

  def parse_slot(format, label, prefix, separator, start_at_zero)
      when format in @chain_formats do
    label = String.trim(label)
    full_prefix = prefix <> separator
    prefix_len = String.length(full_prefix)

    with true <- String.length(label) > prefix_len,
         true <- String.upcase(String.slice(label, 0, prefix_len)) == String.upcase(full_prefix) do
      rest = String.slice(label, prefix_len..-1//1)

      case format do
        "chain_letters_only" -> letters_to_number(rest, start_at_zero)
        _numeric_children -> parse_digits(rest)
      end
    else
      _ -> :error
    end
  end

  def parse_slot(_format, _label, _prefix, _separator, _start_at_zero), do: :error

  @doc """
  Returns the lowest free slot index given the occupied set (an Enumerable of
  integers).
  """
  def next_index(occupied, start_at_zero \\ false) do
    occupied = MapSet.new(occupied)
    start = if start_at_zero, do: 0, else: 1

    Stream.iterate(start, &(&1 + 1))
    |> Enum.find(&(not MapSet.member?(occupied, &1)))
  end

  defp parse_digits(string) do
    case Integer.parse(string) do
      {num, ""} when num >= 0 -> {:ok, num}
      _ -> :error
    end
  end
end
