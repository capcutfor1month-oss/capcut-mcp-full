defmodule CapcutMcp.Tools.AddClip do
  @moduledoc "MCP tool: add a video or audio clip to a CapCut project timeline."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.TimelineHelper

  @video_exts ~w(.mp4 .mov .avi .mkv .webm .m4v .wmv)
  @audio_exts ~w(.mp3 .wav .aac .flac .ogg .m4a)

  @impl true
  def definition do
    %{
      "name" => "add_clip",
      "description" => "Adds a video or audio file as a clip to a CapCut project timeline.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "file_path" => %{
            "type" => "string",
            "description" => "Absolute path to the video or audio file"
          },
          "start_ms" => %{
            "type" => "integer",
            "description" => "Start time on timeline in ms (default: 0)"
          },
          "duration_ms" => %{
            "type" => "integer",
            "description" => "Duration in ms (default: 5000)"
          },
          "track_index" => %{"type" => "integer", "description" => "Track index (default: auto)"}
        },
        "required" => ["project_id", "file_path"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id, "file_path" => file_path} = args) do
    start_ms = Map.get(args, "start_ms", 0)
    duration_ms = Map.get(args, "duration_ms", 5000)
    track_index = Map.get(args, "track_index")

    with {:ok, draft} <- ProjectStore.get_project(id),
         {:ok, {updated_draft, track_type, material_id, segment_id, track_idx}} <-
           apply_clip_to_draft(draft, file_path, start_ms, duration_ms, track_index),
         :ok <- ProjectStore.update_project(id, updated_draft) do
      {:ok,
       "Clip added.\nSegment ID: #{segment_id}\nMaterial ID: #{material_id}\nType: #{track_type}\nTrack index: #{track_idx}\nTime: #{start_ms}ms → #{start_ms + duration_ms}ms"}
    else
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp apply_clip_to_draft(draft, file_path, start_ms, duration_ms, track_index) do
    material_id = TimelineHelper.generate_uuid()
    segment_id = TimelineHelper.generate_uuid()
    tracks = draft["tracks"] || []

    with {:ok, validated_file_path} <- validate_file_path(file_path),
         {:ok, {validated_start_ms, validated_duration_ms}} <-
           TimelineHelper.validate_timing(start_ms, duration_ms),
         {:ok, validated_track_index} <- TimelineHelper.validate_track_index(tracks, track_index) do
      track_type = detect_type(validated_file_path)

      material =
        build_material(material_id, track_type, validated_file_path, validated_duration_ms)

      segment = build_segment(segment_id, material_id, validated_start_ms, validated_duration_ms)

      {updated_tracks, track_idx} =
        TimelineHelper.insert_segment(tracks, segment, track_type, validated_track_index)

      material_key = if track_type == "video", do: "videos", else: "audios"

      updated_draft =
        draft
        |> Map.put("tracks", updated_tracks)
        |> TimelineHelper.add_material(material_key, material)

      {:ok, {updated_draft, track_type, material_id, segment_id, track_idx}}
    end
  end

  defp build_material(id, track_type, file_path, duration_ms) do
    %{
      "id" => id,
      "type" => track_type,
      "path" => Path.expand(file_path),
      "duration" => duration_ms * 1000,
      "item_source" => 1,
      "md5" => "",
      "metetype" => track_type
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
      "render_index" => 0,
      "clip" => %{
        "alpha" => 1.0,
        "flip" => %{"horizontal" => false, "vertical" => false},
        "rotation" => 0.0,
        "scale" => %{"x" => 1.0, "y" => 1.0},
        "transform" => %{"x" => 0.0, "y" => 0.0}
      }
    }
  end

  defp validate_file_path(path) when is_binary(path) do
    if String.trim(path) != "" and Path.type(path) == :absolute do
      {:ok, path}
    else
      {:error, "Invalid file_path: #{inspect(path)}"}
    end
  end

  defp validate_file_path(path), do: {:error, "Invalid file_path: #{inspect(path)}"}

  defp detect_type(path) do
    ext = path |> Path.extname() |> String.downcase()

    cond do
      ext in @video_exts -> "video"
      ext in @audio_exts -> "audio"
      true -> "video"
    end
  end
end
