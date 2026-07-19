defmodule CapcutMcp.CapCut.ProjectStoreTest do
  use ExUnit.Case

  alias CapcutMcp.CapCut.{ManifestSchema, ProjectMeta, ProjectStore}

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
  test "get_project_with_meta returns ProjectMeta and draft together", %{project_id: id} do
    assert {:ok, %{meta: %ProjectMeta{} = meta, draft: draft}} =
             ProjectStore.get_project_with_meta(id)

    assert meta.id == id
    assert meta.name == "Test"
    assert draft["id"] == id
    assert draft["fps"] == 30.0
  end

  @tag :tmp_dir
  test "get_project_with_meta surfaces root_meta identity even when draft_content.id diverges",
       %{tmp: tmp} do
    root_meta_id = "ROOT-META-UUID"
    content_id = "CONTENT-UUID"

    project_path = Path.join(tmp, "divergent_project")
    File.mkdir_p!(project_path)

    File.write!(
      Path.join(project_path, "draft_content.json"),
      Jason.encode!(%{"id" => content_id, "fps" => 30.0, "name" => ""})
    )

    existing = Jason.decode!(File.read!(Path.join(tmp, "root_meta_info.json")))

    updated_entries =
      existing["all_draft_store"] ++
        [
          %{
            "draft_id" => root_meta_id,
            "draft_name" => "Divergent",
            "draft_fold_path" => project_path,
            "tm_draft_modified" => 1_000_000_000_000_000,
            "tm_duration" => 0
          }
        ]

    File.write!(
      Path.join(tmp, "root_meta_info.json"),
      Jason.encode!(%{existing | "all_draft_store" => updated_entries, "draft_ids" => 2})
    )

    assert {:ok, %{meta: meta, draft: draft}} =
             ProjectStore.get_project_with_meta(root_meta_id)

    assert meta.id == root_meta_id
    assert meta.name == "Divergent"
    assert draft["id"] == content_id
  end

  @tag :tmp_dir
  test "get_project_with_meta returns :not_found for unknown id" do
    assert {:error, :not_found} = ProjectStore.get_project_with_meta("NONEXISTENT")
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
  test "create_project writes a CapCut-compatible full-schema manifest entry", %{tmp: tmp} do
    assert {:ok, new_id} = ProjectStore.create_project(%{"name" => "Schema Probe"})

    {:ok, content} = File.read(Path.join(tmp, "root_meta_info.json"))
    {:ok, meta} = Jason.decode(content)

    entry = Enum.find(meta["all_draft_store"], &(&1["draft_id"] == new_id))

    # Full ManifestSchema.keys() shape — CapCut drops manifest entries that
    # miss any of these on startup, so any regression here silently makes
    # MCP-created projects invisible in the CapCut UI after the next restart.
    # See ManifestSchema's moduledoc for why the key count differs by platform.
    assert Enum.sort(Map.keys(entry)) == ManifestSchema.keys()

    # Sentinel defaults that ByteDance-style cloud clients key off of.
    assert entry["streaming_edit_draft_ready"] == true
    # Ground truth (2026-07-20): a real, freshly-created, never-edited
    # CapCut project's manifest entry carries an EMPTY draft_new_version —
    # "164.0.0" only appears once a project has actually been edited.
    assert entry["draft_new_version"] == ""
    assert entry["tm_draft_cloud_entry_id"] == -1
    assert entry["tm_draft_cloud_user_id"] == -1
  end

  @tag :tmp_dir
  test "create_project's draft_info.json id is the timeline id, not the manifest draft_id",
       %{tmp: tmp} do
    # This is the confirmed root cause of CapCut silently refusing to open
    # every MCP-created project through v10 (2026-07-19/20 investigation).
    # draft_info.json's own `id` field is NOT the project's identity — it's
    # the TIMELINE id. Checked across all 12 real CapCut projects on disk:
    # every one has draft_info.json's `id` DIFFERENT from its manifest
    # `draft_id`, and matching its own `Timelines/[uuid]` subfolder name.
    # Live-tested fix: a project built this way opened successfully in the
    # real CapCut app and the fix survived a full quit/relaunch.
    assert {:ok, new_id} = ProjectStore.create_project(%{"name" => "IdentityProbe"})

    {:ok, draft_content} =
      File.read(Path.join([tmp, "IdentityProbe", "draft_info.json"]))

    {:ok, draft_json} = Jason.decode(draft_content)

    refute draft_json["id"] == new_id

    # The internal id must equal the Timelines/ subfolder's own name.
    timelines_dir = Path.join([tmp, "IdentityProbe", "Timelines"])

    [timeline_id] =
      timelines_dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(timelines_dir, &1)))

    assert draft_json["id"] == timeline_id
  end

  @tag :tmp_dir
  test "create_project normalizes manifest paths to CapCut's forward-slash convention",
       %{tmp: tmp} do
    {:ok, new_id} = ProjectStore.create_project(%{"name" => "Path Probe"})

    {:ok, content} = File.read(Path.join(tmp, "root_meta_info.json"))
    {:ok, meta} = Jason.decode(content)

    entry = Enum.find(meta["all_draft_store"], &(&1["draft_id"] == new_id))

    # draft_fold_path and draft_root_path: forward slashes only.
    refute String.contains?(entry["draft_fold_path"], "\\")
    refute String.contains?(entry["draft_root_path"], "\\")
    refute String.contains?(entry["draft_cover"], "\\")

    # draft_json_file: Windows gets forward-slash folder + single backslash
    # before the filename; macOS (and everything else) gets pure forward
    # slashes throughout. See PathUtil.draft_json_file/1.
    case :os.type() do
      {:win32, _} ->
        assert String.ends_with?(entry["draft_json_file"], "\\draft_info.json")

        assert entry["draft_json_file"]
               |> String.graphemes()
               |> Enum.count(&(&1 == "\\")) == 1

      _ ->
        assert String.ends_with?(entry["draft_json_file"], "/draft_info.json")
        refute String.contains?(entry["draft_json_file"], "\\")
    end

    # Root-object root_path is forward-slash too.
    refute String.contains?(meta["root_path"], "\\")
  end

  @tag :tmp_dir
  test "draft_ids always equals length(all_draft_store) across create/remove sequences",
       %{tmp: tmp} do
    # Start with the 1 seed entry from setup
    assert_draft_ids_consistent(tmp)

    {:ok, a} = ProjectStore.create_project(%{"name" => "A"})
    assert_draft_ids_consistent(tmp)

    {:ok, b} = ProjectStore.create_project(%{"name" => "B"})
    assert_draft_ids_consistent(tmp)

    {:ok, _c} = ProjectStore.create_project(%{"name" => "C"})
    assert_draft_ids_consistent(tmp)

    :ok = ProjectStore.remove_project(b)
    assert_draft_ids_consistent(tmp)

    :ok = ProjectStore.remove_project(a)
    assert_draft_ids_consistent(tmp)
  end

  defp assert_draft_ids_consistent(tmp) do
    {:ok, content} = File.read(Path.join(tmp, "root_meta_info.json"))
    {:ok, meta} = Jason.decode(content)

    assert meta["draft_ids"] == length(meta["all_draft_store"]),
           "draft_ids=#{meta["draft_ids"]} but all_draft_store has " <>
             "#{length(meta["all_draft_store"])} entries"
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

  # ── remove_project ─────────────────────────────────────────────────────────

  @tag :tmp_dir
  test "remove_project deletes entry from root_meta_info and folder from disk",
       %{project_id: id, project_path: path, tmp: tmp} do
    # Prime cache so we can also observe cache invalidation
    {:ok, _} = ProjectStore.get_project(id)

    assert :ok = ProjectStore.remove_project(id)

    # Entry gone, draft_ids decremented
    {:ok, content} = File.read(Path.join(tmp, "root_meta_info.json"))
    {:ok, meta} = Jason.decode(content)
    assert meta["all_draft_store"] == []
    assert meta["draft_ids"] == 0

    # Folder gone
    refute File.exists?(path)

    # Cache entry gone → next get_project is a :not_found
    assert {:error, :not_found} = ProjectStore.get_project(id)
  end

  @tag :tmp_dir
  test "remove_project with keep_files: true deletes entry but leaves folder",
       %{project_id: id, project_path: path, tmp: tmp} do
    assert :ok = ProjectStore.remove_project(id, keep_files: true)

    {:ok, content} = File.read(Path.join(tmp, "root_meta_info.json"))
    {:ok, meta} = Jason.decode(content)
    assert meta["all_draft_store"] == []
    assert meta["draft_ids"] == 0

    assert File.exists?(path)
    assert File.exists?(Path.join(path, "draft_content.json"))
  end

  @tag :tmp_dir
  test "remove_project returns :not_found for unknown id", %{tmp: tmp} do
    {:ok, before} = File.read(Path.join(tmp, "root_meta_info.json"))
    assert {:error, :not_found} = ProjectStore.remove_project("UNKNOWN-ID")
    {:ok, unchanged} = File.read(Path.join(tmp, "root_meta_info.json"))
    assert before == unchanged
  end

  @tag :tmp_dir
  test "remove_project writes a .bak of root_meta_info.json so a bad edit is recoverable",
       %{project_id: id, tmp: tmp} do
    assert :ok = ProjectStore.remove_project(id)

    {:ok, bak_content} = File.read(Path.join(tmp, "root_meta_info.json.bak"))
    {:ok, bak} = Jason.decode(bak_content)
    # The .bak holds the *pre-remove* state — i.e. still contains the entry
    assert [%{"draft_id" => ^id}] = bak["all_draft_store"]
  end

  @tag :tmp_dir
  test "remove_project refuses to delete a folder outside the configured root",
       %{tmp: tmp} do
    # A corrupt or hand-edited root_meta_info that points draft_fold_path to
    # some place outside CAPCUT_PATH must never cause an rm_rf on that path —
    # even if the user asks to remove the entry.
    evil_outside =
      Path.join(
        System.tmp_dir!(),
        "capcut_mcp_evil_outside_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(evil_outside)
    evil_file = Path.join(evil_outside, "must_survive.txt")
    File.write!(evil_file, "don't touch me")

    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => "EVIL-ID",
          "draft_name" => "Evil",
          "draft_fold_path" => evil_outside,
          "tm_draft_modified" => 0,
          "tm_duration" => 0
        }
      ],
      "draft_ids" => 1,
      "root_path" => tmp
    }

    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))

    assert {:error, :path_outside_root} = ProjectStore.remove_project("EVIL-ID")

    # Evil folder untouched
    assert File.exists?(evil_file)
    assert File.read!(evil_file) == "don't touch me"

    File.rm_rf!(evil_outside)
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
