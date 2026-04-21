defmodule CapcutMcp.Tools.ListProjects do
  @moduledoc "MCP tool: list all CapCut draft projects."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore

  @impl true
  def definition do
    %{
      "name" => "list_projects",
      "description" =>
        "Lists all CapCut draft projects with name, ID, duration, and last modified time.",
      "inputSchema" => %{"type" => "object", "properties" => %{}, "required" => []}
    }
  end

  @impl true
  def execute(_args) do
    case ProjectStore.list_projects() do
      {:ok, []} ->
        {:ok, "No CapCut projects found."}

      {:ok, projects} ->
        text =
          Enum.map_join(projects, "\n\n", fn p ->
            "• #{p.name}\n  ID: #{p.id}\n  Duration: #{p.duration_ms}ms\n  Modified: #{format_ts(p.modified_at)}"
          end)

        {:ok, text}

      {:error, reason} ->
        {:error, "Failed to list projects: #{inspect(reason)}"}
    end
  end

  defp format_ts(nil), do: "unknown"

  defp format_ts(us) when is_integer(us) do
    case us |> div(1_000_000) |> DateTime.from_unix() do
      {:ok, dt} -> DateTime.to_string(dt)
      {:error, _} -> "unknown"
    end
  end

  defp format_ts(_), do: "unknown"
end
