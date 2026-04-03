defmodule CapcutMcp.CapCut.ProjectStoreTest do
  use ExUnit.Case

  alias CapcutMcp.CapCut.ProjectStore

  setup %{tmp_dir: tmp} do
    project_id = "TEST-001"
    project_path = Path.join(tmp, "test_project")
    File.mkdir_p!(project_path)

    draft = %{
      "id" => project_id,
      "name" => "Test",
      "tracks" => [],
      "materials" => %{
        "videos" => [],
        "texts" => [],
        "audios" => [],
        "images" => [],
        "effects" => [],
        "transitions" => [],
        "stickers" => [],
        "filters" => []
      },
      "fps" => 30.0,
      "duration" => 0,
      "canvas_config" => %{
        "width" => 1920,
        "height" => 1080,
        "ratio" => "original",
        "background" => nil
      }
    }

    File.write!(Path.join(project_path, "draft_content.json"), Jason.encode!(draft))

    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => project_id,
          "draft_name" => "Test",
          "draft_fold_path" => project_path,
          "draft_json_file" => Path.join(project_path, "draft_content.json"),
          "tm_draft_modified" => 1_000_000_000_000_000,
          "tm_duration" => 0
        }
      ],
      "draft_ids" => 1,
      "root_path" => tmp
    }

    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))

    {:ok, _pid} = start_supervised({ProjectStore, [root_path: tmp]})
    %{project_id: project_id, project_path: project_path, tmp: tmp}
  end

  @tag :tmp_dir
  test "list_projects returns projects from disk", %{project_id: id} do
    assert {:ok, [project]} = ProjectStore.list_projects()
    assert project.id == id
    assert project.name == "Test"
  end

  @tag :tmp_dir
  test "get_project returns draft map", %{project_id: id} do
    assert {:ok, draft} = ProjectStore.get_project(id)
    assert draft["id"] == id
    assert draft["fps"] == 30.0
  end

  @tag :tmp_dir
  test "get_project returns error for unknown id" do
    assert {:error, :not_found} = ProjectStore.get_project("NONEXISTENT")
  end

  @tag :tmp_dir
  test "update_project writes to disk and updates cache", %{project_id: id, project_path: path} do
    {:ok, draft} = ProjectStore.get_project(id)
    updated = Map.put(draft, "name", "Updated")
    assert :ok = ProjectStore.update_project(id, updated)
    {:ok, content} = File.read(Path.join(path, "draft_content.json"))
    assert {:ok, %{"name" => "Updated"}} = Jason.decode(content)
  end

  @tag :tmp_dir
  test "create_project creates directory and files" do
    assert {:ok, new_id} = ProjectStore.create_project(%{"name" => "New Project"})
    assert is_binary(new_id)
    {:ok, projects} = ProjectStore.list_projects()
    ids = Enum.map(projects, & &1.id)
    assert new_id in ids
  end
end
