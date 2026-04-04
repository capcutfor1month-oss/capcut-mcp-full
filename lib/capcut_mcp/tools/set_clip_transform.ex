defmodule CapcutMcp.Tools.SetClipTransform do
  @moduledoc "MCP tool: set position, scale, and rotation of a clip."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.TimelineHelper

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
          "clip_id" => %{"type" => "string", "description" => "The segment ID (from get_timeline)"},
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
    with {:ok, draft} <- ProjectStore.get_project(id),
         {:ok, {_t, _s, seg}} <- TimelineHelper.find_segment(draft, clip_id),
         :ok <- require_clip(seg),
         {:ok, updated_draft} <-
           TimelineHelper.update_segment(draft, clip_id, &apply_transform(&1, args)),
         :ok <- ProjectStore.update_project(id, updated_draft) do
      {:ok, "Transform updated on segment #{clip_id}."}
    else
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp require_clip(%{"clip" => clip}) when is_map(clip), do: :ok
  defp require_clip(_), do: {:error, "Cannot set transform: segment has no clip object (audio segments are not supported)"}

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
  defp maybe_update(map, key, value), do: Map.put(map, key, value / 1)

  defp maybe_update_nested(map, _group, _key, nil), do: map

  defp maybe_update_nested(map, group, key, value) do
    nested = Map.get(map, group, %{})
    Map.put(map, group, Map.put(nested, key, value / 1))
  end
end
