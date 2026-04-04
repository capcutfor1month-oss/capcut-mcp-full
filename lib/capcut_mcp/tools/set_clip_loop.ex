defmodule CapcutMcp.Tools.SetClipLoop do
  @moduledoc "MCP tool: enable or disable looping on a clip/segment."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.TimelineHelper

  @impl true
  def definition do
    %{
      "name" => "set_clip_loop",
      "description" =>
        "Enables or disables looping on a clip/segment. When enabled, the clip repeats for its full timeline duration.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "clip_id" => %{"type" => "string", "description" => "The segment ID (from get_timeline)"},
          "loop" => %{"type" => "boolean", "description" => "true to enable loop, false to disable"}
        },
        "required" => ["project_id", "clip_id", "loop"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id, "clip_id" => clip_id, "loop" => loop}) when is_boolean(loop) do
    with {:ok, draft} <- ProjectStore.get_project(id),
         {:ok, updated_draft} <-
           TimelineHelper.update_segment(draft, clip_id, &Map.put(&1, "is_loop", loop)),
         :ok <- ProjectStore.update_project(id, updated_draft) do
      {:ok, "Loop #{if loop, do: "enabled", else: "disabled"} on segment #{clip_id}."}
    else
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def execute(%{"loop" => loop}), do: {:error, "Invalid loop value: #{inspect(loop)} (must be boolean)"}
end
