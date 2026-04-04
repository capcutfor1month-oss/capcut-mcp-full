defmodule CapcutMcp.CapCut.BlendModesTest do
  use ExUnit.Case, async: false

  alias CapcutMcp.CapCut.BlendModes

  @tag :tmp_dir
  test "list_modes uses LOCALAPPDATA fallback and picks newest semver version", %{tmp_dir: tmp_dir} do
    previous_localappdata = System.get_env("LOCALAPPDATA")
    previous_apps_path = System.get_env("CAPCUT_APPS_PATH")

    on_exit(fn ->
      restore_env("LOCALAPPDATA", previous_localappdata)
      restore_env("CAPCUT_APPS_PATH", previous_apps_path)
    end)

    System.delete_env("CAPCUT_APPS_PATH")
    System.put_env("LOCALAPPDATA", tmp_dir)

    create_mix_mode(tmp_dir, "5.9.0", "old-effect")
    create_mix_mode(tmp_dir, "10.0.0", "new-effect")

    assert {:ok, modes} = BlendModes.list_modes()
    assert [%{effect_id: "new-effect"}] = Enum.filter(modes, &(&1.name_id == "soft_light"))
  end

  defp create_mix_mode(localappdata, version, effect_id) do
    mix_mode_dir = Path.join([localappdata, "CapCut", "Apps", version, "Resources", "MixMode"])
    File.mkdir_p!(mix_mode_dir)

    json =
      Jason.encode!(%{
        "resourceList" => [
          %{
            "nameId" => "soft_light",
            "effectId" => effect_id,
            "resourceId" => "#{version}-resource",
            "path" => "soft-light"
          }
        ]
      })

    File.write!(Path.join(mix_mode_dir, "MixMode.json"), json)
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
