defmodule CapcutMcp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CapcutMcp.CapCut.ProjectStore,
      CapcutMcp.MCP.Server
    ]
    opts = [strategy: :one_for_one, name: CapcutMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
