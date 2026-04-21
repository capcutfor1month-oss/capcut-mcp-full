defmodule CapcutMcp.CapCut.Writer do
  @moduledoc "Writes CapCut project data to the local filesystem, with backup on overwrite."

  @doc "Writes draft_content.json atomically; backs up existing file to .bak first."
  @spec write_draft(String.t(), map()) :: :ok | {:error, term()}
  def write_draft(draft_path, content) do
    json_file = Path.join(draft_path, "draft_content.json")

    with {:ok, encoded} <- Jason.encode(content),
         do: atomic_write(json_file, encoded, backup: true)
  end

  @doc """
  Writes root_meta_info.json atomically.

  Pass `backup: true` to copy any existing `root_meta_info.json` to
  `root_meta_info.json.bak` before overwriting — used by destructive paths
  like project removal so a bad edit stays recoverable.
  """
  @spec write_root_meta(String.t(), map(), keyword()) :: :ok | {:error, term()}
  def write_root_meta(root_path, data, opts \\ []) do
    meta_file = Path.join(root_path, "root_meta_info.json")

    with {:ok, encoded} <- Jason.encode(data),
         do: atomic_write(meta_file, encoded, backup: Keyword.get(opts, :backup, false))
  end

  defp atomic_write(target, content, opts) do
    tmp_file = target <> ".tmp"

    with :ok <- File.write(tmp_file, content),
         :ok <- maybe_backup(target, Keyword.get(opts, :backup, false)),
         :ok <- File.rename(tmp_file, target) do
      :ok
    else
      {:error, _} = err ->
        # Rename/backup failed — the temp file is leftover garbage that would
        # otherwise accumulate next to CapCut's project files on every retry.
        _ = File.rm(tmp_file)
        err
    end
  end

  defp maybe_backup(_target, false), do: :ok

  defp maybe_backup(target, true) do
    case File.copy(target, target <> ".bak") do
      {:ok, _} -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, {:backup_failed, reason}}
    end
  end
end
