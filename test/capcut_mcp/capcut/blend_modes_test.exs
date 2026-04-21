defmodule CapcutMcp.CapCut.BlendModesTest do
  use ExUnit.Case, async: false

  alias CapcutMcp.CapCut.BlendModes

  setup do
    BlendModes.invalidate_cache()
    on_exit(fn -> BlendModes.invalidate_cache() end)
    :ok
  end

  @tag :tmp_dir
  test "list_modes uses LOCALAPPDATA fallback and picks newest semver version", %{
    tmp_dir: tmp_dir
  } do
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

  # ── Telemetry cases (D1c) ──────────────────────────────────────────────────

  @tag :tmp_dir
  test "list_modes emits :load telemetry once, subsequent calls hit the cache", %{
    tmp_dir: tmp_dir
  } do
    previous_localappdata = System.get_env("LOCALAPPDATA")
    previous_apps_path = System.get_env("CAPCUT_APPS_PATH")

    on_exit(fn ->
      restore_env("LOCALAPPDATA", previous_localappdata)
      restore_env("CAPCUT_APPS_PATH", previous_apps_path)
    end)

    System.delete_env("CAPCUT_APPS_PATH")
    System.put_env("LOCALAPPDATA", tmp_dir)
    create_mix_mode(tmp_dir, "8.0.0", "effect")

    attach_load_event()

    assert {:ok, modes} = BlendModes.list_modes()

    assert_receive {[:capcut_mcp, :blend_modes, :load], %{duration: duration},
                    %{result: :ok, count: count, path: path}}

    assert is_integer(duration) and duration >= 0
    assert count == length(modes)
    assert String.ends_with?(path, Path.join(["8.0.0", "Resources", "MixMode"]))

    assert {:ok, _} = BlendModes.list_modes()
    refute_receive {[:capcut_mcp, :blend_modes, :load], _, _}, 50
  end

  @tag :tmp_dir
  test "load failure emits :load telemetry with result: :error", %{tmp_dir: tmp_dir} do
    previous_apps_path = System.get_env("CAPCUT_APPS_PATH")
    on_exit(fn -> restore_env("CAPCUT_APPS_PATH", previous_apps_path) end)

    System.put_env("CAPCUT_APPS_PATH", Path.join(tmp_dir, "does-not-exist"))

    attach_load_event()

    assert {:error, _reason} = BlendModes.list_modes()

    assert_receive {[:capcut_mcp, :blend_modes, :load], %{duration: _},
                    %{result: :error, reason: _}}
  end

  defp attach_load_event do
    handler_id = {:blend_modes_load, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:capcut_mcp, :blend_modes, :load],
        fn event, measurements, metadata, _ ->
          send(test_pid, {event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
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
