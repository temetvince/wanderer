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

    test "letter slots cap at two letters, so names never parse as slots" do
      assert {:ok, 702} = AutoLabel.parse_slot("chain_index_letters", "ZZ", "", "", false)
      assert :error = AutoLabel.parse_slot("chain_index_letters", "HTT", "", "", false)
      assert :error = AutoLabel.parse_slot("chain_letters_only", "STAGING", "", "", false)
      assert :error = AutoLabel.parse_slot("index_letter", "HOME", "", "", false)
      assert :error = AutoLabel.parse_slot("chain_letters_only", "AAAAB", "A", "", false)
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

  describe "chain_prefix/7" do
    # Graph fixture: labels and chain-parent edges (parent -> child via a
    # chain-carrying signature). `chain_prefix` walks parents upward.
    defp prefix(system, labels, parents, format \\ "chain_index_letters") do
      AutoLabel.chain_prefix(
        system,
        fn sys -> Map.get(labels, sys, "") end,
        fn sys -> Map.get(parents, sys, []) end,
        format,
        "",
        false
      )
    end

    test "a named root with a stale chain signature into it stays a root" do
      # Home "HTT" has a legacy return-hole signature from A carrying
      # bookmark_index (the poisoning scenario), and home -> A is a real
      # chain edge - a cycle. "HTT" parses under no parent's namespace.
      labels = %{home: "HTT", a: "A"}
      parents = %{home: [:a], a: [:home]}

      assert prefix(:home, labels, parents) == ""
      assert prefix(:a, labels, parents) == "A"
    end

    test "depth-one systems chain off the root, including after renames" do
      labels = %{home: "HTT", c: "C"}
      parents = %{c: [:home]}

      # Home is a root (prefix ""), so "C" parses as a root slot: chain child.
      assert prefix(:c, labels, parents) == "C"
    end

    test "deeper chain nodes parse under their parent's label" do
      labels = %{home: "HTT", a: "A", a2: "A2"}
      parents = %{a: [:home], a2: [:a]}

      assert prefix(:a2, labels, parents) == "A2"
    end

    test "a named mid-map system with no valid parent namespace is a root" do
      labels = %{staging: "STAGING", a: "A"}
      parents = %{staging: [:a], a: []}

      assert prefix(:staging, labels, parents) == ""
    end

    test "unlabeled systems are roots" do
      assert prefix(:x, %{}, %{x: [:y]}) == ""
    end

    test "letter-only chains resolve the same way" do
      labels = %{home: "HTT", a: "A", aa: "AA"}
      parents = %{home: [:a], a: [:home], aa: [:a]}

      assert prefix(:home, labels, parents, "chain_letters_only") == ""
      assert prefix(:a, labels, parents, "chain_letters_only") == "A"
      assert prefix(:aa, labels, parents, "chain_letters_only") == "AA"
    end

    test "a chain child whose entrance closed keeps chaining off its label" do
      # Home -> B collapsed and the signature is gone, so B has no parent.
      # B, BA, BB, BC are still on the map and B's label is a root slot.
      labels = %{b: "B", ba: "BA", bb: "BB", bc: "BC"}
      parents = %{b: [], ba: [:b], bb: [:b], bc: [:b]}

      assert prefix(:b, labels, parents, "chain_letters_only") == "B"
      assert prefix(:ba, labels, parents, "chain_letters_only") == "BA"

      occupied =
        for label <- ["BA", "BB", "BC"],
            {:ok, index} = AutoLabel.parse_slot("chain_letters_only", label, "B", "", false),
            do: index

      assert AutoLabel.render("chain_letters_only", AutoLabel.next_index(occupied, false), "B", "", false) ==
               "BD"
    end

    test "orphaned numeric-children nodes are chain-shaped at any depth" do
      labels = %{a21: "A21", n121: "121"}
      parents = %{}

      assert prefix(:a21, labels, parents, "chain_index_letters") == "A21"
      assert prefix(:n121, labels, parents, "chain_index") == "121"

      dashed = %{a21: "A-2-1", n121: "1-2-1"}
      label_fn = fn sys -> Map.get(dashed, sys, "") end
      parents_fn = fn _sys -> [] end

      assert AutoLabel.chain_prefix(:a21, label_fn, parents_fn, "chain_index_letters", "-", false) == "A-2-1"
      assert AutoLabel.chain_prefix(:n121, label_fn, parents_fn, "chain_index", "-", false) == "1-2-1"
      assert AutoLabel.chain_prefix(:a21, label_fn, parents_fn, "chain_index_letters", "", false) == ""
    end

    test "named roots never qualify as orphaned chain nodes" do
      labels = %{home: "HTT", staging: "STAGING", deep: "ABA", odd: "A2X"}
      parents = %{}

      assert prefix(:home, labels, parents, "chain_letters_only") == ""
      assert prefix(:staging, labels, parents, "chain_index_letters") == ""
      # Letter-only chains are only decidable at depth one without a parent.
      assert prefix(:deep, labels, parents, "chain_letters_only") == ""
      assert prefix(:odd, labels, parents, "chain_index_letters") == ""
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
