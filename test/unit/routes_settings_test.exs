defmodule WandererApp.Map.RoutesSettingsTest do
  use ExUnit.Case, async: true

  alias WandererApp.Map.RoutesSettings

  @full %{
    "path_type" => "secure",
    "include_mass_crit" => true,
    "include_eol" => false,
    "include_frig" => true,
    "include_cruise" => false,
    "avoid_wormholes" => false,
    "avoid_pochven" => true,
    "avoid_edencom" => false,
    "avoid_triglavian" => true,
    "include_thera" => false,
    "avoid" => [30_000_142]
  }

  test "keeps every known setting under its atom key" do
    assert RoutesSettings.from_params(@full) == %{
             path_type: "secure",
             include_mass_crit: true,
             include_eol: false,
             include_frig: true,
             include_cruise: false,
             avoid_wormholes: false,
             avoid_pochven: true,
             avoid_edencom: false,
             avoid_triglavian: true,
             include_thera: false,
             avoid: [30_000_142]
           }
  end

  test "a missing key drops only that setting, never the others" do
    params = Map.delete(@full, "avoid")

    result = RoutesSettings.from_params(params)

    refute Map.has_key?(result, :avoid)
    assert result.include_thera == false
    assert result.avoid_triglavian == true
    assert result.path_type == "secure"
  end

  test "false is a value, nil is an absence" do
    result = RoutesSettings.from_params(%{"include_thera" => false, "avoid_pochven" => nil})

    assert result == %{include_thera: false}
  end

  test "unknown keys are dropped" do
    result = RoutesSettings.from_params(%{"include_thera" => true, "datasource" => "singularity"})

    assert result == %{include_thera: true}
  end

  test "anything that is not a map yields no settings" do
    assert RoutesSettings.from_params(nil) == %{}
    assert RoutesSettings.from_params("secure") == %{}
    assert RoutesSettings.from_params([]) == %{}
  end
end
