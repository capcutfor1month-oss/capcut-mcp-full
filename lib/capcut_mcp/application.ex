defmodule CapcutMcp.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = store_children() ++ mcp_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: CapcutMcp.Supervisor)
  end

  defp store_children do
    if Application.get_env(:capcut_mcp, :start_project_store, true),
      do: [CapcutMcp.CapCut.ProjectStore],
      else: []
  end

  defp mcp_children do
    if Application.get_env(:capcut_mcp, :start_mcp_server, true),
      do: [CapcutMcp.MCP.Server],
      else: []
  end
end
