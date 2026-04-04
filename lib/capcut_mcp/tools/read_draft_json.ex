defmodule CapcutMcp.Tools.ReadDraftJson do
  @moduledoc "MCP tool: return the full raw draft JSON for debugging."
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.ProjectStore

  @impl true
  def definition do
    %{
      "name" => "read_draft_json",
      "description" =>
        "Returns the full raw draft_content.json for a CapCut project. Useful for inspecting the internal structure, debugging, and discovering clip IDs.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"}
        },
        "required" => ["project_id"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id}) do
    case ProjectStore.get_project(id) do
      {:ok, draft} -> {:ok, Jason.encode!(draft, pretty: true)}
      {:error, :not_found} -> {:error, "Project not found: #{id}"}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end
end
