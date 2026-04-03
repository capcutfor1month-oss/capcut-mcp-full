defmodule CapcutMcp.ToolsTest do
  use ExUnit.Case

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.{ListProjects, GetProject, GetTimeline}

  setup %{tmp_dir: tmp} do
    project_id = "TOOL-TEST-001"
    project_path = Path.join(tmp, "tool_test_project")
    File.mkdir_p!(project_path)

    draft = %{
      "id" => project_id,
      "name" => "Tool Test",
      "fps" => 30.0,
      "duration" => 10_000_000,
      "new_version" => "163.0.0",
      "canvas_config" => %{"width" => 1920, "height" => 1080, "ratio" => "original", "background" => nil},
      "tracks" => [
        %{
          "id" => "track-001",
          "type" => "text",
          "segments" => [
            %{
              "id" => "seg-001",
              "material_id" => "mat-001",
              "target_timerange" => %{"start" => 0, "duration" => 3_000_000},
              "source_timerange" => %{"start" => 0, "duration" => 3_000_000}
            }
          ]
        }
      ],
      "materials" => %{"videos" => [], "texts" => [], "audios" => [], "images" => [], "effects" => [], "transitions" => [], "stickers" => [], "filters" => []}
    }
    File.write!(Path.join(project_path, "draft_content.json"), Jason.encode!(draft))

    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => project_id,
          "draft_name" => "Tool Test",
          "draft_fold_path" => project_path,
          "draft_json_file" => Path.join(project_path, "draft_content.json"),
          "tm_draft_modified" => 1_750_000_000_000_000,
          "tm_duration" => 10_000_000
        }
      ],
      "draft_ids" => 1,
      "root_path" => tmp
    }
    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))

    start_supervised!({ProjectStore, [root_path: tmp]})
    %{project_id: project_id}
  end

  @tag :tmp_dir
  test "ListProjects.definition returns correct tool name" do
    assert %{"name" => "list_projects"} = ListProjects.definition()
  end

  @tag :tmp_dir
  test "ListProjects.execute returns project list" do
    assert {:ok, text} = ListProjects.execute(%{})
    assert text =~ "Tool Test"
  end

  @tag :tmp_dir
  test "GetProject.execute returns project info", %{project_id: id} do
    assert {:ok, text} = GetProject.execute(%{"project_id" => id})
    assert text =~ "1920"
    assert text =~ "30"
  end

  @tag :tmp_dir
  test "GetProject.execute returns error for unknown id" do
    assert {:error, msg} = GetProject.execute(%{"project_id" => "NOPE"})
    assert msg =~ "not found"
  end

  @tag :tmp_dir
  test "GetTimeline.execute returns track info", %{project_id: id} do
    assert {:ok, text} = GetTimeline.execute(%{"project_id" => id})
    assert text =~ "text"
    assert text =~ "seg-001"
  end

  @tag :tmp_dir
  test "GetTimeline.execute returns error for unknown id" do
    assert {:error, _} = GetTimeline.execute(%{"project_id" => "NONEXISTENT"})
  end

  alias CapcutMcp.Tools.{CreateProject, AddText}

  @tag :tmp_dir
  test "CreateProject.execute creates a project and returns an ID" do
    assert {:ok, id} = CreateProject.execute(%{"name" => "Brand New"})
    assert is_binary(id)
    assert {:ok, _draft} = ProjectStore.get_project(id)
  end

  @tag :tmp_dir
  test "CreateProject.execute respects width/height/fps params" do
    assert {:ok, id} = CreateProject.execute(%{"name" => "Vertical", "width" => 1080, "height" => 1920, "fps" => 60})
    assert {:ok, draft} = ProjectStore.get_project(id)
    assert draft["canvas_config"]["width"] == 1080
    assert draft["canvas_config"]["height"] == 1920
    assert draft["fps"] == 60.0
  end

  @tag :tmp_dir
  test "AddText.execute adds a text track segment", %{project_id: id} do
    assert {:ok, msg} = AddText.execute(%{
      "project_id" => id,
      "content" => "Hello World",
      "start_ms" => 0,
      "duration_ms" => 2000
    })
    assert msg =~ "Text added"
    {:ok, draft} = ProjectStore.get_project(id)
    text_tracks = Enum.filter(draft["tracks"], fn t -> t["type"] == "text" end)
    assert length(text_tracks) > 0
    segments = hd(text_tracks)["segments"]
    assert length(segments) > 0
  end

  @tag :tmp_dir
  test "AddText.execute returns error for unknown project" do
    assert {:error, msg} = AddText.execute(%{"project_id" => "NOPE", "content" => "x", "start_ms" => 0, "duration_ms" => 1000})
    assert msg =~ "not found"
  end

  alias CapcutMcp.Tools.{AddClip, RemoveClip}

  @tag :tmp_dir
  test "AddClip.execute adds a video segment", %{project_id: id} do
    assert {:ok, msg} = AddClip.execute(%{
      "project_id" => id,
      "file_path" => "C:/Users/tspor/Videos/test.mp4",
      "start_ms" => 0,
      "duration_ms" => 5000
    })
    assert msg =~ "Clip added"
    {:ok, draft} = ProjectStore.get_project(id)
    video_tracks = Enum.filter(draft["tracks"], fn t -> t["type"] == "video" end)
    assert length(video_tracks) > 0
  end

  @tag :tmp_dir
  test "AddClip.execute detects audio files by extension", %{project_id: id} do
    assert {:ok, msg} = AddClip.execute(%{
      "project_id" => id,
      "file_path" => "C:/Users/tspor/Music/track.mp3",
      "start_ms" => 0,
      "duration_ms" => 3000
    })
    assert msg =~ "Clip added"
    {:ok, draft} = ProjectStore.get_project(id)
    audio_tracks = Enum.filter(draft["tracks"], fn t -> t["type"] == "audio" end)
    assert length(audio_tracks) > 0
  end

  @tag :tmp_dir
  test "RemoveClip.execute removes a segment by ID", %{project_id: id} do
    # Load into cache first
    {:ok, _} = ProjectStore.get_project(id)
    assert :ok = ProjectStore.update_project(id, %{
      "id" => id,
      "tracks" => [%{"id" => "t1", "type" => "text", "segments" => [%{"id" => "seg-to-remove", "material_id" => "m1", "target_timerange" => %{"start" => 0, "duration" => 1000}}]}],
      "materials" => %{}
    })
    assert {:ok, _} = RemoveClip.execute(%{"project_id" => id, "clip_id" => "seg-to-remove"})
    {:ok, draft} = ProjectStore.get_project(id)
    all_segments = draft["tracks"] |> Enum.flat_map(fn t -> t["segments"] || [] end)
    refute Enum.any?(all_segments, fn s -> s["id"] == "seg-to-remove" end)
  end

  @tag :tmp_dir
  test "RemoveClip.execute returns error for unknown clip ID", %{project_id: id} do
    assert {:error, msg} = RemoveClip.execute(%{"project_id" => id, "clip_id" => "NOPE"})
    assert msg =~ "not found"
  end
end
