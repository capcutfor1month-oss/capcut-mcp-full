defmodule CapcutMcp.CapCut.ProjectStoreDiscoveryTest do
  @moduledoc """
  Covers the cold-start path where no `:root_path` is passed and neither
  `CAPCUT_PATH` nor a real `LOCALAPPDATA\\CapCut\\...` folder are available.
  The server must still boot and surface a friendly error from each tool-call
  entry point.
  """

  use ExUnit.Case, async: false

  alias CapcutMcp.CapCut.ProjectStore

  setup do
    previous_env = Application.get_env(:capcut_mcp, :capcut_path)
    previous_localappdata = System.get_env("LOCALAPPDATA")

    Application.delete_env(:capcut_mcp, :capcut_path)
    System.delete_env("LOCALAPPDATA")

    on_exit(fn ->
      restore_app_env(:capcut_path, previous_env)
      restore_env("LOCALAPPDATA", previous_localappdata)
    end)

    :ok
  end

  test "ProjectStore boots even without any configured path" do
    assert {:ok, pid} = start_supervised({ProjectStore, []})
    assert Process.alive?(pid)
  end

  test "list_projects returns a helpful error when path is unavailable" do
    {:ok, _pid} = start_supervised({ProjectStore, []})

    assert {:error, message} = ProjectStore.list_projects()
    assert is_binary(message)
    assert message =~ "CapCut path not configured"
    assert message =~ "CAPCUT_PATH"
  end

  test "get_project surfaces the same friendly error" do
    {:ok, _pid} = start_supervised({ProjectStore, []})

    assert {:error, message} = ProjectStore.get_project("unknown-id")
    assert message =~ "CapCut path not configured"
  end

  test "create_project surfaces the same friendly error" do
    {:ok, _pid} = start_supervised({ProjectStore, []})

    assert {:error, message} = ProjectStore.create_project(%{"name" => "whatever"})
    assert message =~ "CapCut path not configured"
  end

  defp restore_app_env(key, nil), do: Application.delete_env(:capcut_mcp, key)
  defp restore_app_env(key, value), do: Application.put_env(:capcut_mcp, key, value)

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
