defmodule CapcutMcp.Application do
  @moduledoc false
  use Application

  alias CapcutMcp.CapCut.{BlendModes, ProjectStore}
  alias CapcutMcp.MCP.{Server, StdinReader}
  alias CapcutMcp.Telemetry

  @impl true
  def start(_type, _args) do
    BlendModes.init_table()
    Telemetry.attach_default_logger()

    children =
      maybe_child(:start_project_store, ProjectStore) ++
        maybe_mcp_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: CapcutMcp.Supervisor)
  end

  defp maybe_child(flag, child) do
    if Application.get_env(:capcut_mcp, flag, true), do: [child], else: []
  end

  # Server + StdinReader share fate: if the server crashes the reader's target is gone,
  # so restart both together via a dedicated `rest_for_one` sub-supervisor.
  defp maybe_mcp_children do
    if Application.get_env(:capcut_mcp, :start_mcp_server, true) do
      [
        %{
          id: CapcutMcp.MCP.Supervisor,
          start:
            {Supervisor, :start_link,
             [
               [Server, StdinReader],
               [strategy: :rest_for_one, name: CapcutMcp.MCP.Supervisor]
             ]},
          type: :supervisor
        }
      ]
    else
      []
    end
  end
end
