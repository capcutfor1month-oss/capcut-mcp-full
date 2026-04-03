defmodule CapcutMcp.Tools.RemoveClip do
  @moduledoc "MCP tool: remove a clip/segment from a CapCut project timeline."
  alias CapcutMcp.CapCut.ProjectStore

  def definition do
    %{
      "name" => "remove_clip",
      "description" => "Removes a clip/segment from a CapCut project timeline by its segment ID. Get IDs via get_timeline.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "clip_id" => %{"type" => "string", "description" => "The segment ID to remove (from get_timeline)"}
        },
        "required" => ["project_id", "clip_id"]
      }
    }
  end

  def execute(%{"project_id" => id, "clip_id" => clip_id}) do
    case ProjectStore.get_project(id) do
      {:ok, draft} ->
        tracks = draft["tracks"] || []
        {updated_tracks, removed} =
          Enum.map_reduce(tracks, false, fn track, found ->
            segs = track["segments"] || []
            new_segs = Enum.reject(segs, fn s -> s["id"] == clip_id end)
            was_removed = length(new_segs) < length(segs)
            {Map.put(track, "segments", new_segs), found || was_removed}
          end)

        if removed do
          updated_draft = Map.put(draft, "tracks", updated_tracks)
          case ProjectStore.update_project(id, updated_draft) do
            :ok -> {:ok, "Clip #{clip_id} removed successfully."}
            error -> {:error, inspect(error)}
          end
        else
          {:error, "Clip not found: #{clip_id}"}
        end
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
