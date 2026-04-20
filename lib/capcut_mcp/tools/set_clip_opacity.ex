defmodule CapcutMcp.Tools.SetClipOpacity do
  @moduledoc "MCP tool: set the opacity/alpha of a clip."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.Tools.{SegmentMutation, ToolArgs}

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
          "clip_id" => %{
            "type" => "string",
            "description" => "The segment ID (from get_timeline)"
          },
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
    with {:ok, alpha} <- validate_opacity(opacity) do
      SegmentMutation.run(id, clip_id, &put_in(&1, ["clip", "alpha"], alpha),
        success: "Opacity set to #{opacity} on segment #{clip_id}.",
        require_clip: true,
        clip_error:
          "Cannot set opacity: segment has no clip object (audio segments are not supported)"
      )
    end
  end

  def execute(args),
    do: {:error, ToolArgs.missing_required_message(args, ["project_id", "clip_id", "opacity"])}

  defp validate_opacity(v) when is_number(v) and v >= 0.0 and v <= 1.0,
    do: {:ok, ToolArgs.to_float(v)}

  defp validate_opacity(v), do: {:error, "Invalid opacity: #{inspect(v)} (must be 0.0 to 1.0)"}
end
