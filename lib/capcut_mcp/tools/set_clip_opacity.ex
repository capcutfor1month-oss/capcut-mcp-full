defmodule CapcutMcp.Tools.SetClipOpacity do
  @moduledoc "MCP tool: set the opacity/alpha of a clip."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.TimelineHelper

  @impl true
  def definition do
    %{
      "name" => "set_clip_opacity",
      "description" =>
        "Sets the opacity (alpha) of a video clip. Does not work on audio segments.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "clip_id" => %{"type" => "string", "description" => "The segment ID (from get_timeline)"},
          "opacity" => %{
            "type" => "number",
            "description" => "Opacity value (0.0 = invisible, 1.0 = fully opaque)"
          }
        },
        "required" => ["project_id", "clip_id", "opacity"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id, "clip_id" => clip_id, "opacity" => opacity}) do
    with {:ok, _} <- validate_opacity(opacity),
         {:ok, draft} <- ProjectStore.get_project(id),
         {:ok, {_t, _s, seg}} <- TimelineHelper.find_segment(draft, clip_id),
         :ok <- require_clip(seg),
         {:ok, updated_draft} <-
           TimelineHelper.update_segment(draft, clip_id, fn seg ->
             put_in(seg, ["clip", "alpha"], opacity / 1)
           end),
         :ok <- ProjectStore.update_project(id, updated_draft) do
      {:ok, "Opacity set to #{opacity} on segment #{clip_id}."}
    else
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp require_clip(%{"clip" => clip}) when is_map(clip), do: :ok
  defp require_clip(_), do: {:error, "Cannot set opacity: segment has no clip object (audio segments are not supported)"}

  defp validate_opacity(v) when is_number(v) and v >= 0.0 and v <= 1.0, do: {:ok, v}
  defp validate_opacity(v), do: {:error, "Invalid opacity: #{inspect(v)} (must be 0.0 to 1.0)"}
end
