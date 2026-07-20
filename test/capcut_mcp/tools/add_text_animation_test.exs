defmodule CapcutMcp.Tools.AddTextAnimationTest do
  use ExUnit.Case, async: false

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.AddTextAnimation

  @project_id "ANIM-TEST-001"

  setup %{tmp_dir: tmp} do
    project_path = Path.join(tmp, "anim_test_project")
    File.mkdir_p!(project_path)
    File.write!(Path.join(project_path, "draft_content.json"), Jason.encode!(seed_draft()))

    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => @project_id,
          "draft_name" => "Animation Test",
          "draft_fold_path" => project_path,
          "draft_json_file" => Path.join(project_path, "draft_content.json"),
          "tm_draft_modified" => 1_750_000_000_000_000,
          "tm_duration" => 3_000_000
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
    test "required fields" do
      defn = AddTextAnimation.definition()
      assert defn["name"] == "add_text_animation"
      assert defn["inputSchema"]["required"] == ["project_id", "clip_id", "animation"]
    end
  end

  describe "execute/1 — happy path" do
    @tag :tmp_dir
    test "adds a fade_in intro animation with default duration", %{project_id: id} do
      assert {:ok, msg} =
               AddTextAnimation.execute(%{
                 "project_id" => id,
                 "clip_id" => "text-seg-001",
                 "animation" => "fade_in"
               })

      assert msg =~ "in"

      {:ok, draft} = ProjectStore.get_project(id)
      [%{"segments" => [seg | _]} | _] = draft["tracks"]
      [animation_material] = draft["materials"]["animations"]

      assert animation_material["id"] in seg["extra_material_refs"]
      assert animation_material["type"] == "sticker_animation"
      assert [entry] = animation_material["animations"]
      assert entry["type"] == "in"
      assert entry["start"] == 0
      assert entry["duration"] == 500_000
    end

    @tag :tmp_dir
    test "fade_out (outro) starts near the segment's end, not at 0", %{project_id: id} do
      assert {:ok, _} =
               AddTextAnimation.execute(%{
                 "project_id" => id,
                 "clip_id" => "text-seg-001",
                 "animation" => "fade_out"
               })

      {:ok, draft} = ProjectStore.get_project(id)
      [animation_material] = draft["materials"]["animations"]
      [entry] = animation_material["animations"]

      assert entry["type"] == "out"
      # segment duration is 3_000_000us; fade_out default duration is 1_600_000us
      assert entry["start"] == 3_000_000 - 1_600_000
      assert entry["duration"] == 1_600_000
    end

    @tag :tmp_dir
    test "duration_ms override replaces the catalog default", %{project_id: id} do
      assert {:ok, _} =
               AddTextAnimation.execute(%{
                 "project_id" => id,
                 "clip_id" => "text-seg-001",
                 "animation" => "fade_in",
                 "duration_ms" => 1200
               })

      {:ok, draft} = ProjectStore.get_project(id)
      [animation_material] = draft["materials"]["animations"]
      [entry] = animation_material["animations"]

      assert entry["duration"] == 1_200_000
    end

    @tag :tmp_dir
    test "an in and an out animation can coexist on the same segment", %{project_id: id} do
      AddTextAnimation.execute(%{
        "project_id" => id,
        "clip_id" => "text-seg-001",
        "animation" => "fade_in"
      })

      assert {:ok, _} =
               AddTextAnimation.execute(%{
                 "project_id" => id,
                 "clip_id" => "text-seg-001",
                 "animation" => "fade_out"
               })

      {:ok, draft} = ProjectStore.get_project(id)
      assert length(draft["materials"]["animations"]) == 2
    end
  end

  describe "execute/1 — validation" do
    @tag :tmp_dir
    test "unknown animation name returns a helpful error", %{project_id: id} do
      assert {:error, msg} =
               AddTextAnimation.execute(%{
                 "project_id" => id,
                 "clip_id" => "text-seg-001",
                 "animation" => "bogus_wipe"
               })

      assert msg =~ "Unknown animation"
      assert msg =~ "fade_in"
    end

    @tag :tmp_dir
    test "adding a second 'in' animation to the same segment is rejected", %{project_id: id} do
      AddTextAnimation.execute(%{
        "project_id" => id,
        "clip_id" => "text-seg-001",
        "animation" => "fade_in"
      })

      assert {:error, msg} =
               AddTextAnimation.execute(%{
                 "project_id" => id,
                 "clip_id" => "text-seg-001",
                 "animation" => "slide_up"
               })

      assert msg =~ "already has an in animation"
    end

    @tag :tmp_dir
    test "zero duration_ms override is rejected", %{project_id: id} do
      assert {:error, msg} =
               AddTextAnimation.execute(%{
                 "project_id" => id,
                 "clip_id" => "text-seg-001",
                 "animation" => "fade_in",
                 "duration_ms" => 0
               })

      assert msg =~ "duration_ms"
    end

    @tag :tmp_dir
    test "returns error for missing required args" do
      assert {:error, msg} = AddTextAnimation.execute(%{})
      assert msg =~ "project_id"
      assert msg =~ "animation"
    end
  end

  defp seed_draft do
    %{
      "id" => @project_id,
      "name" => "Animation Test",
      "fps" => 30.0,
      "duration" => 3_000_000,
      "new_version" => "163.0.0",
      "canvas_config" => %{
        "width" => 1080,
        "height" => 1920,
        "ratio" => "original",
        "background" => nil
      },
      "tracks" => [
        %{
          "id" => "track-text",
          "type" => "text",
          "segments" => [
            %{
              "id" => "text-seg-001",
              "material_id" => "mat-text",
              "target_timerange" => %{"start" => 0, "duration" => 3_000_000},
              "source_timerange" => %{"start" => 0, "duration" => 3_000_000},
              "extra_material_refs" => []
            }
          ]
        }
      ],
      "materials" => %{
        "videos" => [],
        "texts" => [
          %{"id" => "mat-text", "type" => "text", "content" => "Hello"}
        ],
        "audios" => [],
        "images" => [],
        "effects" => [],
        "transitions" => [],
        "stickers" => [],
        "filters" => [],
        "animations" => []
      }
    }
  end
end
