defmodule CapcutMcp.CapCut.Reader do
  @moduledoc "Reads CapCut project metadata and draft content from the local filesystem."

  alias CapcutMcp.CapCut.Types.ProjectMeta

  @doc "Reads all project metadata from root_meta_info.json"
  @spec list_projects(String.t()) :: {:ok, [ProjectMeta.t()]} | {:error, term()}
  def list_projects(root_path) do
    meta_file = Path.join(root_path, "root_meta_info.json")

    with {:ok, content} <- File.read(meta_file),
         {:ok, data} <- Jason.decode(content) do
      projects =
        data
        |> Map.get("all_draft_store", [])
        |> Enum.filter(fn d -> d["draft_id"] && d["draft_name"] && d["draft_fold_path"] end)
        |> Enum.map(fn draft ->
          %ProjectMeta{
            id: draft["draft_id"],
            name: draft["draft_name"],
            path: draft["draft_fold_path"],
            modified_at: draft["tm_draft_modified"],
            duration_ms: (draft["tm_duration"] || 0) |> trunc() |> div(1000)
          }
        end)

      {:ok, projects}
    end
  end

  @doc "Reads draft_content.json for a given project folder path"
  @spec read_draft(String.t()) :: {:ok, map()} | {:error, term()}
  def read_draft(draft_path) do
    json_file = Path.join(draft_path, "draft_content.json")

    with {:ok, content} <- File.read(json_file),
         {:ok, data} <- Jason.decode(content) do
      {:ok, data}
    end
  end
end
