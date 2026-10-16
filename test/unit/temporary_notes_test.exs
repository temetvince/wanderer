defmodule WandererApp.Map.TemporaryNotesTest do
  use ExUnit.Case, async: true

  alias WandererApp.Map.TemporaryNotes

  @with_note ~s({"labels":["la"],"customLabel":"B","tempNotes":"hole is crit"})
  @without_note ~s({"labels":["la"],"customLabel":"B"})

  describe "get/1" do
    test "returns the trimmed note" do
      assert TemporaryNotes.get(@with_note) == "hole is crit"
      assert TemporaryNotes.get(~s({"tempNotes":"  x  "})) == "x"
    end

    test "returns nil when absent, blank, or not a string" do
      assert TemporaryNotes.get(@without_note) == nil
      assert TemporaryNotes.get(~s({"tempNotes":"   "})) == nil
      assert TemporaryNotes.get(~s({"tempNotes":5})) == nil
    end

    test "tolerates nil, empty and legacy comma-separated labels" do
      assert TemporaryNotes.get(nil) == nil
      assert TemporaryNotes.get("") == nil
      assert TemporaryNotes.get("la,lb") == nil
      assert TemporaryNotes.get("[1,2]") == nil
    end
  end

  test "present?/1" do
    assert TemporaryNotes.present?(@with_note)
    refute TemporaryNotes.present?(@without_note)
    refute TemporaryNotes.present?(nil)
  end

  describe "strip/1" do
    test "removes the note and keeps everything else" do
      stripped = TemporaryNotes.strip(@with_note)

      assert Jason.decode!(stripped) == %{"labels" => ["la"], "customLabel" => "B"}
      refute TemporaryNotes.present?(stripped)
    end

    test "returns the input unchanged when there is nothing to strip" do
      assert TemporaryNotes.strip(@without_note) == @without_note
      assert TemporaryNotes.strip(nil) == nil
      assert TemporaryNotes.strip("") == ""
      assert TemporaryNotes.strip("la,lb") == "la,lb"
    end
  end
end
