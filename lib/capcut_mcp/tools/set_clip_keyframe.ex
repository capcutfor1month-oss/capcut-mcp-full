defmodule CapcutMcp.Tools.SetClipKeyframe do
  @moduledoc """
  MCP tool: add a keyframe (an animated value at a point in time) to a clip.

  ## Schema

  Ported from `GuanYixuan/pyCapCut`'s `keyframe.py`. Unlike `set_clip_transform`
  (which sets one static value for the whole segment), keyframes live in the
  segment's own `common_keyframes` array — a list of `{property_type,
  keyframe_list: [{time_offset, values, curveType, ...}]}` groups, one group
  per animated property. Calling this tool twice for the same property adds a
  second point to that property's existing list (sorted by `time_offset`)
  instead of creating a duplicate group — mirrors pyCapCut's
  `VisualSegment.add_keyframe`, which is how you build an actual animation
  curve: call it once per keyframe point.

  `curveType: "Line"` (linear interpolation) is the only mode written —
  pyCapCut's own comment notes CapCut itself only really supports linear via
  its public schema (`"目前只支持线性插值"` — "currently only linear
  interpolation is supported").
  """
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.Tools.{SegmentMutation, TimelineHelper, ToolArgs}

  @properties %{
    "position_x" => "KFTypePositionX",
    "position_y" => "KFTypePositionY",
    "rotation" => "KFTypeRotation",
    "scale_x" => "KFTypeScaleX",
    "scale_y" => "KFTypeScaleY",
    "uniform_scale" => "UNIFORM_SCALE",
    "alpha" => "KFTypeAlpha",
    "saturation" => "KFTypeSaturation",
    "contrast" => "KFTypeContrast",
    "brightness" => "KFTypeBrightness",
    "volume" => "KFTypeVolume"
  }

  @impl true
  def definition do
    %{
      "name" => "set_clip_keyframe",
      "description" =>
        "Adds a keyframe (an animated value at a point in time) to a clip. Call once per " <>
          "keyframe point to build a curve, e.g. alpha=0.0 at 0ms then alpha=1.0 at 500ms " <>
          "for a fade-in. Properties: #{@properties |> Map.keys() |> Enum.sort() |> Enum.join(", ")}.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "clip_id" => %{
            "type" => "string",
            "description" => "The segment ID (from get_timeline)"
          },
          "property" => %{
            "type" => "string",
            "description" =>
              "One of: #{@properties |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"
          },
          "time_offset_ms" => %{
            "type" => "integer",
            "description" =>
              "Time of this keyframe, relative to the clip's own start (not the timeline)"
          },
          "value" => %{
            "type" => "number",
            "description" =>
              "The property's value at time_offset_ms. position_x/position_y are in half-canvas-width/height units (0.0 = center); scale/uniform_scale 1.0 = 100%; alpha 0.0-1.0; rotation in degrees; saturation/contrast/brightness -1.0 to 1.0; volume 1.0 = original."
          }
        },
        "required" => ["project_id", "clip_id", "property", "time_offset_ms", "value"]
      }
    }
  end

  @impl true
  def execute(%{
        "project_id" => id,
        "clip_id" => clip_id,
        "property" => property,
        "time_offset_ms" => time_offset_ms,
        "value" => value
      }) do
    with {:ok, property_type} <- resolve_property(property),
         {:ok, offset_us} <- resolve_offset(time_offset_ms),
         {:ok, float_value} <- ToolArgs.to_float_safe(value) do
      require_clip? = requires_clip?(property)

      SegmentMutation.run(
        id,
        clip_id,
        &apply_keyframe(&1, property_type, offset_us, float_value),
        success:
          "Keyframe added: #{property}=#{float_value} at #{time_offset_ms}ms on segment #{clip_id}.",
        require_clip: require_clip?,
        clip_error:
          "Cannot set #{property} keyframe: segment has no clip object (audio-only property? use volume)"
      )
    end
  end

  def execute(args),
    do:
      {:error,
       ToolArgs.missing_required_message(args, [
         "project_id",
         "clip_id",
         "property",
         "time_offset_ms",
         "value"
       ])}

  defp requires_clip?("volume"), do: false
  defp requires_clip?(_), do: true

  defp resolve_property(property) do
    case Map.fetch(@properties, property) do
      {:ok, kf_type} ->
        {:ok, kf_type}

      :error ->
        {:error,
         "Unknown property #{inspect(property)}. Available: #{@properties |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"}
    end
  end

  defp resolve_offset(ms) when is_integer(ms) and ms >= 0, do: {:ok, ms * 1000}

  defp resolve_offset(ms),
    do: {:error, "time_offset_ms must be a non-negative integer, got #{inspect(ms)}"}

  defp apply_keyframe(segment, property_type, offset_us, value) do
    existing = segment["common_keyframes"] || []
    keyframe = build_keyframe(offset_us, value)

    {updated_list, found?} =
      Enum.map_reduce(existing, false, fn kf_list, found ->
        if kf_list["property_type"] == property_type do
          {insert_sorted(kf_list, keyframe), true}
        else
          {kf_list, found}
        end
      end)

    updated_list =
      if found? do
        updated_list
      else
        updated_list ++ [new_keyframe_list(property_type, keyframe)]
      end

    Map.put(segment, "common_keyframes", updated_list)
  end

  defp build_keyframe(offset_us, value) do
    %{
      "id" => TimelineHelper.generate_uuid(),
      "time_offset" => offset_us,
      "values" => [value],
      "curveType" => "Line",
      "graphID" => "",
      "left_control" => %{"x" => 0.0, "y" => 0.0},
      "right_control" => %{"x" => 0.0, "y" => 0.0}
    }
  end

  defp new_keyframe_list(property_type, keyframe) do
    %{
      "id" => TimelineHelper.generate_uuid(),
      "material_id" => "",
      "property_type" => property_type,
      "keyframe_list" => [keyframe]
    }
  end

  defp insert_sorted(kf_list, keyframe) do
    updated =
      (kf_list["keyframe_list"] || [])
      |> Kernel.++([keyframe])
      |> Enum.sort_by(& &1["time_offset"])

    Map.put(kf_list, "keyframe_list", updated)
  end
end
