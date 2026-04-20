defmodule CapcutMcp.Tools.SetClipTransform do
  @moduledoc "MCP tool: set position, scale, and rotation of a clip."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.Tools.{SegmentMutation, ToolArgs}

  @impl true
  def definition do
    %{
      "name" => "set_clip_transform",
      "description" =>
        "Sets position, scale, and/or rotation of a video clip. Only provided values are updated; others remain unchanged. Does not work on audio segments.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "clip_id" => %{
            "type" => "string",
            "description" => "The segment ID (from get_timeline)"
          },
          "x" => %{
            "type" => "number",
            "description" => "Horizontal position (-1.0 to +1.0, 0.0 = center)"
          },
          "y" => %{
            "type" => "number",
            "description" => "Vertical position (-1.0 to +1.0, 0.0 = center)"
          },
          "scale_x" => %{
            "type" => "number",
            "description" => "Horizontal scale (1.0 = 100%)"
          },
          "scale_y" => %{
            "type" => "number",
            "description" => "Vertical scale (1.0 = 100%)"
          },
          "rotation" => %{
            "type" => "number",
            "description" => "Rotation in degrees"
          }
        },
        "required" => ["project_id", "clip_id"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id, "clip_id" => clip_id} = args) do
    SegmentMutation.run(id, clip_id, &apply_transform(&1, args),
      success: "Transform updated on segment #{clip_id}.",
      require_clip: true,
      clip_error:
        "Cannot set transform: segment has no clip object (audio segments are not supported)"
    )
  end

  def execute(args),
    do: {:error, ToolArgs.missing_required_message(args, ["project_id", "clip_id"])}

  defp apply_transform(seg, args) do
    clip =
      seg["clip"]
      |> maybe_update_nested("transform", "x", args["x"])
      |> maybe_update_nested("transform", "y", args["y"])
      |> maybe_update_nested("scale", "x", args["scale_x"])
      |> maybe_update_nested("scale", "y", args["scale_y"])
      |> maybe_update("rotation", args["rotation"])

    Map.put(seg, "clip", clip)
  end

  defp maybe_update(map, _key, nil), do: map
  defp maybe_update(map, key, value), do: Map.put(map, key, ToolArgs.to_float(value))

  defp maybe_update_nested(map, _group, _key, nil), do: map

  defp maybe_update_nested(map, group, key, value) do
    nested = Map.get(map, group, %{})
    Map.put(map, group, Map.put(nested, key, ToolArgs.to_float(value)))
  end
end
