defmodule CapcutMcp.Tools.SetClipBlendModeTest do
  @moduledoc """
  Exercises the full SetClipBlendMode code path against a real-but-fake CapCut
  installation: a temp directory hosts both the draft project **and** a
  synthetic `MixMode.json`, and `CAPCUT_APPS_PATH` is pointed at that fake
  installation so `BlendModes.find_mode/1` resolves against it.

  Covers the insert-new-mix-mode path, the update-existing-mix-mode path, the
  non-video-segment guard, unknown-mode lookup failures, segment-not-found
  errors, and the missing-required-arg formatter.

  `async: false` because we mutate process-global env vars and the blend-mode
  ETS cache.
  """

  use ExUnit.Case, async: false

  alias CapcutMcp.CapCut.{BlendModes, ProjectStore}
  alias CapcutMcp.Tools.SetClipBlendMode

  @project_id "BLEND-TEST-001"

  setup %{tmp_dir: tmp} do
    previous_apps_path = System.get_env("CAPCUT_APPS_PATH")
    apps_root = Path.join(tmp, "capcut_apps")
    mix_mode_dir = Path.join([apps_root, "9.9.9", "Resources", "MixMode"])
    File.mkdir_p!(mix_mode_dir)

    File.write!(
      Path.join(mix_mode_dir, "MixMode.json"),
      Jason.encode!(%{
        "resourceList" => [
          %{
            "nameId" => "soft_light",
            "effectId" => "fx-soft-light",
            "resourceId" => "res-soft-light",
            "path" => "soft-light"
          },
          %{
            "nameId" => "glare_pc",
            "effectId" => "fx-screen",
            "resourceId" => "res-screen",
            "path" => "screen"
          }
        ]
      })
    )

    System.put_env("CAPCUT_APPS_PATH", apps_root)
    BlendModes.invalidate_cache()

    on_exit(fn ->
      BlendModes.invalidate_cache()

      case previous_apps_path do
        nil -> System.delete_env("CAPCUT_APPS_PATH")
        value -> System.put_env("CAPCUT_APPS_PATH", value)
      end
    end)

    project_path = Path.join(tmp, "blend_test_project")
    File.mkdir_p!(project_path)

    draft = seed_draft(@project_id)
    File.write!(Path.join(project_path, "draft_content.json"), Jason.encode!(draft))

    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => @project_id,
          "draft_name" => "Blend Test",
          "draft_fold_path" => project_path,
          "draft_json_file" => Path.join(project_path, "draft_content.json"),
          "tm_draft_modified" => 1_750_000_000_000_000,
          "tm_duration" => 5_000_000
        }
      ],
      "draft_ids" => 1,
      "root_path" => tmp
    }

    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))

    start_supervised!({ProjectStore, [root_path: tmp]})
    %{project_id: @project_id}
  end

  describe "definition/0" do
    @tag :tmp_dir
    test "advertises required fields and tool name" do
      defn = SetClipBlendMode.definition()
      assert defn["name"] == "set_clip_blend_mode"
      assert defn["inputSchema"]["required"] == ["project_id", "clip_id", "mode"]
    end
  end

  describe "execute/1 — happy path" do
    @tag :tmp_dir
    test "adds a new mix_mode effect and links it via extra_material_refs", %{project_id: id} do
      assert {:ok, msg} =
               SetClipBlendMode.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "mode" => "soft_light",
                 "value" => 0.75
               })

      assert msg =~ "Soft Light"
      assert msg =~ "soft_light"
      assert msg =~ "0.75"

      {:ok, draft} = ProjectStore.get_project(id)
      effects = draft["materials"]["effects"]
      assert [effect] = effects
      assert effect["type"] == "mix_mode"
      assert effect["effect_id"] == "fx-soft-light"
      assert effect["name"] == "Soft Light"
      assert effect["value"] == 0.75

      seg = find_video_segment(draft)
      assert effect["id"] in seg["extra_material_refs"]
    end

    @tag :tmp_dir
    test "defaults value to 1.0 when not provided", %{project_id: id} do
      assert {:ok, msg} =
               SetClipBlendMode.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "mode" => "glare_pc"
               })

      assert msg =~ "1.0"
      {:ok, draft} = ProjectStore.get_project(id)
      [effect] = draft["materials"]["effects"]
      assert effect["value"] == 1.0
      assert effect["effect_id"] == "fx-screen"
    end

    @tag :tmp_dir
    test "coerces integer value to float", %{project_id: id} do
      assert {:ok, _} =
               SetClipBlendMode.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "mode" => "soft_light",
                 "value" => 1
               })

      {:ok, draft} = ProjectStore.get_project(id)
      [effect] = draft["materials"]["effects"]
      assert effect["value"] === 1.0
    end

    @tag :tmp_dir
    test "resolves blend modes case-insensitively by display label", %{project_id: id} do
      assert {:ok, msg} =
               SetClipBlendMode.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "mode" => "screen"
               })

      assert msg =~ "Screen"
      {:ok, draft} = ProjectStore.get_project(id)
      [effect] = draft["materials"]["effects"]
      assert effect["effect_id"] == "fx-screen"
    end
  end

  describe "execute/1 — update-existing path" do
    @tag :tmp_dir
    test "reuses the same effect id when blend mode is changed twice", %{project_id: id} do
      {:ok, _} =
        SetClipBlendMode.execute(%{
          "project_id" => id,
          "clip_id" => "video-seg-001",
          "mode" => "soft_light",
          "value" => 0.5
        })

      {:ok, draft_after_first} = ProjectStore.get_project(id)
      [first_effect] = draft_after_first["materials"]["effects"]

      {:ok, _} =
        SetClipBlendMode.execute(%{
          "project_id" => id,
          "clip_id" => "video-seg-001",
          "mode" => "glare_pc",
          "value" => 0.9
        })

      {:ok, draft_after_second} = ProjectStore.get_project(id)
      effects = draft_after_second["materials"]["effects"]

      assert length(effects) == 1
      [second_effect] = effects
      assert second_effect["id"] == first_effect["id"]
      assert second_effect["effect_id"] == "fx-screen"
      assert second_effect["name"] == "Screen"
      assert second_effect["value"] == 0.9

      seg = find_video_segment(draft_after_second)
      refs = seg["extra_material_refs"]
      assert first_effect["id"] in refs
      assert length(refs) == 1
    end
  end

  describe "execute/1 — errors" do
    @tag :tmp_dir
    test "rejects unknown blend mode with available list", %{project_id: id} do
      assert {:error, msg} =
               SetClipBlendMode.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "mode" => "moonbeam"
               })

      assert msg =~ "Unknown blend mode"
      assert msg =~ "soft_light"
      assert msg =~ "glare_pc"
    end

    @tag :tmp_dir
    test "rejects non-video segment (no clip map)", %{project_id: id} do
      assert {:error, msg} =
               SetClipBlendMode.execute(%{
                 "project_id" => id,
                 "clip_id" => "text-seg-001",
                 "mode" => "soft_light"
               })

      assert msg =~ "only video segments"
    end

    @tag :tmp_dir
    test "returns error for unknown clip id", %{project_id: id} do
      assert {:error, msg} =
               SetClipBlendMode.execute(%{
                 "project_id" => id,
                 "clip_id" => "does-not-exist",
                 "mode" => "soft_light"
               })

      assert msg =~ "Segment not found"
    end

    @tag :tmp_dir
    test "returns error for missing required args" do
      assert {:error, msg} = SetClipBlendMode.execute(%{})
      assert msg =~ "project_id"
      assert msg =~ "clip_id"
      assert msg =~ "mode"
    end

    @tag :tmp_dir
    test "returns error for unknown project" do
      assert {:error, _} =
               SetClipBlendMode.execute(%{
                 "project_id" => "NOPE",
                 "clip_id" => "video-seg-001",
                 "mode" => "soft_light"
               })
    end

    @tag :tmp_dir
    test "stringified value returns an error instead of raising", %{project_id: id} do
      assert {:error, msg} =
               SetClipBlendMode.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "mode" => "soft_light",
                 "value" => "0.8"
               })

      assert msg =~ "Expected number"
      assert msg =~ ~s("0.8")
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp find_video_segment(draft) do
    draft["tracks"]
    |> Enum.flat_map(& &1["segments"])
    |> Enum.find(&(&1["id"] == "video-seg-001"))
  end

  defp seed_draft(id) do
    %{
      "id" => id,
      "name" => "Blend Test",
      "fps" => 30.0,
      "duration" => 5_000_000,
      "new_version" => "163.0.0",
      "canvas_config" => %{
        "width" => 1920,
        "height" => 1080,
        "ratio" => "original",
        "background" => nil
      },
      "tracks" => [
        %{
          "id" => "track-video",
          "type" => "video",
          "segments" => [
            %{
              "id" => "video-seg-001",
              "material_id" => "mat-video",
              "target_timerange" => %{"start" => 0, "duration" => 3_000_000},
              "source_timerange" => %{"start" => 0, "duration" => 3_000_000},
              "clip" => %{
                "alpha" => 1.0,
                "transform" => %{"x" => 0.0, "y" => 0.0},
                "scale" => %{"x" => 1.0, "y" => 1.0}
              }
            }
          ]
        },
        %{
          "id" => "track-text",
          "type" => "text",
          "segments" => [
            %{
              "id" => "text-seg-001",
              "material_id" => "mat-text",
              "target_timerange" => %{"start" => 0, "duration" => 2_000_000},
              "source_timerange" => %{"start" => 0, "duration" => 2_000_000}
            }
          ]
        }
      ],
      "materials" => %{
        "videos" => [],
        "texts" => [],
        "audios" => [],
        "images" => [],
        "effects" => [],
        "transitions" => [],
        "stickers" => [],
        "filters" => []
      }
    }
  end
end
