defmodule CapcutMcp.Tools.AddText do
  @moduledoc "MCP tool: add a text overlay to a CapCut project timeline."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.{TimelineHelper, ToolArgs}

  @impl true
  def definition do
    %{
      "name" => "add_text",
      "description" => "Adds a text overlay element to a CapCut project timeline.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "content" => %{"type" => "string", "description" => "The text to display"},
          "start_ms" => %{"type" => "integer", "description" => "Start time in milliseconds"},
          "duration_ms" => %{"type" => "integer", "description" => "Duration in milliseconds"},
          "track_index" => %{
            "type" => "integer",
            "description" => "Track index (default: auto-select text track)"
          }
        },
        "required" => ["project_id", "content", "start_ms", "duration_ms"]
      }
    }
  end

  @impl true
  def execute(
        %{
          "project_id" => id,
          "content" => content,
          "start_ms" => start_ms,
          "duration_ms" => duration_ms
        } = args
      ) do
    track_index = Map.get(args, "track_index")

    with {:ok, draft} <- ProjectStore.get_project(id),
         {:ok, {updated_draft, segment_id, track_idx}} <-
           apply_text_to_draft(draft, content, start_ms, duration_ms, track_index),
         :ok <- ProjectStore.update_project(id, updated_draft) do
      {:ok,
       "Text added.\nSegment ID: #{segment_id}\nTrack index: #{track_idx}\nContent: \"#{content}\"\nTime: #{start_ms}ms → #{start_ms + duration_ms}ms"}
    end
    |> ToolArgs.format_tool_result(id)
  end

  defp apply_text_to_draft(draft, content, start_ms, duration_ms, track_index) do
    text_id = TimelineHelper.generate_uuid()
    segment_id = TimelineHelper.generate_uuid()
    tracks = draft["tracks"] || []

    with {:ok, validated_content} <- validate_content(content),
         {:ok, {validated_start_ms, validated_duration_ms}} <-
           TimelineHelper.validate_timing(start_ms, duration_ms),
         {:ok, validated_track_index} <- TimelineHelper.validate_track_index(tracks, track_index) do
      text_material = build_text_material(text_id, validated_content)
      segment = build_segment(segment_id, text_id, validated_start_ms, validated_duration_ms)

      {updated_tracks, track_idx} =
        TimelineHelper.insert_segment(tracks, segment, "text", validated_track_index)

      updated_draft =
        draft
        |> Map.put("tracks", updated_tracks)
        |> TimelineHelper.add_material("texts", text_material)

      {:ok, {updated_draft, segment_id, track_idx}}
    end
  end

  defp build_text_material(id, content) do
    %{
      "id" => id,
      "type" => "text",
      "content" => content,
      "text_size" => 30,
      "font_color" => "rgba(1,1,1,1)",
      "bold" => false,
      "italic" => false,
      "underline" => false,
      "alignment" => "center",
      "text_to_audio_ids" => [],
      "words" => %{"words" => []}
    }
  end

  defp build_segment(id, material_id, start_ms, duration_ms) do
    start_us = start_ms * 1000
    duration_us = duration_ms * 1000

    %{
      "id" => id,
      "material_id" => material_id,
      "target_timerange" => %{"start" => start_us, "duration" => duration_us},
      "source_timerange" => %{"start" => 0, "duration" => duration_us},
      "extra_material_refs" => [],
      "render_index" => 0
    }
  end

  defp validate_content(content) when is_binary(content) do
    if String.trim(content) != "" do
      {:ok, content}
    else
      {:error, "Invalid content: #{inspect(content)}"}
    end
  end

  defp validate_content(content), do: {:error, "Invalid content: #{inspect(content)}"}
end
