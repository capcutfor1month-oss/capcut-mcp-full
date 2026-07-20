defmodule CapcutMcp.Tools.SetClipKeyframeTest do
  use ExUnit.Case, async: false

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.SetClipKeyframe

  @project_id "KF-TEST-001"

  setup %{tmp_dir: tmp} do
    project_path = Path.join(tmp, "kf_test_project")
    File.mkdir_p!(project_path)
    File.write!(Path.join(project_path, "draft_content.json"), Jason.encode!(seed_draft()))

    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => @project_id,
          "draft_name" => "Keyframe Test",
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
      defn = SetClipKeyframe.definition()
      assert defn["name"] == "set_clip_keyframe"

      assert defn["inputSchema"]["required"] == [
               "project_id",
               "clip_id",
               "property",
               "time_offset_ms",
               "value"
             ]
    end
  end

  describe "execute/1 — happy path" do
    @tag :tmp_dir
    test "adds a single keyframe as a new property group", %{project_id: id} do
      assert {:ok, msg} =
               SetClipKeyframe.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "property" => "alpha",
                 "time_offset_ms" => 0,
                 "value" => 0.0
               })

      assert msg =~ "Keyframe added"

      {:ok, draft} = ProjectStore.get_project(id)
      [%{"segments" => [seg | _]} | _] = draft["tracks"]
      [kf_list] = seg["common_keyframes"]

      assert kf_list["property_type"] == "KFTypeAlpha"
      assert [keyframe] = kf_list["keyframe_list"]
      assert keyframe["time_offset"] == 0
      assert keyframe["values"] == [0.0]
      assert keyframe["curveType"] == "Line"
    end

    @tag :tmp_dir
    test "second call for the same property appends to the existing group, sorted by time", %{
      project_id: id
    } do
      SetClipKeyframe.execute(%{
        "project_id" => id,
        "clip_id" => "video-seg-001",
        "property" => "alpha",
        "time_offset_ms" => 500,
        "value" => 1.0
      })

      assert {:ok, _} =
               SetClipKeyframe.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "property" => "alpha",
                 "time_offset_ms" => 0,
                 "value" => 0.0
               })

      {:ok, draft} = ProjectStore.get_project(id)
      [%{"segments" => [seg | _]} | _] = draft["tracks"]

      assert [kf_list] = seg["common_keyframes"]
      assert Enum.map(kf_list["keyframe_list"], & &1["time_offset"]) == [0, 500_000]
    end

    @tag :tmp_dir
    test "different properties create separate groups", %{project_id: id} do
      SetClipKeyframe.execute(%{
        "project_id" => id,
        "clip_id" => "video-seg-001",
        "property" => "alpha",
        "time_offset_ms" => 0,
        "value" => 0.0
      })

      SetClipKeyframe.execute(%{
        "project_id" => id,
        "clip_id" => "video-seg-001",
        "property" => "position_x",
        "time_offset_ms" => 0,
        "value" => -0.5
      })

      {:ok, draft} = ProjectStore.get_project(id)
      [%{"segments" => [seg | _]} | _] = draft["tracks"]
      property_types = seg["common_keyframes"] |> Enum.map(& &1["property_type"]) |> Enum.sort()

      assert property_types == ["KFTypeAlpha", "KFTypePositionX"]
    end

    @tag :tmp_dir
    test "volume keyframe works on a segment without a clip object (audio)", %{project_id: id} do
      assert {:ok, _} =
               SetClipKeyframe.execute(%{
                 "project_id" => id,
                 "clip_id" => "audio-seg-001",
                 "property" => "volume",
                 "time_offset_ms" => 0,
                 "value" => 0.5
               })
    end
  end

  describe "execute/1 — validation" do
    @tag :tmp_dir
    test "unknown property returns a helpful error", %{project_id: id} do
      assert {:error, msg} =
               SetClipKeyframe.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "property" => "bogus",
                 "time_offset_ms" => 0,
                 "value" => 1.0
               })

      assert msg =~ "Unknown property"
      assert msg =~ "alpha"
    end

    @tag :tmp_dir
    test "negative time_offset_ms is rejected", %{project_id: id} do
      assert {:error, msg} =
               SetClipKeyframe.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "property" => "alpha",
                 "time_offset_ms" => -1,
                 "value" => 1.0
               })

      assert msg =~ "time_offset_ms"
    end

    @tag :tmp_dir
    test "non-numeric value is rejected", %{project_id: id} do
      assert {:error, msg} =
               SetClipKeyframe.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "property" => "alpha",
                 "time_offset_ms" => 0,
                 "value" => "1.0"
               })

      assert msg =~ "Expected number"
    end

    @tag :tmp_dir
    test "returns error for missing required args" do
      assert {:error, msg} = SetClipKeyframe.execute(%{})
      assert msg =~ "project_id"
      assert msg =~ "clip_id"
    end

    @tag :tmp_dir
    test "position keyframe on an audio-only segment (no clip) is rejected", %{project_id: id} do
      assert {:error, msg} =
               SetClipKeyframe.execute(%{
                 "project_id" => id,
                 "clip_id" => "audio-seg-001",
                 "property" => "position_x",
                 "time_offset_ms" => 0,
                 "value" => 0.0
               })

      assert msg =~ "no clip object"
    end
  end

  defp seed_draft do
    %{
      "id" => @project_id,
      "name" => "Keyframe Test",
      "fps" => 30.0,
      "duration" => 3_000_000,
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
                "rotation" => 0.0,
                "transform" => %{"x" => 0.0, "y" => 0.0},
                "scale" => %{"x" => 1.0, "y" => 1.0}
              }
            }
          ]
        },
        %{
          "id" => "track-audio",
          "type" => "audio",
          "segments" => [
            %{
              "id" => "audio-seg-001",
              "material_id" => "mat-audio",
              "target_timerange" => %{"start" => 0, "duration" => 3_000_000},
              "source_timerange" => %{"start" => 0, "duration" => 3_000_000}
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
