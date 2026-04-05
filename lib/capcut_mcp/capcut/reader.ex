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
        |> Enum.flat_map(fn
          %{"draft_id" => id, "draft_name" => name, "draft_fold_path" => path} = draft ->
            [
              %ProjectMeta{
                id: id,
                name: name,
                path: path,
                modified_at: draft["tm_draft_modified"],
                duration_ms: parse_duration(draft["tm_duration"])
              }
            ]

          _incomplete ->
            []
        end)

      {:ok, projects}
    end
  end

  @doc "Reads draft_content.json for a given project folder path"
  @spec read_draft(String.t()) :: {:ok, map()} | {:error, term()}
  def read_draft(draft_path) do
    json_file = Path.join(draft_path, "draft_content.json")

    with {:ok, content} <- File.read(json_file),
         do: Jason.decode(content)
  end

  defp parse_duration(nil), do: 0
  defp parse_duration(duration) when is_number(duration), do: duration |> trunc() |> div(1000)
  defp parse_duration(_), do: 0
end
