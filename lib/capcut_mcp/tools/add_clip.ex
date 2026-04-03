defmodule CapcutMcp.Tools.AddClip do
  @moduledoc "MCP tool: add a video or audio clip to a CapCut project timeline."
  alias CapcutMcp.CapCut.ProjectStore

  @video_exts ~w(.mp4 .mov .avi .mkv .webm .m4v .wmv)
  @audio_exts ~w(.mp3 .wav .aac .flac .ogg .m4a)

  def definition do
    %{
      "name" => "add_clip",
      "description" => "Adds a video or audio file as a clip to a CapCut project timeline.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "file_path" => %{"type" => "string", "description" => "Absolute path to the video or audio file"},
          "start_ms" => %{"type" => "integer", "description" => "Start time on timeline in ms (default: 0)"},
          "duration_ms" => %{"type" => "integer", "description" => "Duration in ms (default: 5000)"},
          "track_index" => %{"type" => "integer", "description" => "Track index (default: auto)"}
        },
        "required" => ["project_id", "file_path"]
      }
    }
  end

  def execute(%{"project_id" => id, "file_path" => file_path} = args) do
    case ProjectStore.get_project(id) do
      {:ok, draft} ->
        start_ms = Map.get(args, "start_ms", 0)
        duration_ms = Map.get(args, "duration_ms", 5000)
        start_us = start_ms * 1000
        duration_us = duration_ms * 1000
        track_type = detect_type(file_path)
        material_id = generate_uuid()
        segment_id = generate_uuid()

        material = %{
          "id" => material_id,
          "type" => track_type,
          "path" => Path.expand(file_path),
          "duration" => duration_us,
          "item_source" => 1,
          "md5" => "",
          "metetype" => track_type
        }

        segment = %{
          "id" => segment_id,
          "material_id" => material_id,
          "target_timerange" => %{"start" => start_us, "duration" => duration_us},
          "source_timerange" => %{"start" => 0, "duration" => duration_us},
          "extra_material_refs" => [],
          "render_index" => 0,
          "clip" => %{
            "alpha" => 1.0,
            "flip" => %{"horizontal" => false, "vertical" => false},
            "rotation" => 0.0,
            "scale" => %{"x" => 1.0, "y" => 1.0},
            "transform" => %{"x" => 0.0, "y" => 0.0}
          }
        }

        tracks = draft["tracks"] || []
        {updated_tracks, track_idx} = insert_segment(tracks, segment, track_type, Map.get(args, "track_index"))
        material_key = if track_type == "video", do: "videos", else: "audios"
        materials = draft["materials"] || %{}
        updated_materials = Map.update(materials, material_key, [material], fn m -> m ++ [material] end)
        updated_draft = draft |> Map.put("tracks", updated_tracks) |> Map.put("materials", updated_materials)

        case ProjectStore.update_project(id, updated_draft) do
          :ok ->
            {:ok, "Clip added.\nSegment ID: #{segment_id}\nMaterial ID: #{material_id}\nType: #{track_type}\nTrack index: #{track_idx}\nTime: #{start_ms}ms → #{start_ms + duration_ms}ms"}
          error -> {:error, inspect(error)}
        end
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp detect_type(path) do
    ext = path |> Path.extname() |> String.downcase()
    cond do
      ext in @video_exts -> "video"
      ext in @audio_exts -> "audio"
      true -> "video"
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
