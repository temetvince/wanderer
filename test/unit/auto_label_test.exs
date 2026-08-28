defmodule WandererApp.Map.AutoLabelTest do
  use ExUnit.Case, async: true

  alias WandererApp.Map.AutoLabel

  describe "number_to_letters/2 and letters_to_number/2" do
    test "bijective base-26 round trip" do
      assert AutoLabel.number_to_letters(1) == "A"
      assert AutoLabel.number_to_letters(2) == "B"
      assert AutoLabel.number_to_letters(26) == "Z"
      assert AutoLabel.number_to_letters(27) == "AA"
      assert AutoLabel.number_to_letters(52) == "AZ"
      assert AutoLabel.number_to_letters(53) == "BA"

      for n <- 1..1000 do
        assert {:ok, ^n} = AutoLabel.letters_to_number(AutoLabel.number_to_letters(n))
      end
    end

    test "start_at_zero shifts the base" do
      assert AutoLabel.number_to_letters(0, true) == "A"
      assert AutoLabel.number_to_letters(1, true) == "B"
      assert {:ok, 0} = AutoLabel.letters_to_number("A", true)
      assert {:ok, 1} = AutoLabel.letters_to_number("B", true)
    end

    test "letters_to_number rejects non-letter input" do
      assert :error = AutoLabel.letters_to_number("A1")
      assert :error = AutoLabel.letters_to_number("1")
      assert :error = AutoLabel.letters_to_number("")
      assert :error = AutoLabel.letters_to_number(nil)
    end

    test "letters_to_number is case-insensitive and trims" do
      assert {:ok, 1} = AutoLabel.letters_to_number(" a ")
      assert {:ok, 27} = AutoLabel.letters_to_number("aa")
    end
  end

  describe "render/5" do
    test "index and index_letter ignore the prefix" do
      assert AutoLabel.render("index", 3, "A", "", false) == "3"
      assert AutoLabel.render("index_letter", 3, "A", "", false) == "C"
    end

    test "chain_index" do
      assert AutoLabel.render("chain_index", 2, "", "", false) == "2"
      assert AutoLabel.render("chain_index", 2, "1", "", false) == "12"
      assert AutoLabel.render("chain_index", 1, "12", "", false) == "121"
    end

    test "chain_index_letters: letter roots, numeric children" do
      assert AutoLabel.render("chain_index_letters", 1, "", "", false) == "A"
      assert AutoLabel.render("chain_index_letters", 2, "A", "", false) == "A2"
      assert AutoLabel.render("chain_index_letters", 1, "A2", "", false) == "A21"
    end

    test "chain_letters_only: letters at every depth" do
      assert AutoLabel.render("chain_letters_only", 1, "", "", false) == "A"
      assert AutoLabel.render("chain_letters_only", 1, "A", "", false) == "AA"
      assert AutoLabel.render("chain_letters_only", 2, "AA", "", false) == "AAB"
      # The A121 example: A -> 1 -> 2 -> 1 becomes A -> A -> B -> A
      assert AutoLabel.render("chain_letters_only", 1, "AAB", "", false) == "AABA"
    end

    test "separator is inserted between prefix and slot" do
      assert AutoLabel.render("chain_index_letters", 2, "A", "-", false) == "A-2"
      assert AutoLabel.render("chain_letters_only", 2, "A", ".", false) == "A.B"
    end
  end

  describe "parse_slot/5" do
    test "roots parse whole labels" do
      assert {:ok, 3} = AutoLabel.parse_slot("chain_index_letters", "C", "", "", false)
      assert {:ok, 3} = AutoLabel.parse_slot("chain_letters_only", "C", "", "", false)
      assert {:ok, 3} = AutoLabel.parse_slot("chain_index", "3", "", "", false)
      assert {:ok, 3} = AutoLabel.parse_slot("index", "3", "", "", false)
      assert {:ok, 3} = AutoLabel.parse_slot("index_letter", "C", "", "", false)
    end

    test "children parse prefix plus remainder" do
      assert {:ok, 2} = AutoLabel.parse_slot("chain_index_letters", "A2", "A", "", false)
      assert {:ok, 21} = AutoLabel.parse_slot("chain_index_letters", "A21", "A", "", false)
      assert {:ok, 1} = AutoLabel.parse_slot("chain_index_letters", "A21", "A2", "", false)
      assert {:ok, 2} = AutoLabel.parse_slot("chain_letters_only", "AB", "A", "", false)
      assert {:ok, 1} = AutoLabel.parse_slot("chain_letters_only", "AABA", "AAB", "", false)
    end

    test "labels of other chains and free-form names do not occupy slots" do
      assert :error = AutoLabel.parse_slot("chain_index_letters", "B2", "A", "", false)
      assert :error = AutoLabel.parse_slot("chain_index_letters", "A", "A", "", false)
      assert :error = AutoLabel.parse_slot("chain_index_letters", "STAGING", "A", "", false)
      assert :error = AutoLabel.parse_slot("chain_index_letters", "A2X", "A", "", false)
      assert :error = AutoLabel.parse_slot("chain_letters_only", "A2", "A", "", false)
      assert :error = AutoLabel.parse_slot("chain_index_letters", "", "A", "", false)
      assert :error = AutoLabel.parse_slot("chain_index_letters", nil, "A", "", false)
    end

    test "prefix match is case-insensitive" do
      assert {:ok, 2} = AutoLabel.parse_slot("chain_index_letters", "a2", "A", "", false)
    end

    test "separator must be present when configured" do
      assert {:ok, 2} = AutoLabel.parse_slot("chain_index_letters", "A-2", "A", "-", false)
      assert :error = AutoLabel.parse_slot("chain_index_letters", "A2", "A", "-", false)
    end

    test "render and parse are inverse for every format" do
      for format <- AutoLabel.formats(),
          prefix <- ["", "A", "A2", "AB"],
          index <- [1, 2, 12, 27] do
        label = AutoLabel.render(format, index, prefix, "", false)

        parse_prefix =
          if format in ["index", "index_letter"] do
            ""
          else
            prefix
          end

        assert {:ok, ^index} = AutoLabel.parse_slot(format, label, parse_prefix, "", false),
               "#{format} failed round trip: prefix=#{prefix} index=#{index} label=#{label}"
      end
    end
  end

  describe "next_index/2" do
    test "returns the lowest free slot" do
      assert AutoLabel.next_index([], false) == 1
      assert AutoLabel.next_index([1, 2, 3], false) == 4
      assert AutoLabel.next_index([1, 3], false) == 2
      assert AutoLabel.next_index([2, 3], false) == 1
      assert AutoLabel.next_index([], true) == 0
      assert AutoLabel.next_index([0, 1], true) == 2
    end

    test "rename scenario: renaming B to C frees B and blocks C" do
      # Home has children A and B. Someone renames B's system to C.
      # Occupied is parsed from the labels in use: A (1) and C (3).
      occupied =
        for label <- ["A", "C"],
            {:ok, index} = AutoLabel.parse_slot("chain_index_letters", label, "", "", false),
            do: index

      # The next hole gets B (slot 2), and C (slot 3) is never handed out again.
      assert AutoLabel.next_index(occupied, false) == 2
      assert AutoLabel.render("chain_index_letters", 2, "", "", false) == "B"
    end
  end
end
