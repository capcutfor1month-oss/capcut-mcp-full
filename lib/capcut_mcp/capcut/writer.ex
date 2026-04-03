defmodule CapcutMcp.CapCut.Writer do
  @moduledoc "Writes CapCut project data to the local filesystem, with backup on overwrite."

  @doc "Writes draft_content.json; backs up existing file to .bak first. Uses atomic write (tmp + rename) for safety."
  @spec write_draft(String.t(), map()) :: :ok | {:error, term()}
  def write_draft(draft_path, content) do
    json_file = Path.join(draft_path, "draft_content.json")
    bak_file = Path.join(draft_path, "draft_content.json.bak")
    tmp_file = Path.join(draft_path, "draft_content.json.tmp")

    with {:ok, encoded} <- Jason.encode(content),
         :ok <- File.write(tmp_file, encoded),
         :ok <- backup_if_exists(json_file, bak_file) do
      File.rename(tmp_file, json_file)
    end
  end

  defp backup_if_exists(source, dest) do
    case File.copy(source, dest) do
      {:ok, _} -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, {:backup_failed, reason}}
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
