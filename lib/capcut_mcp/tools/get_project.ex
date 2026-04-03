defmodule CapcutMcp.Tools.GetProject do
  @moduledoc "MCP tool: get CapCut project info."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore

  @impl true
  def definition do
    %{
      "name" => "get_project",
      "description" =>
        "Returns canvas config, FPS, version, duration, and track count for a CapCut project.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"}
        },
        "required" => ["project_id"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id}) do
    with {:ok, draft} <- ProjectStore.get_project(id) do
      canvas = draft["canvas_config"] || %{}

      text =
        [
          "Name: #{draft["name"] || "(unnamed)"}",
          "ID: #{draft["id"]}",
          "Canvas: #{canvas["width"]}x#{canvas["height"]} (#{canvas["ratio"]})",
          "FPS: #{draft["fps"]}",
          "Duration: #{draft["duration"]}us",
          "Version: #{draft["new_version"]}",
          "Tracks: #{length(draft["tracks"] || [])}"
        ]
        |> Enum.join("\n")

      {:ok, text}
    else
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
