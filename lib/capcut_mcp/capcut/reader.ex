defmodule CapcutMcp.CapCut.Reader do
  @moduledoc """
  Reads CapCut project metadata and draft content from the local filesystem.

  ## Telemetry

  Every successful `read_draft/1` call emits:

    * `[:capcut_mcp, :draft, :schema_version]`
      * **measurements**: `%{count: 1}`
      * **metadata**: `%{version: String.t() | nil, supported: boolean()}`

  `list_projects/1` additionally emits:

    * `[:capcut_mcp, :meta, :rejected]`
      * **measurements**: `%{count: 1}`
      * **metadata**: `%{reason: :path_outside_root, path: String.t()}`

  The schema event fires for both supported and unsupported versions so
  attached handlers can build an audit trail of which CapCut schema versions
  show up in the wild. Unsupported or missing versions are additionally logged
  at `:warning` level — the server continues to read the draft and return it
  to the caller.

  The `meta/rejected` event fires once per skipped `root_meta_info.json` entry
  whose `draft_fold_path` resolves outside the configured root. This guards
  against a corrupt or malicious meta file causing the server to read or
  write arbitrary paths on disk.
  """

  require Logger

  alias CapcutMcp.CapCut.ProjectMeta

  @supported_versions ~w(163.0.0 164.0.0)

  @doc "Reads all project metadata from root_meta_info.json"
  @spec list_projects(String.t()) :: {:ok, [ProjectMeta.t()]} | {:error, term()}
  def list_projects(root_path) do
    meta_file = Path.join(root_path, "root_meta_info.json")

    with {:ok, content} <- File.read(meta_file),
         {:ok, data} <- Jason.decode(content) do
      expanded_root = Path.expand(root_path)

      projects =
        data
        |> Map.get("all_draft_store", [])
        |> Enum.flat_map(&decode_entry(&1, expanded_root))

      {:ok, projects}
    end
  end

  defp decode_entry(
         %{"draft_id" => id, "draft_name" => name, "draft_fold_path" => path} = draft,
         expanded_root
       )
       when is_binary(id) and is_binary(name) and is_binary(path) do
    if path_under_root?(path, expanded_root) do
      [
        %ProjectMeta{
          id: id,
          name: name,
          path: path,
          modified_at: parse_ts(draft["tm_draft_modified"]),
          duration_ms: parse_duration(draft["tm_duration"])
        }
      ]
    else
      emit_rejected(path)
      []
    end
  end

  defp decode_entry(_incomplete, _expanded_root), do: []

  # Windows filesystems are case-insensitive, and Path.expand normalizes to `/`
  # but root_meta_info.json can store either separator. Normalize both sides
  # (case and separator) before comparing, so a config with `CAPCUT_PATH=C:\…`
  # doesn't silently reject draft entries written as `c:\…`.
  @doc false
  @spec path_under_root?(String.t(), String.t()) :: boolean()
  def path_under_root?(path, expanded_root) do
    expanded = path |> Path.expand() |> normalize_for_compare()
    root = normalize_for_compare(expanded_root)

    expanded == root or String.starts_with?(expanded, root <> "/")
  end

  defp normalize_for_compare(path) do
    normalized = String.replace(path, "\\", "/")
    if windows?(), do: String.downcase(normalized), else: normalized
  end

  defp windows?, do: match?({:win32, _}, :os.type())

  defp emit_rejected(path) do
    Logger.warning(
      "root_meta_info.json references draft_fold_path outside of CAPCUT_PATH — " <>
        "ignoring: #{inspect(path)}"
    )

    :telemetry.execute(
      [:capcut_mcp, :meta, :rejected],
      %{count: 1},
      %{reason: :path_outside_root, path: path}
    )
  end

  @doc """
  Reads `draft_content.json` for a given project folder path.

  On success the decoded draft map is returned and a
  `[:capcut_mcp, :draft, :schema_version]` telemetry event is emitted. If the
  draft's `new_version` field is missing or not in `supported_versions/0` a
  warning is logged; the call still succeeds so the caller can attempt best-effort
  reads against newer CapCut releases.
  """
  @spec read_draft(String.t()) :: {:ok, map()} | {:error, term()}
  def read_draft(draft_path) do
    json_file = Path.join(draft_path, "draft_content.json")

    with {:ok, content} <- File.read(json_file),
         {:ok, draft} <- Jason.decode(content) do
      emit_schema_version(draft)
      {:ok, draft}
    end
  end

  @doc """
  Returns the list of CapCut schema versions this server has been tested against.
  """
  @spec supported_versions() :: [String.t()]
  def supported_versions, do: @supported_versions

  defp emit_schema_version(draft) do
    version = draft["new_version"]
    supported = version in @supported_versions

    if not supported do
      Logger.warning(
        "CapCut schema version #{inspect(version)} untested " <>
          "(supported: #{Enum.join(@supported_versions, ", ")}). " <>
          "Proceeding anyway; file a report if something looks off."
      )
    end

    :telemetry.execute(
      [:capcut_mcp, :draft, :schema_version],
      %{count: 1},
      %{version: version, supported: supported}
    )
  end

  defp parse_duration(nil), do: 0
  defp parse_duration(duration) when is_number(duration), do: duration |> trunc() |> div(1000)
  defp parse_duration(_), do: 0

  defp parse_ts(ts) when is_integer(ts) and ts >= 0, do: ts
  defp parse_ts(_), do: nil
end
