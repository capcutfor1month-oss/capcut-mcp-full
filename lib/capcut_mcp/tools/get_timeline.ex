defmodule CapcutMcp.Tools.GetTimeline do
  @moduledoc "MCP tool: get CapCut project timeline."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore

  @impl true
  def definition do
    %{
      "name" => "get_timeline",
      "description" =>
        "Returns all tracks with their segments, timecodes, and material IDs for a CapCut project.",
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
      tracks = draft["tracks"] || []

      if Enum.empty?(tracks) do
        {:ok, "Timeline is empty (no tracks)."}
      else
        text =
          tracks
          |> Enum.with_index(1)
          |> Enum.map(&format_track/1)
          |> Enum.join("\n\n")

        {:ok, text}
      end
    else
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp format_track({track, index}) do
    segments = track["segments"] || []

    formatted_segments =
      segments
      |> Enum.map(&format_segment/1)
      |> Enum.join("\n")

    "Track #{index} [#{track["type"]}] id=#{track["id"]} — #{length(segments)} segment(s):\n#{formatted_segments}"
  end

  defp format_segment(segment) do
    timerange = segment["target_timerange"] || %{}
    start_ms = div(timerange["start"] || 0, 1000)
    duration_ms = div(timerange["duration"] || 0, 1000)

    "    - #{segment["id"]} @ #{start_ms}ms for #{duration_ms}ms (material: #{segment["material_id"]})"
  end
end
