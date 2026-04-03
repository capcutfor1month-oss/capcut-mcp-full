defmodule CapcutMcp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      case Application.get_env(:capcut_mcp, :start_mcp_server, true) do
        false -> []
        _ ->
          [
            CapcutMcp.CapCut.ProjectStore,
            CapcutMcp.MCP.Server
          ]
      end

    opts = [strategy: :one_for_one, name: CapcutMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
