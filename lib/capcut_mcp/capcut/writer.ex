defmodule CapcutMcp.CapCut.Writer do
  @moduledoc "Writes CapCut project data to the local filesystem, with backup on overwrite."

  @doc "Writes draft_content.json; backs up existing file to .bak first"
  @spec write_draft(String.t(), map()) :: :ok | {:error, term()}
  def write_draft(draft_path, content) do
    json_file = Path.join(draft_path, "draft_content.json")
    bak_file = Path.join(draft_path, "draft_content.json.bak")

    with {:ok, encoded} <- Jason.encode(content) do
      # Backup existing file — ignore error if it doesn't exist yet
      File.copy(json_file, bak_file)
      File.write(json_file, encoded)
    end
  end

  @doc "Writes root_meta_info.json"
  @spec write_root_meta(String.t(), map()) :: :ok | {:error, term()}
  def write_root_meta(root_path, data) do
    meta_file = Path.join(root_path, "root_meta_info.json")

    with {:ok, encoded} <- Jason.encode(data) do
      File.write(meta_file, encoded)
    end
  end
end
