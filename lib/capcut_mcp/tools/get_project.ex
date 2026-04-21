defmodule CapcutMcp.Tools.GetProject do
  @moduledoc "MCP tool: get CapCut project info."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.ToolArgs

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
    # Name and ID come from root_meta_info.json (the manifest). `draft_content.json`
    # has its own internal `"id"` and `"name"` that may diverge for CapCut-native
    # projects — only the manifest's values are the stable address a caller can
    # use to look the project up again.
    with {:ok, %{meta: meta, draft: draft}} <- ProjectStore.get_project_with_meta(id) do
      canvas = draft["canvas_config"] || %{}

      text =
        Enum.join(
          [
            "Name: #{meta.name}",
            "ID: #{meta.id}",
            "Canvas: #{canvas["width"]}x#{canvas["height"]} (#{canvas["ratio"]})",
            "FPS: #{draft["fps"]}",
            "Duration: #{draft["duration"]}us",
            "Version: #{draft["new_version"]}",
            "Tracks: #{length(draft["tracks"] || [])}"
          ],
          "\n"
        )

      {:ok, text}
    end
    |> ToolArgs.format_tool_result(id)
  end
end
