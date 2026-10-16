defmodule WandererApp.Map.SystemStatusTest do
  use ExUnit.Case, async: true

  alias WandererApp.Map.SystemStatus

  @default "J123456"
  @home 1
  @target 5

  defp system(attrs), do: Map.merge(%{name: @default, custom_name: nil, status: @target}, attrs)

  describe "enabled?/1" do
    test "off unless the option is explicitly true" do
      refute SystemStatus.enabled?(%{})
      refute SystemStatus.enabled?(%{SystemStatus.option_key() => "false"})
      refute SystemStatus.enabled?(nil)
      assert SystemStatus.enabled?(%{SystemStatus.option_key() => "true"})
      assert SystemStatus.enabled?(%{SystemStatus.option_key() => true})
    end
  end

  describe "custom_named?/2" do
    test "a system carrying the default name is not custom named" do
      refute SystemStatus.custom_named?(system(%{}), @default)
      refute SystemStatus.custom_named?(system(%{name: "  #{@default} "}), @default)
    end

    test "a blank or missing name is not custom named" do
      refute SystemStatus.custom_named?(system(%{name: ""}), @default)
      refute SystemStatus.custom_named?(system(%{name: "   "}), @default)
      refute SystemStatus.custom_named?(system(%{name: nil}), @default)
      refute SystemStatus.custom_named?(%{status: @target}, @default)
    end

    test "a name different from the default is custom" do
      assert SystemStatus.custom_named?(system(%{name: "HOME"}), @default)
      assert SystemStatus.custom_named?(system(%{name: "Staging"}), nil)
    end

    test "a custom_name counts even when name is the default" do
      assert SystemStatus.custom_named?(system(%{custom_name: "HQ"}), @default)
      refute SystemStatus.custom_named?(system(%{custom_name: "  "}), @default)
    end
  end

  describe "clear?/2" do
    test "only an unnamed system with a status is cleared" do
      assert SystemStatus.clear?(system(%{status: @home}), @default)
      refute SystemStatus.clear?(system(%{status: 0}), @default)
      refute SystemStatus.clear?(system(%{status: nil}), @default)
      refute SystemStatus.clear?(system(%{name: "HOME", status: @home}), @default)
      refute SystemStatus.clear?(system(%{custom_name: "HQ", status: @home}), @default)
    end
  end

  describe "after_removal/2" do
    test "a custom named system keeps its status" do
      assert SystemStatus.after_removal(system(%{name: "HOME", status: @home}), @default) == @home

      assert SystemStatus.after_removal(system(%{custom_name: "HQ", status: @target}), @default) ==
               @target
    end

    test "a default named system loses its status" do
      assert SystemStatus.after_removal(system(%{status: @home}), @default) ==
               SystemStatus.clear()

      assert SystemStatus.after_removal(system(%{status: @target}), @default) ==
               SystemStatus.clear()
    end

    test "clear stays clear either way" do
      assert SystemStatus.after_removal(system(%{status: 0}), @default) == 0
      assert SystemStatus.after_removal(system(%{name: "HOME", status: 0}), @default) == 0
    end
  end

  test "set?/1" do
    refute SystemStatus.set?(nil)
    refute SystemStatus.set?(0)
    assert SystemStatus.set?(@home)
    assert SystemStatus.set?(@target)
  end
end
