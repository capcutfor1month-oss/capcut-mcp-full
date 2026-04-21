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
    with {:ok, coerced} <- coerce_numeric_fields(args) do
      SegmentMutation.run(id, clip_id, &apply_transform(&1, coerced),
        success: "Transform updated on segment #{clip_id}.",
        require_clip: true,
        clip_error:
          "Cannot set transform: segment has no clip object (audio segments are not supported)"
      )
    end
  end

  def execute(args),
    do: {:error, ToolArgs.missing_required_message(args, ["project_id", "clip_id"])}

  # Validates numeric inputs at the request boundary. Non-number values
  # (e.g. stringified "0.5" from a sloppy client) short-circuit to
  # `{:error, msg}` instead of raising inside `ToolArgs.to_float/1`.
  defp coerce_numeric_fields(args) do
    Enum.reduce_while(~w(x y scale_x scale_y rotation), {:ok, %{}}, &coerce_field(args, &1, &2))
  end

  defp coerce_field(args, key, {:ok, acc}) do
    case Map.get(args, key) do
      nil -> {:cont, {:ok, acc}}
      value -> coerce_value(key, value, acc)
    end
  end

  defp coerce_value(key, value, acc) do
    case ToolArgs.to_float_safe(value) do
      {:ok, float} -> {:cont, {:ok, Map.put(acc, key, float)}}
      {:error, msg} -> {:halt, {:error, "#{key}: #{msg}"}}
    end
  end

  defp apply_transform(seg, coerced) do
    clip =
      seg["clip"]
      |> maybe_update_nested("transform", "x", Map.get(coerced, "x"))
      |> maybe_update_nested("transform", "y", Map.get(coerced, "y"))
      |> maybe_update_nested("scale", "x", Map.get(coerced, "scale_x"))
      |> maybe_update_nested("scale", "y", Map.get(coerced, "scale_y"))
      |> maybe_update("rotation", Map.get(coerced, "rotation"))

    Map.put(seg, "clip", clip)
  end

  defp maybe_update(map, _key, nil), do: map
  defp maybe_update(map, key, value), do: Map.put(map, key, value)

  defp maybe_update_nested(map, _group, _key, nil), do: map

  defp maybe_update_nested(map, group, key, value) do
    nested = Map.get(map, group, %{})
    Map.put(map, group, Map.put(nested, key, value))
  end
end
