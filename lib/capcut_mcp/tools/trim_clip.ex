defmodule CapcutMcp.Tools.TrimClip do
  @moduledoc "MCP tool: set source in/out points and optionally adjust timeline duration."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.{TimelineHelper, ToolArgs}

  @impl true
  def definition do
    %{
      "name" => "trim_clip",
      "description" =>
        "Sets the source in/out points of a clip (which portion of the source material is used). Optionally adjusts the timeline duration independently.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "clip_id" => %{"type" => "string", "description" => "The segment ID (from get_timeline)"},
          "source_start_ms" => %{
            "type" => "integer",
            "description" => "In-point in the source material in ms (default: keep current)"
          },
          "source_duration_ms" => %{
            "type" => "integer",
            "description" => "Duration from the source material in ms (default: keep current)"
          },
          "target_duration_ms" => %{
            "type" => "integer",
            "description" =>
              "Duration on the timeline in ms. If omitted and source_duration_ms is set, target matches source."
          }
        },
        "required" => ["project_id", "clip_id"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id, "clip_id" => clip_id} = args) do
    source_start = args["source_start_ms"]
    source_dur = args["source_duration_ms"]
    target_dur = args["target_duration_ms"]

    with :ok <- validate_optional_timing(source_start, "source_start_ms"),
         :ok <- validate_optional_positive(source_dur, "source_duration_ms"),
         :ok <- validate_optional_positive(target_dur, "target_duration_ms"),
         {:ok, draft} <- ProjectStore.get_project(id),
         {:ok, updated_draft} <-
           TimelineHelper.update_segment(draft, clip_id, fn seg ->
             apply_trim(seg, source_start, source_dur, target_dur)
           end),
         :ok <- ProjectStore.update_project(id, updated_draft) do
      {:ok, "Clip #{clip_id} trimmed."}
    else
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def execute(args),
    do: {:error, ToolArgs.missing_required_message(args, ["project_id", "clip_id"])}

  defp apply_trim(seg, source_start, source_dur, target_dur) do
    seg
    |> apply_source(source_start, source_dur)
    |> apply_target(source_dur, target_dur)
  end

  defp apply_source(seg, nil, nil), do: seg

  defp apply_source(seg, source_start, source_dur) do
    sr = seg["source_timerange"] || %{"start" => 0, "duration" => 0}

    sr =
      sr
      |> then(fn sr -> if source_start, do: Map.put(sr, "start", source_start * 1000), else: sr end)
      |> then(fn sr -> if source_dur, do: Map.put(sr, "duration", source_dur * 1000), else: sr end)

    Map.put(seg, "source_timerange", sr)
  end

  defp apply_target(seg, source_dur, nil) when is_integer(source_dur) do
    seg
    |> ensure_target_timerange()
    |> put_in(["target_timerange", "duration"], source_dur * 1000)
  end

  defp apply_target(seg, _source_dur, target_dur) when is_integer(target_dur) do
    seg
    |> ensure_target_timerange()
    |> put_in(["target_timerange", "duration"], target_dur * 1000)
  end

  defp apply_target(seg, _source_dur, _target_dur), do: seg

  defp ensure_target_timerange(seg) do
    TimelineHelper.ensure_timerange(seg, "target_timerange", %{
      "start" => 0,
      "duration" => get_in(seg, ["source_timerange", "duration"]) || 0
    })
  end

  defp validate_optional_timing(nil, _), do: :ok
  defp validate_optional_timing(v, _) when is_integer(v) and v >= 0, do: :ok
  defp validate_optional_timing(v, name), do: {:error, "Invalid #{name}: #{inspect(v)} (must be integer >= 0)"}

  defp validate_optional_positive(nil, _), do: :ok
  defp validate_optional_positive(v, _) when is_integer(v) and v > 0, do: :ok
  defp validate_optional_positive(v, name), do: {:error, "Invalid #{name}: #{inspect(v)} (must be integer > 0)"}
end
