defmodule CapcutMcp.CapCut.ManifestSchemaTest do
  use ExUnit.Case, async: true

  alias CapcutMcp.CapCut.ManifestSchema

  # Full set of 37 keys observed in native CapCut 164.0.0 `all_draft_store` entries.
  # This list is the canonical source of truth — if CapCut changes its schema
  # and a key needs to be added/removed, update both this test and
  # ManifestSchema in the same commit.
  #
  # The 5 pippit_* / draft_is_pippit_draft keys were added after discovering
  # (via a live macOS CapCut 164.0.0 relaunch test) that entries missing them
  # are silently dropped from the project list on macOS, even though the
  # original 32-key set was sufficient on Windows. See ManifestSchema's
  # moduledoc for the full story.
  @expected_keys ~w(
    cloud_draft_cover
    cloud_draft_sync
    draft_cloud_last_action_download
    draft_cloud_purchase_info
    draft_cloud_template_id
    draft_cloud_tutorial_info
    draft_cloud_videocut_purchase_info
    draft_cover
    draft_fold_path
    draft_id
    draft_is_ai_shorts
    draft_is_cloud_temp_draft
    draft_is_invisible
    draft_is_pippit_draft
    draft_is_web_article_video
    draft_json_file
    draft_name
    draft_new_version
    draft_root_path
    draft_timeline_materials_size
    draft_type
    draft_web_article_video_enter_from
    pippit_avatar_url
    pippit_extra_info
    pippit_id
    pippit_user_name
    streaming_edit_draft_ready
    tm_draft_cloud_completed
    tm_draft_cloud_entry_id
    tm_draft_cloud_modified
    tm_draft_cloud_parent_entry_id
    tm_draft_cloud_space_id
    tm_draft_cloud_user_id
    tm_draft_create
    tm_draft_modified
    tm_draft_removed
    tm_duration
  )

  defp sample_opts(overrides \\ []) do
    Keyword.merge(
      [
        draft_id: "UUID-1",
        draft_name: "My Clip",
        fold_path: "C:/Users/u/Projects/com.lveditor.draft/My_Clip",
        json_file: "C:/Users/u/Projects/com.lveditor.draft/My_Clip\\draft_content.json",
        cover_path: "C:/Users/u/Projects/com.lveditor.draft/My_Clip/draft_cover.jpg",
        root_path: "C:/Users/u/Projects/com.lveditor.draft",
        now_us: 1_776_805_299_129_000
      ],
      overrides
    )
  end

  test "keys/0 returns exactly the 37 CapCut-compatible field names" do
    assert Enum.sort(@expected_keys) == ManifestSchema.keys()
    assert length(@expected_keys) == 37
  end

  test "new_entry/1 returns an entry with exactly the 37 expected keys" do
    entry = ManifestSchema.new_entry(sample_opts())

    assert Enum.sort(Map.keys(entry)) == Enum.sort(@expected_keys)
    assert map_size(entry) == 37
  end

  test "new_entry/1 writes caller-provided identity and path fields verbatim" do
    opts = sample_opts()
    entry = ManifestSchema.new_entry(opts)

    assert entry["draft_id"] == opts[:draft_id]
    assert entry["draft_name"] == opts[:draft_name]
    assert entry["draft_fold_path"] == opts[:fold_path]
    assert entry["draft_json_file"] == opts[:json_file]
    assert entry["draft_cover"] == opts[:cover_path]
    assert entry["draft_root_path"] == opts[:root_path]
  end

  test "new_entry/1 mirrors :now_us into both tm_draft_create and tm_draft_modified" do
    now = 1_776_805_299_129_000
    entry = ManifestSchema.new_entry(sample_opts(now_us: now))

    assert entry["tm_draft_create"] == now
    assert entry["tm_draft_modified"] == now
  end

  test "new_entry/1 defaults draft_new_version to the module default (164.0.0)" do
    entry = ManifestSchema.new_entry(sample_opts())
    assert entry["draft_new_version"] == ManifestSchema.default_version()
    assert entry["draft_new_version"] == "164.0.0"
  end

  test "new_entry/1 accepts a custom :version" do
    entry = ManifestSchema.new_entry(sample_opts(version: "163.0.0"))
    assert entry["draft_new_version"] == "163.0.0"
  end

  test "new_entry/1 writes ByteDance-style cloud sentinels" do
    entry = ManifestSchema.new_entry(sample_opts())

    # -1 sentinels — observed in native entries for every cloud-id field
    assert entry["tm_draft_cloud_entry_id"] == -1
    assert entry["tm_draft_cloud_parent_entry_id"] == -1
    assert entry["tm_draft_cloud_space_id"] == -1
    assert entry["tm_draft_cloud_user_id"] == -1

    # Empty-string / zero sentinels
    assert entry["tm_draft_cloud_completed"] == ""
    assert entry["tm_draft_cloud_modified"] == 0

    # Boolean defaults for local drafts
    assert entry["cloud_draft_cover"] == false
    assert entry["cloud_draft_sync"] == false
    assert entry["draft_cloud_last_action_download"] == false
    assert entry["draft_is_cloud_temp_draft"] == false
  end

  test "new_entry/1 writes empty Pippit sentinels for locally-created drafts" do
    # Pippit is ByteDance's separate AI-avatar app; a locally-created CapCut
    # draft is never a Pippit draft, so these are all empty/false. Confirmed
    # required for macOS visibility: a real macOS CapCut 164.0.0 entry always
    # carries these 5 keys, and a tool-written entry missing them was
    # silently absent from CapCut's project list even after a full relaunch.
    entry = ManifestSchema.new_entry(sample_opts())

    assert entry["draft_is_pippit_draft"] == false
    assert entry["pippit_avatar_url"] == ""
    assert entry["pippit_extra_info"] == ""
    assert entry["pippit_id"] == ""
    assert entry["pippit_user_name"] == ""
  end

  test "new_entry/1 marks the draft as ready for CapCut's streaming editor" do
    # Native entries have this true; if CapCut performs a readiness check on
    # startup this is the field most likely to gate visibility in the project list.
    entry = ManifestSchema.new_entry(sample_opts())
    assert entry["streaming_edit_draft_ready"] == true
  end

  test "new_entry/1 raises ArgumentError when required opts are missing" do
    assert_raise ArgumentError, ~r/missing required opts/, fn ->
      ManifestSchema.new_entry(draft_id: "x", draft_name: "y")
    end
  end
end
