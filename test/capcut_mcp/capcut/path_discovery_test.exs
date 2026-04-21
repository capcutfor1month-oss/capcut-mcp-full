defmodule CapcutMcp.CapCut.PathDiscoveryTest do
  use ExUnit.Case, async: false

  alias CapcutMcp.CapCut.PathDiscovery

  setup do
    previous_env = Application.get_env(:capcut_mcp, :capcut_path)
    previous_localappdata = System.get_env("LOCALAPPDATA")

    on_exit(fn ->
      restore_app_env(:capcut_path, previous_env)
      restore_env("LOCALAPPDATA", previous_localappdata)
    end)

    Application.delete_env(:capcut_mcp, :capcut_path)
    System.delete_env("LOCALAPPDATA")

    :ok
  end

  describe "discover/0" do
    test "prefers :capcut_path application env over LOCALAPPDATA" do
      Application.put_env(:capcut_mcp, :capcut_path, "C:/explicit/projects")
      System.put_env("LOCALAPPDATA", "C:/should/not/matter")

      assert {:ok, "C:/explicit/projects"} = PathDiscovery.discover()
    end

    @tag :tmp_dir
    test "falls back to %LOCALAPPDATA%\\CapCut\\User Data\\Projects\\com.lveditor.draft",
         %{tmp_dir: tmp} do
      projects =
        Path.join([tmp, "CapCut", "User Data", "Projects", "com.lveditor.draft"])

      File.mkdir_p!(projects)
      System.put_env("LOCALAPPDATA", tmp)

      assert {:ok, discovered} = PathDiscovery.discover()
      assert Path.expand(discovered) == Path.expand(projects)
    end

    @tag :tmp_dir
    test "returns error when LOCALAPPDATA is set but CapCut is not installed",
         %{tmp_dir: tmp} do
      System.put_env("LOCALAPPDATA", tmp)

      assert {:error, message} = PathDiscovery.discover()
      assert message =~ "Could not locate the CapCut projects folder"
      assert message =~ "com.lveditor.draft"
      assert message =~ "CAPCUT_PATH"
    end

    test "returns error when neither env nor LOCALAPPDATA are set" do
      assert {:error, message} = PathDiscovery.discover()
      assert message =~ "LOCALAPPDATA not set"
    end

    test "ignores empty :capcut_path and empty LOCALAPPDATA" do
      Application.put_env(:capcut_mcp, :capcut_path, "")
      System.put_env("LOCALAPPDATA", "")

      assert {:error, _} = PathDiscovery.discover()
    end
  end

  describe "localappdata_candidate/0" do
    test "returns nil when LOCALAPPDATA is not set" do
      assert PathDiscovery.localappdata_candidate() == nil
    end

    test "returns the fully-expanded candidate path when LOCALAPPDATA is set" do
      System.put_env("LOCALAPPDATA", "C:/Users/me/AppData/Local")

      assert PathDiscovery.localappdata_candidate() ==
               "C:/Users/me/AppData/Local/CapCut/User Data/Projects/com.lveditor.draft"
    end
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:capcut_mcp, key)
  defp restore_app_env(key, value), do: Application.put_env(:capcut_mcp, key, value)

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
