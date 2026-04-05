defmodule CapcutMcp.Tools.SetClipVolume do
  @moduledoc "MCP tool: set the volume of a clip/segment."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.{TimelineHelper, ToolArgs}

  @impl true
  def definition do
    %{
      "name" => "set_clip_volume",
      "description" =>
        "Sets the volume of a clip/segment. Works for both video and audio segments. Values above 1.0 boost the volume.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "clip_id" => %{"type" => "string", "description" => "The segment ID (from get_timeline)"},
          "volume" => %{
            "type" => "number",
            "description" => "Volume level (0.0 = mute, 1.0 = normal, >1.0 = boost)"
          }
        },
        "required" => ["project_id", "clip_id", "volume"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id, "clip_id" => clip_id, "volume" => volume}) do
    with {:ok, _} <- validate_volume(volume),
         {:ok, draft} <- ProjectStore.get_project(id),
         {:ok, updated_draft} <-
           TimelineHelper.update_segment(draft, clip_id, &Map.put(&1, "volume", volume / 1)),
         :ok <- ProjectStore.update_project(id, updated_draft) do
      {:ok, "Volume set to #{volume} on segment #{clip_id}."}
    end
    |> ToolArgs.format_tool_result(id)
  end

  def execute(args),
    do: {:error, ToolArgs.missing_required_message(args, ["project_id", "clip_id", "volume"])}

  defp validate_volume(v) when is_number(v) and v >= 0.0, do: {:ok, v}
  defp validate_volume(v), do: {:error, "Invalid volume: #{inspect(v)} (must be >= 0.0)"}
end
