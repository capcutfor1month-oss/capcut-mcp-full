defmodule CapcutMcp.CapCut.Draft do
  @moduledoc """
  A typed representation of CapCut's `draft_info.json` schema.

  CapCut persists drafts as JSON with string keys. This module provides a
  **type-safe construction path** — you build a `%Draft{}` struct and serialize
  it via `to_json/1`, eliminating the class of "typo in string key" bugs at the
  point where the shape matters most (creation).

  Consumers that only read drafts may still work with the raw decoded map
  returned by `CapcutMcp.CapCut.Reader.read_draft/1` — converting to a struct
  is optional and only valuable when the entire field set is known.

  ## Schema provenance

  The full 36-key top-level shape (and the `platform`/`config` sub-shapes)
  was captured from a live file, not reverse-engineered from docs: created a
  real project through CapCut's own macOS UI (app_version 8.9.1), dragged a
  real image onto its timeline, and diffed the resulting
  `draft_info.json` against what this module previously produced. CapCut
  silently drops manifest entries and (per the same failure mode, one layer
  deeper) apparently expects the draft JSON itself to carry this full shape —
  a minimal draft written by an earlier version of this module was rejected
  by CapCut's project list even with a fully-populated manifest entry.

  `materials` originally kept only 8 buckets (videos/audios/texts/images/
  effects/transitions/stickers/filters), on the untested guess that CapCut
  wouldn't require the full set for a brand-new entry with no clips. That
  guess was wrong: a project written with only those 8 buckets appeared in
  CapCut's project list (list-time validation only checks the manifest +
  file existence) but silently failed to open — no error, no file access
  logged, just no navigation, even though an otherwise-identical
  CapCut-created empty project opened fine. Diffing against a pristine
  (created via CapCut's UI, closed with zero edits) `draft_info.json`
  revealed `materials` needs the full **55-key** shape (all empty arrays for
  a fresh project) — the same silent-drop failure mode as the manifest and
  `keyframes` fixes, just gating *open* instead of *list*. `keyframes`
  similarly needed an 8th bucket (`handwrites`), and `color_space` defaults
  to `-1`, not `0`.

  `platform`/`last_modified_platform` device-fingerprint fields
  (`device_id`, `hard_disk_id`, `mac_address`) are intentionally left as
  empty-string sentinels rather than reading this machine's real hardware
  identifiers into a project file.

  ## `:id` is the TIMELINE id, not the project's identity (2026-07-20)

  This was the actual root cause of every MCP-created project silently
  failing to open in CapCut — through 10 prior fix attempts (manifest
  schema, `materials`/`keyframes` shape, full companion-file scaffold,
  `template-2.tmp`, `.bak` files) — despite achieving byte-for-byte
  structural parity with real CapCut output on every other axis.

  Checked across all 12 real CapCut projects on disk: every single one has
  `draft_info.json`'s own `id` field DIFFERENT from its project's identity
  in `root_meta_info.json` (`draft_id`), and instead matching its own
  `Timelines/[uuid]/` subfolder name. Ten of those projects — entirely
  unrelated to each other — even share the exact same internal `id`
  value, proving it carries no per-project uniqueness requirement
  whatsoever; it's just the timeline's id, duplicated into the root
  `draft_info.json` as CapCut's own "single default timeline" convention.

  Every version of `ProjectStore.do_create_project/2` through the one that
  shipped `template-2.tmp` + `.bak` files used the SAME UUID for both the
  manifest's `draft_id` and this struct's `:id` — because that pairing is
  the obvious assumption from the field names, and every ground-truth
  capture used to validate prior fixes happened to be a real project where
  checking this specific relationship was never isolated. The caller MUST
  pass the timeline id here, not the project's manifest draft_id — see
  `ProjectStore.do_create_project/2`, which generates `timeline_id` first
  and threads it through to both `Draft.new/1`'s `:id` and the
  `Timelines/[timeline_id]/` folder name, keeping a separate, unrelated
  UUID for the manifest's `draft_id`.

  Confirmed live: a project built this way (`ClaudeMCP_TestProject_v11`)
  opened successfully in the real CapCut editor — the first MCP-created
  project to do so across two full investigation sessions — and the fix
  survived a full CapCut quit/relaunch.
  """

  alias __MODULE__

  @type canvas :: %{
          required(String.t()) => term()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          draft_type: String.t(),
          canvas_config: canvas(),
          fps: float(),
          duration: non_neg_integer(),
          tracks: [map()],
          materials: map(),
          keyframes: map(),
          version: integer(),
          new_version: String.t(),
          create_time: integer(),
          update_time: integer(),
          is_drop_frame_timecode: boolean(),
          color_space: integer(),
          config: map(),
          group_container: map() | nil,
          keyframe_graph_list: [map()],
          platform: map(),
          last_modified_platform: map(),
          mutable_config: map() | nil,
          cover: map() | nil,
          retouch_cover: map() | nil,
          extra_info: term(),
          relationships: [term()],
          mixed_track_mode_on: boolean(),
          render_index_track_mode_on: boolean(),
          free_render_index_mode_on: boolean(),
          static_cover_image_path: String.t(),
          source: String.t(),
          time_marks: term(),
          path: String.t(),
          lyrics_effects: [term()],
          uneven_animation_template_info: map(),
          smart_ads_info: map(),
          function_assistant_info: map()
        }

  @enforce_keys [:id, :name]
  defstruct id: nil,
            name: nil,
            draft_type: "video",
            canvas_config: %{
              "width" => 1920,
              "height" => 1080,
              "ratio" => "original",
              "background" => nil
            },
            fps: 30.0,
            duration: 0,
            tracks: [],
            materials: %{
              "ai_text_effects" => [],
              "ai_translates" => [],
              "audio_balances" => [],
              "audio_effects" => [],
              "audio_fades" => [],
              "audio_pannings" => [],
              "audio_pitch_shifts" => [],
              "audio_track_indexes" => [],
              "audios" => [],
              "beats" => [],
              "canvases" => [],
              "chromas" => [],
              "color_curves" => [],
              "common_mask" => [],
              "digital_human_model_dressing" => [],
              "digital_humans" => [],
              "drafts" => [],
              "effects" => [],
              "flowers" => [],
              "green_screens" => [],
              "handwrites" => [],
              "hsl" => [],
              "hsl_curves" => [],
              "images" => [],
              "log_color_wheels" => [],
              "loudnesses" => [],
              "manual_beautys" => [],
              "manual_deformations" => [],
              "material_animations" => [],
              "material_colors" => [],
              "multi_language_refs" => [],
              "placeholder_infos" => [],
              "placeholders" => [],
              "plugin_effects" => [],
              "primary_color_wheels" => [],
              "realtime_denoises" => [],
              "shapes" => [],
              "smart_crops" => [],
              "smart_relights" => [],
              "sound_channel_mappings" => [],
              "speeds" => [],
              "stickers" => [],
              "tail_leaders" => [],
              "text_templates" => [],
              "texts" => [],
              "time_marks" => [],
              "transitions" => [],
              "video_effects" => [],
              "video_radius" => [],
              "video_shadows" => [],
              "video_strokes" => [],
              "video_trackings" => [],
              "videos" => [],
              "vocal_beautifys" => [],
              "vocal_separations" => []
            },
            keyframes: %{
              "adjusts" => [],
              "audios" => [],
              "effects" => [],
              "filters" => [],
              "handwrites" => [],
              "stickers" => [],
              "texts" => [],
              "videos" => []
            },
            version: 360_000,
            new_version: "175.0.0",
            create_time: 0,
            update_time: 0,
            is_drop_frame_timecode: false,
            # -1 confirmed via a pristine (never-edited) CapCut-created
            # project's draft_info.json — not 0.
            color_space: -1,
            config: %{
              "video_mute" => false,
              "record_audio_last_index" => 1,
              "extract_audio_last_index" => 1,
              "original_sound_last_index" => 1,
              "subtitle_recognition_id" => "",
              "subtitle_taskinfo" => [],
              "lyrics_recognition_id" => "",
              "lyrics_taskinfo" => [],
              "subtitle_sync" => true,
              "lyrics_sync" => true,
              "voice_change_sync" => false,
              "sticker_max_index" => 1,
              "adjust_max_index" => 1,
              "material_save_mode" => 0,
              "export_range" => nil,
              "maintrack_adsorb" => true,
              "combination_max_index" => 1,
              "attachment_info" => [],
              "zoom_info_params" => nil,
              "system_font_list" => [],
              "multi_language_mode" => "none",
              "multi_language_main" => "none",
              "multi_language_current" => "none",
              "multi_language_list" => [],
              "subtitle_keywords_config" => nil,
              "use_float_render" => false
            },
            group_container: nil,
            keyframe_graph_list: [],
            platform: %{
              "os" => "mac",
              "os_version" => "",
              "app_id" => 359_289,
              "app_version" => "8.9.1",
              "app_source" => "cc",
              "device_id" => "",
              "hard_disk_id" => "",
              "mac_address" => ""
            },
            last_modified_platform: %{
              "os" => "mac",
              "os_version" => "",
              "app_id" => 359_289,
              "app_version" => "8.9.1",
              "app_source" => "cc",
              "device_id" => "",
              "hard_disk_id" => "",
              "mac_address" => ""
            },
            mutable_config: nil,
            cover: nil,
            retouch_cover: nil,
            extra_info: nil,
            relationships: [],
            mixed_track_mode_on: false,
            render_index_track_mode_on: true,
            free_render_index_mode_on: false,
            static_cover_image_path: "",
            source: "default",
            time_marks: nil,
            path: "",
            lyrics_effects: [],
            uneven_animation_template_info: %{
              "composition" => "",
              "content" => "",
              "order" => "",
              "sub_template_info_list" => []
            },
            smart_ads_info: %{
              "page_from" => "",
              "routine" => "",
              "draft_url" => ""
            },
            function_assistant_info: %{
              "smart_rec_applied" => false,
              "fixed_rec_applied" => false,
              "auto_adjust" => false,
              "auto_adjust_segid_list" => [],
              "color_correction" => false,
              "color_correction_segid_list" => [],
              "enhance_quality" => false,
              "smooth_slow_motion" => false,
              "deflicker_segid_list" => [],
              "video_noise_segid_list" => [],
              "enhance_quality_segid_list" => [],
              "smart_segid_list" => [],
              "retouch" => false,
              "retouch_segid_list" => [],
              "enhande_voice" => false,
              "enhance_voice_segid_list" => [],
              "audio_noise_segid_list" => [],
              "auto_caption" => false,
              "auto_caption_segid_list" => [],
              "auto_caption_template_id" => "",
              "caption_opt" => false,
              "caption_opt_segid_list" => [],
              "eye_correction" => false,
              "eye_correction_segid_list" => [],
              "normalize_loudness" => false,
              "normalize_loudness_segid_list" => [],
              "normalize_loudness_audio_denoise_segid_list" => [],
              "auto_adjust_fixed" => false,
              "auto_adjust_fixed_value" => 50.0,
              "color_correction_fixed" => false,
              "color_correction_fixed_value" => 50.0,
              "normalize_loudness_fixed" => false,
              "enhande_voice_fixed" => false,
              "retouch_fixed" => false,
              "enhance_quality_fixed" => false,
              "smooth_slow_motion_fixed" => false,
              "fps" => %{"num" => 0, "den" => 1}
            }

  @doc """
  Builds a fresh empty draft.

  Returns `{:error, msg}` for non-numeric `:fps`, non-integer `:width`/`:height`,
  and non-binary `:name` so the create_project boundary surfaces bad client
  input as a JSON-RPC error instead of crashing the store GenServer.

  ## Examples

      iex> {:ok, d} = CapcutMcp.CapCut.Draft.new(id: "abc", name: "My Clip", width: 1080, height: 1920, fps: 60)
      iex> d.canvas_config["width"]
      1080
      iex> d.fps
      60.0

      iex> CapcutMcp.CapCut.Draft.new(id: "abc", name: "My Clip", fps: "30")
      {:error, "fps: Expected number, got \\"30\\""}
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(opts) do
    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    width = Keyword.get(opts, :width, 1920)
    height = Keyword.get(opts, :height, 1080)
    fps_input = Keyword.get(opts, :fps, 30.0)

    with :ok <- check_binary(:name, name),
         :ok <- check_integer(:width, width),
         :ok <- check_integer(:height, height),
         {:ok, fps} <- coerce_fps(fps_input) do
      {:ok,
       %Draft{
         id: id,
         name: name,
         canvas_config: %{
           "width" => width,
           "height" => height,
           "ratio" => "original",
           "background" => nil
         },
         fps: fps
       }}
    end
  end

  defp check_binary(_, value) when is_binary(value), do: :ok

  defp check_binary(field, value),
    do: {:error, "#{field}: expected string, got #{inspect(value)}"}

  defp check_integer(_, value) when is_integer(value), do: :ok

  defp check_integer(field, value),
    do: {:error, "#{field}: expected integer, got #{inspect(value)}"}

  defp coerce_fps(v) when is_integer(v), do: {:ok, v * 1.0}
  defp coerce_fps(v) when is_float(v), do: {:ok, v}
  defp coerce_fps(v), do: {:error, "fps: Expected number, got #{inspect(v)}"}

  @doc "Serializes a `%Draft{}` into the string-keyed map shape CapCut expects on disk."
  @spec to_json(t()) :: map()
  def to_json(%Draft{} = d) do
    %{
      "id" => d.id,
      "name" => d.name,
      "draft_type" => d.draft_type,
      "canvas_config" => d.canvas_config,
      "fps" => d.fps,
      "duration" => d.duration,
      "tracks" => d.tracks,
      "materials" => d.materials,
      "keyframes" => d.keyframes,
      "version" => d.version,
      "new_version" => d.new_version,
      "create_time" => d.create_time,
      "update_time" => d.update_time,
      "is_drop_frame_timecode" => d.is_drop_frame_timecode,
      "color_space" => d.color_space,
      "config" => d.config,
      "group_container" => d.group_container,
      "keyframe_graph_list" => d.keyframe_graph_list,
      "platform" => d.platform,
      "last_modified_platform" => d.last_modified_platform,
      "mutable_config" => d.mutable_config,
      "cover" => d.cover,
      "retouch_cover" => d.retouch_cover,
      "extra_info" => d.extra_info,
      "relationships" => d.relationships,
      "mixed_track_mode_on" => d.mixed_track_mode_on,
      "render_index_track_mode_on" => d.render_index_track_mode_on,
      "free_render_index_mode_on" => d.free_render_index_mode_on,
      "static_cover_image_path" => d.static_cover_image_path,
      "source" => d.source,
      "time_marks" => d.time_marks,
      "path" => d.path,
      "lyrics_effects" => d.lyrics_effects,
      "uneven_animation_template_info" => d.uneven_animation_template_info,
      "smart_ads_info" => d.smart_ads_info,
      "function_assistant_info" => d.function_assistant_info
    }
  end

  defimpl Jason.Encoder do
    def encode(draft, opts), do: Jason.Encode.map(@for.to_json(draft), opts)
  end
end
