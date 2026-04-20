defmodule CapcutMcp.ToolsTest do
  use ExUnit.Case

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.{GetProject, GetTimeline, ListProjects}

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
      "canvas_config" => %{
        "width" => 1920,
        "height" => 1080,
        "ratio" => "original",
        "background" => nil
      },
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

  alias CapcutMcp.Tools.{AddText, CreateProject}

  @tag :tmp_dir
  test "CreateProject.execute creates a project and returns an ID" do
    assert {:ok, id} = CreateProject.execute(%{"name" => "Brand New"})
    assert is_binary(id)
    assert {:ok, _draft} = ProjectStore.get_project(id)
  end

  @tag :tmp_dir
  test "CreateProject.execute uses defaults when name is the only arg" do
    assert {:ok, id} = CreateProject.execute(%{"name" => "Defaults"})
    assert {:ok, draft} = ProjectStore.get_project(id)
    assert draft["canvas_config"]["width"] == 1920
    assert draft["canvas_config"]["height"] == 1080
    assert draft["fps"] == 30.0
  end

  @tag :tmp_dir
  test "CreateProject.execute substitutes 'Untitled_N' when name has no safe characters",
       %{project_id: _id} do
    assert {:ok, id} = CreateProject.execute(%{"name" => "!!!"})
    assert is_binary(id)
    assert {:ok, draft} = ProjectStore.get_project(id)
    assert draft["name"] == "!!!"
  end

  @tag :tmp_dir
  test "CreateProject.execute returns formatted error when directory cannot be created",
       %{tmp_dir: tmp} do
    # Place a plain file where the sanitized project directory would go —
    # mkdir_p then fails with :enotdir / :eexist and the tool surfaces it.
    conflict = Path.join(tmp, "Conflict_Project")
    File.write!(conflict, "blocking")

    assert {:error, msg} = CreateProject.execute(%{"name" => "Conflict Project"})
    assert msg =~ "Failed to create project"
  end

  @tag :tmp_dir
  test "CreateProject.execute respects width/height/fps params" do
    assert {:ok, id} =
             CreateProject.execute(%{
               "name" => "Vertical",
               "width" => 1080,
               "height" => 1920,
               "fps" => 60
             })

    assert {:ok, draft} = ProjectStore.get_project(id)
    assert draft["canvas_config"]["width"] == 1080
    assert draft["canvas_config"]["height"] == 1920
    assert draft["fps"] == 60.0
  end

  @tag :tmp_dir
  test "AddText.execute adds a text track segment", %{project_id: id} do
    assert {:ok, msg} =
             AddText.execute(%{
               "project_id" => id,
               "content" => "Hello World",
               "start_ms" => 0,
               "duration_ms" => 2000
             })

    assert msg =~ "Text added"
    {:ok, draft} = ProjectStore.get_project(id)
    text_tracks = Enum.filter(draft["tracks"], fn t -> t["type"] == "text" end)
    assert text_tracks != []
    segments = hd(text_tracks)["segments"]
    assert segments != []
  end

  @tag :tmp_dir
  test "AddText.execute returns error for unknown project" do
    assert {:error, msg} =
             AddText.execute(%{
               "project_id" => "NOPE",
               "content" => "x",
               "start_ms" => 0,
               "duration_ms" => 1000
             })

    assert msg =~ "not found"
  end

  @tag :tmp_dir
  test "AddText.execute rejects negative track_index", %{project_id: id} do
    assert {:error, msg} =
             AddText.execute(%{
               "project_id" => id,
               "content" => "Hello World",
               "start_ms" => 0,
               "duration_ms" => 2000,
               "track_index" => -1
             })

    assert msg =~ "Invalid track index"

    {:ok, draft} = ProjectStore.get_project(id)
    text_track = Enum.find(draft["tracks"], fn track -> track["id"] == "track-001" end)
    assert length(text_track["segments"]) == 1
  end

  @tag :tmp_dir
  test "AddText.execute rejects negative start_ms", %{project_id: id} do
    assert {:error, msg} =
             AddText.execute(%{
               "project_id" => id,
               "content" => "Hello World",
               "start_ms" => -1,
               "duration_ms" => 2000
             })

    assert msg =~ "Invalid start_ms"

    {:ok, draft} = ProjectStore.get_project(id)
    text_track = Enum.find(draft["tracks"], fn track -> track["id"] == "track-001" end)
    assert length(text_track["segments"]) == 1
  end

  @tag :tmp_dir
  test "AddText.execute rejects non-positive duration_ms", %{project_id: id} do
    assert {:error, msg} =
             AddText.execute(%{
               "project_id" => id,
               "content" => "Hello World",
               "start_ms" => 0,
               "duration_ms" => 0
             })

    assert msg =~ "Invalid duration_ms"

    {:ok, draft} = ProjectStore.get_project(id)
    text_track = Enum.find(draft["tracks"], fn track -> track["id"] == "track-001" end)
    assert length(text_track["segments"]) == 1
  end

  @tag :tmp_dir
  test "AddText.execute rejects blank content", %{project_id: id} do
    assert {:error, msg} =
             AddText.execute(%{
               "project_id" => id,
               "content" => "   ",
               "start_ms" => 0,
               "duration_ms" => 2000
             })

    assert msg =~ "Invalid content"

    {:ok, draft} = ProjectStore.get_project(id)
    text_track = Enum.find(draft["tracks"], fn track -> track["id"] == "track-001" end)
    assert length(text_track["segments"]) == 1
  end

  alias CapcutMcp.Tools.{
    AddClip,
    MoveClip,
    ReadDraftJson,
    RemoveClip,
    SetClipBlendMode,
    SetClipLoop,
    SetClipOpacity,
    SetClipTransform,
    SetClipVolume,
    TrimClip
  }

  # ── ReadDraftJson ───────────────────────────────────────────────────────────

  @tag :tmp_dir
  test "ReadDraftJson.execute returns valid JSON", %{project_id: id} do
    assert {:ok, text} = ReadDraftJson.execute(%{"project_id" => id})
    assert {:ok, _} = Jason.decode(text)
  end

  @tag :tmp_dir
  test "ReadDraftJson.execute returns error for unknown project" do
    assert {:error, msg} = ReadDraftJson.execute(%{"project_id" => "NOPE"})
    assert msg =~ "not found"
  end

  # ── SetClipVolume ───────────────────────────────────────────────────────────

  @tag :tmp_dir
  test "SetClipVolume.execute sets volume on a segment", %{project_id: id} do
    assert {:ok, _} =
             SetClipVolume.execute(%{"project_id" => id, "clip_id" => "seg-001", "volume" => 0.5})

    {:ok, draft} = ProjectStore.get_project(id)

    seg =
      draft["tracks"] |> Enum.flat_map(& &1["segments"]) |> Enum.find(&(&1["id"] == "seg-001"))

    assert seg["volume"] == 0.5
  end

  @tag :tmp_dir
  test "SetClipVolume.execute allows volume above 1.0", %{project_id: id} do
    assert {:ok, _} =
             SetClipVolume.execute(%{"project_id" => id, "clip_id" => "seg-001", "volume" => 5.0})

    {:ok, draft} = ProjectStore.get_project(id)

    seg =
      draft["tracks"] |> Enum.flat_map(& &1["segments"]) |> Enum.find(&(&1["id"] == "seg-001"))

    assert seg["volume"] == 5.0
  end

  @tag :tmp_dir
  test "SetClipVolume.execute rejects negative volume", %{project_id: id} do
    assert {:error, msg} =
             SetClipVolume.execute(%{
               "project_id" => id,
               "clip_id" => "seg-001",
               "volume" => -1.0
             })

    assert msg =~ "Invalid volume"
  end

  # ── SetClipLoop ─────────────────────────────────────────────────────────────

  @tag :tmp_dir
  test "SetClipLoop.execute enables loop", %{project_id: id} do
    assert {:ok, _} =
             SetClipLoop.execute(%{"project_id" => id, "clip_id" => "seg-001", "loop" => true})

    {:ok, draft} = ProjectStore.get_project(id)

    seg =
      draft["tracks"] |> Enum.flat_map(& &1["segments"]) |> Enum.find(&(&1["id"] == "seg-001"))

    assert seg["is_loop"] == true
  end

  @tag :tmp_dir
  test "SetClipLoop.execute disables loop", %{project_id: id} do
    SetClipLoop.execute(%{"project_id" => id, "clip_id" => "seg-001", "loop" => true})

    assert {:ok, _} =
             SetClipLoop.execute(%{"project_id" => id, "clip_id" => "seg-001", "loop" => false})

    {:ok, draft} = ProjectStore.get_project(id)

    seg =
      draft["tracks"] |> Enum.flat_map(& &1["segments"]) |> Enum.find(&(&1["id"] == "seg-001"))

    assert seg["is_loop"] == false
  end

  # ── MoveClip ────────────────────────────────────────────────────────────────

  @tag :tmp_dir
  test "MoveClip.execute moves a segment to new start position", %{project_id: id} do
    assert {:ok, _} =
             MoveClip.execute(%{"project_id" => id, "clip_id" => "seg-001", "start_ms" => 5000})

    {:ok, draft} = ProjectStore.get_project(id)

    seg =
      draft["tracks"] |> Enum.flat_map(& &1["segments"]) |> Enum.find(&(&1["id"] == "seg-001"))

    assert seg["target_timerange"]["start"] == 5_000_000
  end

  @tag :tmp_dir
  test "MoveClip.execute rejects negative start_ms", %{project_id: id} do
    assert {:error, msg} =
             MoveClip.execute(%{"project_id" => id, "clip_id" => "seg-001", "start_ms" => -1})

    assert msg =~ "Invalid start_ms"
  end

  @tag :tmp_dir
  test "MoveClip.execute returns error for missing required arguments" do
    assert {:error, msg} = MoveClip.execute(%{})
    assert msg =~ "project_id"
    assert msg =~ "clip_id"
    assert msg =~ "start_ms"
  end

  @tag :tmp_dir
  test "new tools return errors instead of raising on missing required arguments" do
    tools = [
      {ReadDraftJson, ["project_id"]},
      {SetClipVolume, ["project_id", "clip_id", "volume"]},
      {SetClipLoop, ["project_id", "clip_id", "loop"]},
      {SetClipTransform, ["project_id", "clip_id"]},
      {SetClipOpacity, ["project_id", "clip_id", "opacity"]},
      {TrimClip, ["project_id", "clip_id"]},
      {SetClipBlendMode, ["project_id", "clip_id", "mode"]}
    ]

    Enum.each(tools, fn {tool, required_keys} ->
      assert {:error, msg} = tool.execute(%{})

      Enum.each(required_keys, fn key ->
        assert msg =~ key
      end)
    end)
  end

  @tag :tmp_dir
  test "MoveClip.execute initializes missing target_timerange", %{project_id: id} do
    {:ok, draft} = ProjectStore.get_project(id)
    [track] = draft["tracks"]
    [seg] = track["segments"]
    seg_with_nil_target = Map.put(seg, "target_timerange", nil)
    updated_track = Map.put(track, "segments", [seg_with_nil_target])
    :ok = ProjectStore.update_project(id, %{draft | "tracks" => [updated_track]})

    assert {:ok, _} =
             MoveClip.execute(%{"project_id" => id, "clip_id" => "seg-001", "start_ms" => 5000})

    {:ok, updated_draft} = ProjectStore.get_project(id)

    updated_seg =
      updated_draft["tracks"]
      |> Enum.flat_map(& &1["segments"])
      |> Enum.find(&(&1["id"] == "seg-001"))

    assert updated_seg["target_timerange"]["start"] == 5_000_000
    assert updated_seg["target_timerange"]["duration"] == 3_000_000
  end

  # ── SetClipTransform ────────────────────────────────────────────────────────

  @tag :tmp_dir
  test "SetClipTransform.execute sets transform on video clip", %{project_id: id} do
    # First add a video clip (which has a clip object)
    {:ok, msg} =
      AddClip.execute(%{
        "project_id" => id,
        "file_path" => "C:/test.mp4",
        "start_ms" => 0,
        "duration_ms" => 5000
      })

    seg_id =
      msg
      |> String.split("\n")
      |> Enum.find(&(&1 =~ "Segment ID"))
      |> String.split(": ")
      |> List.last()

    assert {:ok, _} =
             SetClipTransform.execute(%{
               "project_id" => id,
               "clip_id" => seg_id,
               "x" => 0.5,
               "scale_x" => 2.0
             })

    {:ok, draft} = ProjectStore.get_project(id)
    seg = draft["tracks"] |> Enum.flat_map(& &1["segments"]) |> Enum.find(&(&1["id"] == seg_id))
    assert seg["clip"]["transform"]["x"] == 0.5
    assert seg["clip"]["scale"]["x"] == 2.0
    # Unchanged values preserved
    assert seg["clip"]["transform"]["y"] == 0.0
    assert seg["clip"]["scale"]["y"] == 1.0
  end

  @tag :tmp_dir
  test "SetClipTransform.execute rejects text segment without clip", %{project_id: id} do
    assert {:error, msg} =
             SetClipTransform.execute(%{"project_id" => id, "clip_id" => "seg-001", "x" => 0.5})

    assert msg =~ "no clip object"
  end

  # ── SetClipOpacity ──────────────────────────────────────────────────────────

  @tag :tmp_dir
  test "SetClipOpacity.execute sets opacity on video clip", %{project_id: id} do
    {:ok, msg} =
      AddClip.execute(%{
        "project_id" => id,
        "file_path" => "C:/test.mp4",
        "start_ms" => 0,
        "duration_ms" => 5000
      })

    seg_id =
      msg
      |> String.split("\n")
      |> Enum.find(&(&1 =~ "Segment ID"))
      |> String.split(": ")
      |> List.last()

    assert {:ok, _} =
             SetClipOpacity.execute(%{"project_id" => id, "clip_id" => seg_id, "opacity" => 0.3})

    {:ok, draft} = ProjectStore.get_project(id)
    seg = draft["tracks"] |> Enum.flat_map(& &1["segments"]) |> Enum.find(&(&1["id"] == seg_id))
    assert seg["clip"]["alpha"] == 0.3
  end

  @tag :tmp_dir
  test "SetClipOpacity.execute rejects out-of-range opacity", %{project_id: id} do
    {:ok, msg} =
      AddClip.execute(%{
        "project_id" => id,
        "file_path" => "C:/test.mp4",
        "start_ms" => 0,
        "duration_ms" => 5000
      })

    seg_id =
      msg
      |> String.split("\n")
      |> Enum.find(&(&1 =~ "Segment ID"))
      |> String.split(": ")
      |> List.last()

    assert {:error, msg} =
             SetClipOpacity.execute(%{"project_id" => id, "clip_id" => seg_id, "opacity" => 1.5})

    assert msg =~ "Invalid opacity"
  end

  @tag :tmp_dir
  test "SetClipOpacity.execute rejects text segment without clip", %{project_id: id} do
    assert {:error, msg} =
             SetClipOpacity.execute(%{
               "project_id" => id,
               "clip_id" => "seg-001",
               "opacity" => 0.5
             })

    assert msg =~ "no clip object"
  end

  # ── TrimClip ────────────────────────────────────────────────────────────────

  @tag :tmp_dir
  test "TrimClip.execute trims source and target", %{project_id: id} do
    assert {:ok, _} =
             TrimClip.execute(%{
               "project_id" => id,
               "clip_id" => "seg-001",
               "source_start_ms" => 1000,
               "source_duration_ms" => 2000
             })

    {:ok, draft} = ProjectStore.get_project(id)

    seg =
      draft["tracks"] |> Enum.flat_map(& &1["segments"]) |> Enum.find(&(&1["id"] == "seg-001"))

    assert seg["source_timerange"]["start"] == 1_000_000
    assert seg["source_timerange"]["duration"] == 2_000_000
    # target_duration matches source when target_duration_ms not given
    assert seg["target_timerange"]["duration"] == 2_000_000
  end

  @tag :tmp_dir
  test "TrimClip.execute allows independent target duration", %{project_id: id} do
    assert {:ok, _} =
             TrimClip.execute(%{
               "project_id" => id,
               "clip_id" => "seg-001",
               "source_duration_ms" => 2000,
               "target_duration_ms" => 4000
             })

    {:ok, draft} = ProjectStore.get_project(id)

    seg =
      draft["tracks"] |> Enum.flat_map(& &1["segments"]) |> Enum.find(&(&1["id"] == "seg-001"))

    assert seg["source_timerange"]["duration"] == 2_000_000
    assert seg["target_timerange"]["duration"] == 4_000_000
  end

  @tag :tmp_dir
  test "TrimClip.execute initializes missing target_timerange", %{project_id: id} do
    {:ok, draft} = ProjectStore.get_project(id)
    [track] = draft["tracks"]
    [seg] = track["segments"]
    seg_with_nil_target = Map.put(seg, "target_timerange", nil)
    updated_track = Map.put(track, "segments", [seg_with_nil_target])
    :ok = ProjectStore.update_project(id, %{draft | "tracks" => [updated_track]})

    assert {:ok, _} =
             TrimClip.execute(%{
               "project_id" => id,
               "clip_id" => "seg-001",
               "source_duration_ms" => 2000
             })

    {:ok, updated_draft} = ProjectStore.get_project(id)

    updated_seg =
      updated_draft["tracks"]
      |> Enum.flat_map(& &1["segments"])
      |> Enum.find(&(&1["id"] == "seg-001"))

    assert updated_seg["target_timerange"]["start"] == 0
    assert updated_seg["target_timerange"]["duration"] == 2_000_000
  end

  @tag :tmp_dir
  test "AddClip.execute adds a video segment", %{project_id: id} do
    assert {:ok, msg} =
             AddClip.execute(%{
               "project_id" => id,
               "file_path" => "C:/Users/tspor/Videos/test.mp4",
               "start_ms" => 0,
               "duration_ms" => 5000
             })

    assert msg =~ "Clip added"
    {:ok, draft} = ProjectStore.get_project(id)
    video_tracks = Enum.filter(draft["tracks"], fn t -> t["type"] == "video" end)
    assert video_tracks != []
  end

  @tag :tmp_dir
  test "AddClip.execute detects audio files by extension", %{project_id: id} do
    assert {:ok, msg} =
             AddClip.execute(%{
               "project_id" => id,
               "file_path" => "C:/Users/tspor/Music/track.mp3",
               "start_ms" => 0,
               "duration_ms" => 3000
             })

    assert msg =~ "Clip added"
    {:ok, draft} = ProjectStore.get_project(id)
    audio_tracks = Enum.filter(draft["tracks"], fn t -> t["type"] == "audio" end)
    assert audio_tracks != []
  end

  @tag :tmp_dir
  test "AddClip.execute rejects out-of-range track_index", %{project_id: id} do
    assert {:error, msg} =
             AddClip.execute(%{
               "project_id" => id,
               "file_path" => "C:/Users/tspor/Videos/test.mp4",
               "start_ms" => 0,
               "duration_ms" => 5000,
               "track_index" => 99
             })

    assert msg =~ "Invalid track index"

    {:ok, draft} = ProjectStore.get_project(id)
    refute Enum.any?(draft["tracks"], fn track -> track["type"] == "video" end)
  end

  @tag :tmp_dir
  test "AddClip.execute rejects negative start_ms", %{project_id: id} do
    assert {:error, msg} =
             AddClip.execute(%{
               "project_id" => id,
               "file_path" => "C:/Users/tspor/Videos/test.mp4",
               "start_ms" => -1,
               "duration_ms" => 5000
             })

    assert msg =~ "Invalid start_ms"

    {:ok, draft} = ProjectStore.get_project(id)
    refute Enum.any?(draft["tracks"], fn track -> track["type"] == "video" end)
  end

  @tag :tmp_dir
  test "AddClip.execute rejects non-positive duration_ms", %{project_id: id} do
    assert {:error, msg} =
             AddClip.execute(%{
               "project_id" => id,
               "file_path" => "C:/Users/tspor/Videos/test.mp4",
               "start_ms" => 0,
               "duration_ms" => 0
             })

    assert msg =~ "Invalid duration_ms"

    {:ok, draft} = ProjectStore.get_project(id)
    refute Enum.any?(draft["tracks"], fn track -> track["type"] == "video" end)
  end

  @tag :tmp_dir
  test "AddClip.execute rejects blank file_path", %{project_id: id} do
    assert {:error, msg} =
             AddClip.execute(%{
               "project_id" => id,
               "file_path" => "   ",
               "start_ms" => 0,
               "duration_ms" => 5000
             })

    assert msg =~ "Invalid file_path"

    {:ok, draft} = ProjectStore.get_project(id)
    refute Enum.any?(draft["tracks"], fn track -> track["type"] == "video" end)
  end

  @tag :tmp_dir
  test "AddClip.execute rejects relative file_path", %{project_id: id} do
    assert {:error, msg} =
             AddClip.execute(%{
               "project_id" => id,
               "file_path" => "videos/test.mp4",
               "start_ms" => 0,
               "duration_ms" => 5000
             })

    assert msg =~ "Invalid file_path"

    {:ok, draft} = ProjectStore.get_project(id)
    refute Enum.any?(draft["tracks"], fn track -> track["type"] == "video" end)
  end

  @tag :tmp_dir
  test "RemoveClip.execute removes a segment by ID", %{project_id: id} do
    # Load into cache first
    {:ok, _} = ProjectStore.get_project(id)

    assert :ok =
             ProjectStore.update_project(id, %{
               "id" => id,
               "tracks" => [
                 %{
                   "id" => "t1",
                   "type" => "text",
                   "segments" => [
                     %{
                       "id" => "seg-to-remove",
                       "material_id" => "m1",
                       "target_timerange" => %{"start" => 0, "duration" => 1000}
                     }
                   ]
                 }
               ],
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
