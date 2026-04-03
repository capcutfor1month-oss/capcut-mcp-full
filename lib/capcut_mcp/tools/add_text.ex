defmodule CapcutMcp.Tools.AddText do
  @moduledoc "MCP tool: add a text overlay to a CapCut project timeline."
  alias CapcutMcp.CapCut.ProjectStore

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
          "track_index" => %{"type" => "integer", "description" => "Track index (default: auto-select text track)"}
        },
        "required" => ["project_id", "content", "start_ms", "duration_ms"]
      }
    }
  end

  def execute(%{"project_id" => id, "content" => content, "start_ms" => start_ms, "duration_ms" => duration_ms} = args) do
    case ProjectStore.get_project(id) do
      {:ok, draft} ->
        text_id = generate_uuid()
        segment_id = generate_uuid()
        start_us = start_ms * 1000
        duration_us = duration_ms * 1000

        text_material = %{
          "id" => text_id,
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

        segment = %{
          "id" => segment_id,
          "material_id" => text_id,
          "target_timerange" => %{"start" => start_us, "duration" => duration_us},
          "source_timerange" => %{"start" => 0, "duration" => duration_us},
          "extra_material_refs" => [],
          "render_index" => 0
        }

        tracks = draft["tracks"] || []
        {updated_tracks, track_idx} = insert_segment(tracks, segment, "text", Map.get(args, "track_index"))
        materials = draft["materials"] || %{}
        updated_materials = Map.update(materials, "texts", [text_material], fn t -> t ++ [text_material] end)
        updated_draft = draft |> Map.put("tracks", updated_tracks) |> Map.put("materials", updated_materials)

        case ProjectStore.update_project(id, updated_draft) do
          :ok ->
            {:ok, "Text added.\nSegment ID: #{segment_id}\nTrack index: #{track_idx}\nContent: \"#{content}\"\nTime: #{start_ms}ms → #{start_ms + duration_ms}ms"}
          error -> {:error, inspect(error)}
        end
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp insert_segment(tracks, segment, type, nil) do
    case Enum.find_index(tracks, fn t -> t["type"] == type end) do
      nil ->
        new_track = %{"id" => generate_uuid(), "type" => type, "segments" => [segment], "attribute" => 0, "flag" => 0}
        {tracks ++ [new_track], length(tracks)}
      idx ->
        updated = Map.update!(Enum.at(tracks, idx), "segments", fn s -> s ++ [segment] end)
        {List.replace_at(tracks, idx, updated), idx}
    end
  end

  defp insert_segment(tracks, segment, _type, idx) when is_integer(idx) and idx < length(tracks) do
    updated = Map.update!(Enum.at(tracks, idx), "segments", fn s -> s ++ [segment] end)
    {List.replace_at(tracks, idx, updated), idx}
  end

  defp insert_segment(tracks, segment, type, _idx), do: insert_segment(tracks, segment, type, nil)

  defp generate_uuid do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)
    s = <<a::48, 4::4, b::12, 2::2, c::62>> |> Base.encode16(case: :upper)
    "#{String.slice(s, 0, 8)}-#{String.slice(s, 8, 4)}-#{String.slice(s, 12, 4)}-#{String.slice(s, 16, 4)}-#{String.slice(s, 20, 12)}"
  end
end
