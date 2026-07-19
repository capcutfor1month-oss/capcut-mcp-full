defmodule CapcutMcp.CapCut.Scaffold do
  @moduledoc """
  Builds the full set of companion files CapCut writes alongside
  `draft_info.json` for a brand-new project — not just the draft content
  itself.

  ## Provenance

  Captured from a *pristine* real project: created through CapCut's own
  macOS UI (app_version 8.9.1), closed immediately with zero edits, then
  every file under the project folder was copied out and diffed. This is
  deliberately the empty-project snapshot, not a snapshot after adding
  media — an earlier attempt used a post-edit capture and mixed in
  content-specific data (material IDs, real file paths) that doesn't belong
  in a fresh scaffold.

  This scaffolding turned out to be necessary, not cosmetic: a `create_project`
  call that wrote only a schema-complete `draft_info.json` plus a
  schema-complete `root_meta_info.json` manifest entry was still silently
  absent from CapCut's project list after a full quit/relaunch. Only after
  adding this full file set (verified against the pristine capture) does a
  programmatically-created project match what CapCut itself produces.

  ## What's included, what's skipped

  Included: every file that existed in the pristine capture before any edit
  — 9 root-level files, `common_attachment/attachment_pc_timeline.json`, the
  `Timelines/project.json` index, and the full `Timelines/[uuid]/` mirror
  (its own `draft_info.json` — confirmed byte-identical to the root copy —
  plus `attachment_editing.json` and its own `common_attachment/*`).

  Also included: `template-2.tmp` at the project root, byte-identical to
  `draft_info.json`. Originally skipped as a presumed CapCut save-cache
  artifact — checking all 12 real, currently-working CapCut projects on
  disk showed every one of them (except one non-standard `CLIP 1` entry
  that isn't a real draft folder) carries `template-2.tmp`, byte-for-byte
  identical to that project's own `draft_info.json`. A third-party
  CapCut-CLI project's bug report (github.com/renezander030/capcut-cli
  issue #35 / docs/version-support.md) claims that on CapCut 8.7+, a
  readable `template-2.tmp` takes precedence over `draft_info.json` when
  resolving which timeline to load.

  TESTED AND DISPROVEN as a standalone fix (2026-07-20): added this file
  to a fresh scaffold (`ClaudeMCP_TestProject_v8`), confirmed it was
  written byte-identical, confirmed the project appeared in CapCut's live
  project list without even a relaunch — then double-clicked it in the
  real CapCut UI. Same silent failure as every prior attempt: `find
  -newer` on the whole project folder showed CapCut touched *zero files*
  on click, no error, no navigation. Left in the scaffold anyway (it's
  harmless and matches ground truth), but it is not the fix.

  The zero-file-access result is itself the important data point: it
  means CapCut's open-gate check happens *before* it ever reads anything
  in the draft folder. Combined with the earlier finding that CapCut's
  own "Duplicate" of a real, working project produces a byte-identical
  copy that *also* fails to open, this points away from "some field or
  file inside the draft folder is wrong" and toward an external registry
  — most likely a local SQLite/LevelDB store elsewhere under CapCut's
  `User Data` directory that only CapCut's own native create/duplicate
  code path populates, and which a JSON-writing tool like this one cannot
  reach by writing files into the draft folder alone. Not yet located or
  confirmed; next investigator should look for `.db`/`.sqlite` files
  under `User Data` and diff them before/after a native "New Project".

  `template.tmp` (no "-2") was also observed but is NOT included here:
  present in only about half of real projects, and where present it's a
  tiny (~4KB) generic empty-draft skeleton, not project-specific content.

  ## `.bak` files: also required, not just save-cache noise (2026-07-20)

  A second ground-truth capture — this time a full before/after file-tree
  diff of CapCut's entire `User Data` directory (not just the draft
  folder) around a fresh native "Create project" — settled something the
  `template-2.tmp`-only fix left open: `.bak` files are written as part of
  *initial* project creation, not just accumulated from later saves.
  Confirmed present immediately after creating a never-edited native
  project, each byte-identical to its non-`.bak` counterpart:
  `draft_info.json.bak` (root), `Timelines/project.json.bak`, and
  `Timelines/[uuid]/draft_info.json.bak` — plus `Timelines/[uuid]/
  template-2.tmp` (the per-timeline mirror, not just the root one). All
  four are now included below. `template.json.bak` (a different, oddly
  named `.bak` seen only on some older real projects, with no matching
  non-`.bak` file) looks like a leftover from a prior CapCut schema
  version, not part of fresh creation — not included.

  Untested whether this is actually sufficient to fix the open gate.
  Hypothesis: an editor whose atomic-save pattern is
  "write-new-then-rename-old-to-.bak" may treat the total absence of any
  `.bak` trail as a signal of a corrupted/interrupted write and refuse to
  open — but this is a plausible mechanism, not a confirmed one.

  Still skipped: `.bak` files (`draft_info.json.bak`, `template.json.bak`,
  `crypto_key_store.dat.bak`) and `template.tmp` — CapCut's own save-cache
  artifacts, not yet shown to be load-bearing for opening a fresh project.
  """

  @doc """
  Returns `{relative_path, content}` pairs for every companion file, where
  `content` is a map (to be JSON-encoded) for `.json` files or a plain
  string for `draft_settings` (CapCut's own file, INI format, not JSON).

  `opts` — all required:
    * `:draft_id` — the project's id, reused as `draft_meta_info.json`'s `draft_id`
    * `:name` — project name
    * `:fold_path` — absolute path to the project folder (forward-slash)
    * `:root_path` — absolute path to the `com.lveditor.draft` root (forward-slash)
    * `:timeline_id` — UUID for the single default timeline
    * `:timelines_project_id` — separate UUID for `Timelines/project.json`'s
      own `id` field. Confirmed distinct from `:timeline_id` in a real
      capture (`Timelines/project.json`'s `id` and its `main_timeline_id` /
      `timelines[0].id` were different UUIDs) — an earlier version of this
      module reused `:timeline_id` for both, which is wrong even though it
      wasn't provably the open-blocker at the time it was caught.
    * `:now_us` — creation timestamp in microseconds (reused for both
      create/modified — a fresh project has never been separately modified)
    * `:draft_json` — the already-built `Draft.to_json/1` map, duplicated
      verbatim into `Timelines/[timeline_id]/draft_info.json`
    * `:timeline_materials_size` — byte size of `:draft_json` once
      JSON-encoded. Written into `draft_meta_info.json`'s
      `draft_timeline_materials_size_`. Confirmed load-bearing: a pristine,
      never-edited CapCut-created project carries this equal to its
      `draft_info.json`'s exact byte count, not 0 — see
      `ManifestSchema.new_entry/1`'s doc for the matching manifest-side field
      and the open-vs-list distinction this was found to gate.
  """
  @spec build(keyword()) :: [{String.t(), map() | String.t()}]
  def build(opts) do
    draft_id = Keyword.fetch!(opts, :draft_id)
    name = Keyword.fetch!(opts, :name)
    fold_path = Keyword.fetch!(opts, :fold_path)
    root_path = Keyword.fetch!(opts, :root_path)
    timeline_id = Keyword.fetch!(opts, :timeline_id)
    timelines_project_id = Keyword.fetch!(opts, :timelines_project_id)
    now_us = Keyword.fetch!(opts, :now_us)
    draft_json = Keyword.fetch!(opts, :draft_json)
    timeline_materials_size = Keyword.fetch!(opts, :timeline_materials_size)

    now_s = div(now_us, 1_000_000)
    timeline_uuid_prefix = "Timelines/#{timeline_id}"
    project_json = timelines_project(timelines_project_id, timeline_id, now_us)

    [
      {"attachment_pc_common.json", attachment_pc_common()},
      {"draft_agency_config.json", draft_agency_config()},
      {"draft_biz_config.json", draft_biz_config(timeline_id)},
      {"draft_meta_info.json",
       draft_meta_info(draft_id, name, fold_path, root_path, now_us, timeline_materials_size)},
      {"performance_opt_info.json", performance_opt_info()},
      {"timeline_layout.json", timeline_layout(timeline_id)},
      {"draft_settings", draft_settings(now_s)},
      {"draft_info.json.bak", draft_json},
      {"template-2.tmp", draft_json},
      {"common_attachment/attachment_pc_timeline.json", attachment_pc_timeline()},
      {"Timelines/project.json", project_json},
      {"Timelines/project.json.bak", project_json},
      {"#{timeline_uuid_prefix}/draft_info.json", draft_json},
      {"#{timeline_uuid_prefix}/draft_info.json.bak", draft_json},
      {"#{timeline_uuid_prefix}/template-2.tmp", draft_json},
      {"#{timeline_uuid_prefix}/attachment_editing.json", attachment_editing()},
      {"#{timeline_uuid_prefix}/attachment_pc_common.json", attachment_pc_common()},
      {"#{timeline_uuid_prefix}/common_attachment/attachment_pc_timeline.json",
       attachment_pc_timeline()},
      {"#{timeline_uuid_prefix}/common_attachment/attachment_action_scene.json",
       attachment_action_scene()},
      {"#{timeline_uuid_prefix}/common_attachment/attachment_gen_ai_info.json",
       attachment_gen_ai_info()},
      {"#{timeline_uuid_prefix}/common_attachment/attachment_script_video.json",
       attachment_script_video()}
    ]
  end

  defp attachment_pc_common do
    ai_packaging_report_info = %{
      "caption_id_list" => [],
      "commercial_material" => "",
      "material_source" => "",
      "method" => "",
      "page_from" => "",
      "style" => "",
      "task_id" => "",
      "text_style" => "",
      "tos_id" => "",
      "video_category" => ""
    }

    %{
      "ai_packaging_infos" => [],
      "ai_packaging_report_info" => ai_packaging_report_info,
      "broll" => %{
        "ai_packaging_infos" => [],
        "ai_packaging_report_info" => ai_packaging_report_info
      },
      "commercial_music_category_ids" => [],
      "pc_feature_flag" => 0,
      "recognize_tasks" => [],
      "reference_lines_config" => %{
        "horizontal_lines" => [],
        "is_lock" => false,
        "is_visible" => false,
        "vertical_lines" => []
      },
      "safe_area_type" => 0,
      "template_item_infos" => [],
      "unlock_template_ids" => []
    }
  end

  defp attachment_pc_timeline do
    %{
      "reference_lines_config" => %{
        "horizontal_lines" => [],
        "is_lock" => false,
        "is_visible" => false,
        "vertical_lines" => []
      },
      "safe_area_type" => 0
    }
  end

  defp draft_agency_config do
    %{
      "is_auto_agency_enabled" => false,
      "is_auto_agency_popup" => false,
      "is_single_agency_mode" => false,
      "marterials" => nil,
      "use_converter" => false,
      "video_resolution" => 720
    }
  end

  defp draft_biz_config(timeline_id) do
    %{
      "timeline_settings" => %{
        timeline_id => %{"linkage_enabled" => false}
      }
    }
  end

  defp draft_meta_info(draft_id, name, fold_path, root_path, now_us, timeline_materials_size) do
    empty_material_buckets =
      for type <- [0, 1, 2, 3, 6, 7, 8], do: %{"type" => type, "value" => []}

    %{
      "cloud_draft_cover" => false,
      "cloud_draft_sync" => false,
      "cloud_package_completed_time" => "",
      "draft_cloud_capcut_purchase_info" => "",
      "draft_cloud_last_action_download" => false,
      "draft_cloud_package_type" => "",
      "draft_cloud_purchase_info" => "",
      "draft_cloud_template_id" => "",
      "draft_cloud_tutorial_info" => "",
      "draft_cloud_videocut_purchase_info" => "",
      "draft_cover" => "draft_cover.jpg",
      "draft_deeplink_url" => "",
      "draft_enterprise_info" => %{
        "draft_enterprise_extra" => "",
        "draft_enterprise_id" => "",
        "draft_enterprise_name" => "",
        "enterprise_material" => []
      },
      "draft_fold_path" => fold_path,
      "draft_id" => draft_id,
      "draft_is_ae_produce" => false,
      "draft_is_ai_packaging_used" => false,
      "draft_is_ai_shorts" => false,
      "draft_is_ai_translate" => false,
      "draft_is_article_video_draft" => false,
      "draft_is_cloud_temp_draft" => false,
      "draft_is_from_deeplink" => "false",
      "draft_is_invisible" => false,
      "draft_is_pippit_draft" => false,
      "draft_is_web_article_video" => false,
      "draft_materials" => empty_material_buckets,
      "draft_materials_copied_info" => [],
      "draft_name" => name,
      "draft_need_rename_folder" => false,
      "draft_new_version" => "",
      "draft_removable_storage_device" => "",
      "draft_root_path" => root_path,
      "draft_segment_extra_info" => [],
      "draft_timeline_materials_size_" => timeline_materials_size,
      "draft_type" => "",
      "draft_web_article_video_enter_from" => "",
      "pippit_avatar_url" => "",
      "pippit_extra_info" => "",
      "pippit_id" => "",
      "pippit_user_name" => "",
      "tm_draft_cloud_completed" => "",
      "tm_draft_cloud_entry_id" => -1,
      "tm_draft_cloud_modified" => 0,
      "tm_draft_cloud_parent_entry_id" => -1,
      "tm_draft_cloud_space_id" => -1,
      "tm_draft_cloud_user_id" => -1,
      "tm_draft_create" => now_us,
      "tm_draft_modified" => now_us,
      "tm_draft_removed" => 0,
      "tm_duration" => 0
    }
  end

  defp performance_opt_info do
    %{"manual_cancle_precombine_segs" => nil, "need_auto_precombine_segs" => nil}
  end

  defp timeline_layout(timeline_id) do
    %{
      "dockItems" => [
        %{
          "dockIndex" => 0,
          "ratio" => 1,
          "timelineIds" => [timeline_id],
          "timelineNames" => ["Timeline 01"]
        }
      ],
      "layoutOrientation" => 1
    }
  end

  defp draft_settings(now_s) do
    """
    [General]
    draft_create_time=#{now_s}
    draft_last_edit_time=#{now_s}
    real_edit_keys=0
    real_edit_seconds=0
    """
  end

  defp timelines_project(timelines_project_id, timeline_id, now_us) do
    %{
      "config" => %{
        "color_space" => -1,
        "render_index_track_mode_on" => false,
        "use_float_render" => false
      },
      "create_time" => now_us,
      "id" => timelines_project_id,
      "main_timeline_id" => timeline_id,
      "timelines" => [
        %{
          "create_time" => now_us,
          "id" => timeline_id,
          "is_marked_delete" => false,
          "name" => "Timeline 01",
          "update_time" => now_us
        }
      ],
      "update_time" => now_us,
      "version" => 0
    }
  end

  defp attachment_editing do
    %{
      "editing_draft" => %{
        "ai_remove_filter_words" => %{"enter_source" => "", "right_id" => ""},
        "ai_shorts_info" => %{"report_params" => "", "type" => 0},
        "cover_extra_info" => %{
          "draft_id" => "",
          "position" => 0,
          "select_segment_id" => "",
          "select_segment_source_start" => 0,
          "select_segment_target_start" => 0,
          "type" => 1
        },
        "crop_info_extra" => %{
          "crop_mirror_type" => 0,
          "crop_rotate" => 0.0,
          "crop_rotate_total" => 0.0
        },
        "digital_human_template_to_video_info" => %{
          "has_upload_material" => false,
          "template_type" => 0
        },
        "draft_used_recommend_function" => "",
        "edit_type" => 0,
        "eye_correct_enabled_multi_face_time" => 0,
        "has_adjusted_render_layer" => false,
        "image_ai_chat_info" => %{
          "before_chat_edit" => false,
          "draft_modify_time" => 0,
          "generate_type" => "",
          "inspiration_item_id" => "",
          "inspiration_item_name" => "",
          "keyword_content" => "",
          "keyword_id" => "",
          "keyword_name" => "",
          "keyword_type" => "",
          "message_id" => "",
          "model_name" => "",
          "need_restore" => false,
          "picture_id" => "",
          "prompt_content" => "",
          "prompt_from" => "",
          "sugs_info" => []
        },
        "is_open_expand_player" => false,
        "is_template_text_ai_generate" => false,
        "is_use_adjust" => false,
        "is_use_ai_expand" => false,
        "is_use_ai_image" => false,
        "is_use_ai_remove" => false,
        "is_use_ai_video" => false,
        "is_use_audio_separation" => false,
        "is_use_chroma_key" => false,
        "is_use_curve_speed" => false,
        "is_use_digital_human" => false,
        "is_use_edit_multi_camera" => false,
        "is_use_lip_sync" => false,
        "is_use_lock_object" => false,
        "is_use_loudness_unify" => false,
        "is_use_noise_reduction" => false,
        "is_use_one_click_beauty" => false,
        "is_use_one_click_ultra_hd" => false,
        "is_use_retouch_face" => false,
        "is_use_smart_adjust_color" => false,
        "is_use_smart_body_beautify" => false,
        "is_use_smart_motion" => false,
        "is_use_subtitle_recognition" => false,
        "is_use_text_to_audio" => false,
        "material_edit_session" => %{
          "material_edit_info" => [],
          "session_id" => "",
          "session_time" => 0
        },
        "paste_segment_list" => [],
        "profile_entrance_type" => "",
        "publish_enter_from" => "",
        "publish_type" => "",
        "single_function_type" => 0,
        "text_convert_case_types" => [],
        "version" => "1.0.0",
        "video_recording_create_draft" => ""
      }
    }
  end

  defp attachment_action_scene do
    %{"action_scene" => %{"removed_segments" => [], "segment_infos" => []}}
  end

  defp attachment_gen_ai_info do
    %{
      "gen_ai" => %{
        "ai_func_config" => %{
          "ai_common_configs" => [],
          "ai_effect_configs" => [],
          "ai_func_list" => [],
          "aigc_generation_configs" => []
        },
        "cc_agent_info" => %{
          "agent_stringent_section_id_list" => [],
          "agent_stringent_used_tool_list" => [],
          "click_cnt" => 0,
          "consume_credits_function_list" => [],
          "conversation_ids" => [],
          "generate_success_cnt" => 0,
          "is_agent_stringent_used" => false,
          "is_agent_used" => false,
          "request_cnt" => 0,
          "request_from" => [],
          "tool_list" => []
        },
        "id" => "",
        "scene" => "",
        "version" => "1.0.0"
      }
    }
  end

  defp attachment_script_video do
    %{
      "script_video" => %{
        "attachment_valid" => false,
        "language" => "",
        "overdub_recover" => [],
        "overdub_sentence_ids" => [],
        "parts" => [],
        "sync_subtitle" => false,
        "translate_segments" => [],
        "translate_type" => "",
        "version" => "1.0.0"
      }
    }
  end
end
