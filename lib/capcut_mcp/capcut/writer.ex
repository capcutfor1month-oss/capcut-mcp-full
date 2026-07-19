defmodule CapcutMcp.CapCut.Writer do
  @moduledoc "Writes CapCut project data to the local filesystem, with backup on overwrite."

  @doc """
  Writes the project's draft JSON atomically; backs up any existing file to
  `.bak` first.

  Filename is auto-detected to match what's already on disk, mirroring
  `Reader.read_draft/1`'s lookup order: if `draft_content.json` exists,
  write there (preserves the legacy format some existing macOS/Windows
  projects still use — confirmed present without a `Timelines/` folder on a
  real project, e.g. "MFA Mobile"). Else if `draft_info.json` exists, write
  there. Else (brand-new project, neither file exists yet) default to
  `draft_info.json` — confirmed via a live filesystem diff that current
  CapCut (macOS) writes new projects' content to `draft_info.json` at the
  project root, not `draft_content.json`, and not nested under `Timelines/`.
  """
  @spec write_draft(String.t(), map()) :: :ok | {:error, term()}
  def write_draft(draft_path, content) do
    json_file = Path.join(draft_path, target_filename(draft_path))

    with {:ok, encoded} <- Jason.encode(content),
         do: atomic_write(json_file, encoded, backup: true)
  end

  defp target_filename(draft_path) do
    cond do
      File.exists?(Path.join(draft_path, "draft_content.json")) -> "draft_content.json"
      File.exists?(Path.join(draft_path, "draft_info.json")) -> "draft_info.json"
      true -> "draft_info.json"
    end
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
