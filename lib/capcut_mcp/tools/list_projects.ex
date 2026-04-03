defmodule CapcutMcp.Tools.ListProjects do
  @moduledoc "MCP tool: list all CapCut draft projects."
  alias CapcutMcp.CapCut.ProjectStore

  def definition do
    %{
      "name" => "list_projects",
      "description" => "Lists all CapCut draft projects with name, ID, duration, and last modified time.",
      "inputSchema" => %{"type" => "object", "properties" => %{}, "required" => []}
    }
  end

  def execute(_args) do
    case ProjectStore.list_projects() do
      {:ok, []} ->
        {:ok, "No CapCut projects found."}
      {:ok, projects} ->
        text =
          projects
          |> Enum.map(fn p ->
            modified = format_ts(p.modified_at)
            "• #{p.name}\n  ID: #{p.id}\n  Duration: #{p.duration_ms}ms\n  Modified: #{modified}"
          end)
          |> Enum.join("\n\n")
        {:ok, text}
      {:error, reason} ->
        {:error, "Failed to list projects: #{inspect(reason)}"}
    end
  end

  defp format_ts(nil), do: "unknown"
  defp format_ts(us) when is_integer(us) do
    us |> div(1_000_000) |> DateTime.from_unix!() |> DateTime.to_string()
  end
end
