defmodule CapcutMcp.Tools.GetTimeline do
  @moduledoc "MCP tool: get CapCut project timeline."
  alias CapcutMcp.CapCut.ProjectStore

  def definition do
    %{
      "name" => "get_timeline",
      "description" => "Returns all tracks with their segments, timecodes, and material IDs for a CapCut project.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"}
        },
        "required" => ["project_id"]
      }
    }
  end

  def execute(%{"project_id" => id}) do
    case ProjectStore.get_project(id) do
      {:ok, draft} ->
        tracks = draft["tracks"] || []
        if Enum.empty?(tracks) do
          {:ok, "Timeline is empty (no tracks)."}
        else
          text =
            tracks
            |> Enum.with_index(1)
            |> Enum.map(fn {track, i} ->
              segments = track["segments"] || []
              segs =
                segments
                |> Enum.map(fn s ->
                  tr = s["target_timerange"] || %{}
                  start_ms = div(tr["start"] || 0, 1000)
                  dur_ms = div(tr["duration"] || 0, 1000)
                  "    - #{s["id"]} @ #{start_ms}ms for #{dur_ms}ms (material: #{s["material_id"]})"
                end)
                |> Enum.join("\n")
              "Track #{i} [#{track["type"]}] id=#{track["id"]} — #{length(segments)} segment(s):\n#{segs}"
            end)
            |> Enum.join("\n\n")
          {:ok, text}
        end
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
