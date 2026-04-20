defmodule CapcutMcp.Tools.MoveClip do
  @moduledoc "MCP tool: move a clip to a new position on the timeline."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.Tools.{SegmentMutation, TimelineHelper, ToolArgs}

  @impl true
  def definition do
    %{
      "name" => "move_clip",
      "description" =>
        "Moves a clip/segment to a new start position on the timeline. Does not change duration or source.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "clip_id" => %{
            "type" => "string",
            "description" => "The segment ID (from get_timeline)"
          },
          "start_ms" => %{
            "type" => "integer",
            "description" => "New start position on the timeline in milliseconds"
          }
        },
        "required" => ["project_id", "clip_id", "start_ms"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id, "clip_id" => clip_id, "start_ms" => start_ms})
      when is_integer(start_ms) and start_ms >= 0 do
    SegmentMutation.run(id, clip_id, &move_segment(&1, start_ms),
      success: "Clip #{clip_id} moved to #{start_ms}ms."
    )
  end

  def execute(%{"start_ms" => start_ms}),
    do: {:error, "Invalid start_ms: #{inspect(start_ms)} (must be integer >= 0)"}

  def execute(args),
    do: {:error, ToolArgs.missing_required_message(args, ["project_id", "clip_id", "start_ms"])}

  defp move_segment(seg, start_ms) do
    seg
    |> TimelineHelper.ensure_timerange("target_timerange", target_timerange_defaults(seg))
    |> put_in(["target_timerange", "start"], start_ms * 1000)
  end

  defp target_timerange_defaults(seg) do
    %{
      "start" => 0,
      "duration" => get_in(seg, ["source_timerange", "duration"]) || 0
    }
  end
end
