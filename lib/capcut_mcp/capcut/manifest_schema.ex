defmodule CapcutMcp.CapCut.ManifestSchema do
  @moduledoc """
  Builds a CapCut-compatible `all_draft_store` entry for `root_meta_info.json`.

  CapCut validates manifest entries on startup and silently drops entries that
  miss required keys. A minimal 10-field entry survives our own reader but is
  rejected by the CapCut UI. `new_entry/1` returns the full field shape
  observed in native CapCut builds (164.0.0), with caller-controlled values
  for the identity/timestamp/path fields and ByteDance-style sentinel defaults
  for cloud/draft-state fields.

  The original 32-field shape here was reverse-engineered from Windows CapCut
  manifests only. Live entries from macOS CapCut 164.0.0 additionally carry
  five `pippit_*` / `draft_is_pippit_draft` fields (Pippit is ByteDance's
  separate AI-avatar app; CapCut's manifest schema apparently unified with it
  on macOS builds but not the Windows build this was first tested against).
  Confirmed by diffing a tool-written entry lacking them against a real macOS
  entry: CapCut's project list silently omitted the tool-written entry even
  after a full quit and relaunch, and the omission stopped after adding these
  fields. Missing them is the same silent-drop failure mode described above,
  just on a different platform than the one this module was validated on.
  """

  @draft_entry_defaults %{
    "cloud_draft_cover" => false,
    "cloud_draft_sync" => false,
    "draft_cloud_last_action_download" => false,
    "draft_cloud_purchase_info" => "",
    "draft_cloud_template_id" => "",
    "draft_cloud_tutorial_info" => "",
    "draft_cloud_videocut_purchase_info" => "",
    "draft_is_ai_shorts" => false,
    "draft_is_cloud_temp_draft" => false,
    "draft_is_invisible" => false,
    "draft_is_pippit_draft" => false,
    "draft_is_web_article_video" => false,
    "draft_type" => "",
    "draft_web_article_video_enter_from" => "",
    "pippit_avatar_url" => "",
    "pippit_extra_info" => "",
    "pippit_id" => "",
    "pippit_user_name" => "",
    "streaming_edit_draft_ready" => true,
    "tm_draft_cloud_completed" => "",
    "tm_draft_cloud_entry_id" => -1,
    "tm_draft_cloud_modified" => 0,
    "tm_draft_cloud_parent_entry_id" => -1,
    "tm_draft_cloud_space_id" => -1,
    "tm_draft_cloud_user_id" => -1,
    "tm_draft_removed" => 0,
    "tm_duration" => 0
  }

  @default_version "164.0.0"

  @required_opts [
    :draft_id,
    :draft_name,
    :fold_path,
    :json_file,
    :cover_path,
    :root_path,
    :now_us
  ]

  @type opts :: [
          draft_id: String.t(),
          draft_name: String.t(),
          fold_path: String.t(),
          json_file: String.t(),
          cover_path: String.t(),
          root_path: String.t(),
          now_us: integer(),
          version: String.t(),
          timeline_materials_size: non_neg_integer()
        ]

  @doc """
  Returns the canonical list of keys a CapCut-compatible manifest entry must expose.
  """
  @spec keys() :: [String.t()]
  def keys do
    caller_keys = [
      "draft_cover",
      "draft_fold_path",
      "draft_id",
      "draft_json_file",
      "draft_name",
      "draft_new_version",
      "draft_root_path",
      "draft_timeline_materials_size",
      "tm_draft_create",
      "tm_draft_modified"
    ]

    Enum.sort(caller_keys ++ Map.keys(@draft_entry_defaults))
  end

  @doc """
  Builds a manifest entry. All keys in `@required_opts` must be provided;
  `:version` defaults to the latest schema version observed in the wild
  (`#{@default_version}`).

  `:timeline_materials_size` defaults to `0` but should be passed as the
  byte size of the encoded `draft_info.json` content. Confirmed load-bearing
  for CapCut's *open* action (a separate gate from the project-list
  visibility check both other fields in this module fix): a real, empty,
  never-edited project's manifest entry carries this field equal to its
  `draft_info.json`'s exact byte count (4181 in the captured case) — not 0,
  despite having no actual media/materials. A manifest entry written with
  this hardcoded to `0` appeared in CapCut's project list but silently
  failed to open (no file access, no error, just no navigation) even after
  a full quit/relaunch, while an otherwise-identical CapCut-created project
  opened normally.
  """
  @spec new_entry(opts()) :: map()
  def new_entry(opts) do
    ensure_required!(opts)

    Map.merge(@draft_entry_defaults, %{
      "draft_id" => Keyword.fetch!(opts, :draft_id),
      "draft_name" => Keyword.fetch!(opts, :draft_name),
      "draft_fold_path" => Keyword.fetch!(opts, :fold_path),
      "draft_json_file" => Keyword.fetch!(opts, :json_file),
      "draft_cover" => Keyword.fetch!(opts, :cover_path),
      "draft_new_version" => Keyword.get(opts, :version, @default_version),
      "draft_root_path" => Keyword.fetch!(opts, :root_path),
      "draft_timeline_materials_size" => Keyword.get(opts, :timeline_materials_size, 0),
      "tm_draft_create" => Keyword.fetch!(opts, :now_us),
      "tm_draft_modified" => Keyword.fetch!(opts, :now_us)
    })
  end

  @doc "The schema version written into new entries by default."
  @spec default_version() :: String.t()
  def default_version, do: @default_version

  defp ensure_required!(opts) do
    missing = Enum.reject(@required_opts, &Keyword.has_key?(opts, &1))

    unless missing == [] do
      raise ArgumentError,
            "CapcutMcp.CapCut.ManifestSchema.new_entry/1 missing required opts: #{inspect(missing)}"
    end

    :ok
  end
end
