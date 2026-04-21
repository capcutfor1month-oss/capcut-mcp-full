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

  @tag :tmp_dir
  test "create_project tolerates root_meta_info.json that lacks expected keys", %{tmp: tmp} do
    # A future CapCut build (or a hand-edited meta file) might ship without
    # `all_draft_store` or `draft_ids`. The store must still create the project
    # instead of crashing the GenServer on a map-update KeyError.
    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(%{"unexpected" => "shape"}))

    assert {:ok, new_id} = ProjectStore.create_project(%{"name" => "Resilient"})

    {:ok, content} = File.read(Path.join(tmp, "root_meta_info.json"))
    {:ok, meta} = Jason.decode(content)
    assert meta["unexpected"] == "shape"
    assert [%{"draft_id" => ^new_id}] = meta["all_draft_store"]
    assert meta["draft_ids"] == 1
  end

  # ── Telemetry cases (D1b) ──────────────────────────────────────────────────

  @cache_events [
    [:capcut_mcp, :cache, :hit],
    [:capcut_mcp, :cache, :miss],
    [:capcut_mcp, :cache, :write]
  ]

  @tag :tmp_dir
  test "get_project emits miss + write on first call, hit on second", %{project_id: id} do
    attach_cache_events()

    assert {:ok, _} = ProjectStore.get_project(id)

    assert_receive {[:capcut_mcp, :cache, :miss], %{count: 1}, %{id: ^id}}
    assert_receive {[:capcut_mcp, :cache, :write], %{count: 1}, %{id: ^id, reason: :load}}

    assert {:ok, _} = ProjectStore.get_project(id)
    assert_receive {[:capcut_mcp, :cache, :hit], %{count: 1}, %{id: ^id}}
  end

  @tag :tmp_dir
  test "update_project emits a :write event with reason :update", %{project_id: id} do
    {:ok, draft} = ProjectStore.get_project(id)
    attach_cache_events()

    :ok = ProjectStore.update_project(id, Map.put(draft, "name", "Updated"))

    assert_receive {[:capcut_mcp, :cache, :write], %{count: 1}, %{id: ^id, reason: :update}}
  end

  @tag :tmp_dir
  test "create_project emits a :write event with reason :create" do
    attach_cache_events()

    {:ok, new_id} = ProjectStore.create_project(%{"name" => "Telemetry Project"})

    assert_receive {[:capcut_mcp, :cache, :write], %{count: 1}, %{id: ^new_id, reason: :create}}
  end

  defp attach_cache_events do
    handler_id = {:cache_events, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        @cache_events,
        fn event, measurements, metadata, _ ->
          send(test_pid, {event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
