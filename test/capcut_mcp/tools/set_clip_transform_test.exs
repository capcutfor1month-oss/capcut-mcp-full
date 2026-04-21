defmodule CapcutMcp.Tools.SetClipTransformTest do
  @moduledoc """
  Focused coverage for the `SetClipTransform` tool with an emphasis on the
  D16-F2 input-validation boundary: stringified numeric inputs must surface as
  `{:error, _}` tuples, not as raised `FunctionClauseError`.
  """

  use ExUnit.Case, async: false

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.SetClipTransform

  @project_id "XFORM-TEST-001"

  setup %{tmp_dir: tmp} do
    project_path = Path.join(tmp, "xform_test_project")
    File.mkdir_p!(project_path)
    File.write!(Path.join(project_path, "draft_content.json"), Jason.encode!(seed_draft()))

    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => @project_id,
          "draft_name" => "Transform Test",
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
    test "required fields are project_id + clip_id" do
      defn = SetClipTransform.definition()
      assert defn["name"] == "set_clip_transform"
      assert defn["inputSchema"]["required"] == ["project_id", "clip_id"]
    end
  end

  describe "execute/1 — happy path" do
    @tag :tmp_dir
    test "updates transform.x and scale.x on a video segment", %{project_id: id} do
      assert {:ok, msg} =
               SetClipTransform.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "x" => 0.5,
                 "scale_x" => 2
               })

      assert msg =~ "Transform updated"

      {:ok, draft} = ProjectStore.get_project(id)
      [%{"segments" => [seg | _]} | _] = draft["tracks"]
      assert seg["clip"]["transform"]["x"] === 0.5
      assert seg["clip"]["scale"]["x"] === 2.0
    end
  end

  describe "execute/1 — D16-F2 input validation" do
    @tag :tmp_dir
    test "stringified x returns an error instead of raising", %{project_id: id} do
      assert {:error, msg} =
               SetClipTransform.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "x" => "0.5"
               })

      assert msg =~ "x"
      assert msg =~ "Expected number"
    end

    @tag :tmp_dir
    test "stringified rotation returns an error instead of raising", %{project_id: id} do
      assert {:error, msg} =
               SetClipTransform.execute(%{
                 "project_id" => id,
                 "clip_id" => "video-seg-001",
                 "rotation" => "45"
               })

      assert msg =~ "rotation"
      assert msg =~ "Expected number"
    end

    @tag :tmp_dir
    test "returns error for missing required args" do
      assert {:error, msg} = SetClipTransform.execute(%{})
      assert msg =~ "project_id"
      assert msg =~ "clip_id"
    end
  end

  defp seed_draft do
    %{
      "id" => @project_id,
      "name" => "Transform Test",
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
                "rotation" => 0.0,
                "transform" => %{"x" => 0.0, "y" => 0.0},
                "scale" => %{"x" => 1.0, "y" => 1.0}
              }
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
