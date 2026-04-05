defmodule CapcutMcp.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      for {flag, child} <- [
            {:start_project_store, CapcutMcp.CapCut.ProjectStore},
            {:start_mcp_server, CapcutMcp.MCP.Server}
          ],
          Application.get_env(:capcut_mcp, flag, true) do
        child
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: CapcutMcp.Supervisor)
  end
end
