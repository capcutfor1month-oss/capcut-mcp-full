defmodule CapcutMcp.CapCut.ReaderTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias CapcutMcp.CapCut.ProjectMeta
  alias CapcutMcp.CapCut.Reader

  @tag :tmp_dir
  test "list_projects returns empty list when no drafts", %{tmp_dir: tmp} do
    meta = %{"all_draft_store" => [], "draft_ids" => 0, "root_path" => tmp}
    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))
    assert {:ok, []} = Reader.list_projects(tmp)
  end

  @tag :tmp_dir
  test "list_projects returns ProjectMeta list", %{tmp_dir: tmp} do
    draft_path = Path.join(tmp, "some_project")

    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => "abc-123",
          "draft_name" => "My Video",
          "draft_fold_path" => draft_path,
          "tm_draft_modified" => 1_000_000_000_000_000,
          "tm_duration" => 5_000_000
        }
      ],
      "draft_ids" => 1,
      "root_path" => tmp
    }

    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))
    assert {:ok, [project]} = Reader.list_projects(tmp)

    assert %ProjectMeta{
             id: "abc-123",
             name: "My Video",
             modified_at: 1_000_000_000_000_000,
             duration_ms: 5000
           } = project

    assert project.path == draft_path
  end

  @tag :tmp_dir
  test "list_projects returns error when file missing", %{tmp_dir: tmp} do
    assert {:error, _} = Reader.list_projects(tmp)
  end

  @tag :tmp_dir
  test "read_draft returns parsed map", %{tmp_dir: tmp} do
    draft = %{
      "id" => "test-id",
      "name" => "Test",
      "tracks" => [],
      "fps" => 30.0,
      "new_version" => "163.0.0"
    }

    File.write!(Path.join(tmp, "draft_content.json"), Jason.encode!(draft))
    assert {:ok, %{"id" => "test-id", "name" => "Test"}} = Reader.read_draft(tmp)
  end

  @tag :tmp_dir
  test "read_draft returns error when file missing", %{tmp_dir: tmp} do
    assert {:error, _} = Reader.read_draft(tmp)
  end

  # ── D14: Schema-Version Handling ───────────────────────────────────────────

  describe "read_draft schema version" do
    @tag :tmp_dir
    test "emits :schema_version with supported: true on known version", %{tmp_dir: tmp} do
      [supported | _] = Reader.supported_versions()
      write_draft(tmp, %{"new_version" => supported})

      attach_schema_version_event()

      log =
        capture_log(fn ->
          assert {:ok, _} = Reader.read_draft(tmp)
        end)

      assert_receive {[:capcut_mcp, :draft, :schema_version], %{count: 1},
                      %{version: ^supported, supported: true}}

      refute log =~ "untested"
    end

    @tag :tmp_dir
    test "emits :schema_version and warns on unknown version", %{tmp_dir: tmp} do
      write_draft(tmp, %{"new_version" => "999.0.0"})

      attach_schema_version_event()

      log =
        capture_log(fn ->
          assert {:ok, _} = Reader.read_draft(tmp)
        end)

      assert_receive {[:capcut_mcp, :draft, :schema_version], %{count: 1},
                      %{version: "999.0.0", supported: false}}

      assert log =~ "CapCut schema version \"999.0.0\" untested"
    end

    @tag :tmp_dir
    test "emits :schema_version and warns when new_version is missing", %{tmp_dir: tmp} do
      write_draft(tmp, %{})

      attach_schema_version_event()

      log =
        capture_log(fn ->
          assert {:ok, _} = Reader.read_draft(tmp)
        end)

      assert_receive {[:capcut_mcp, :draft, :schema_version], %{count: 1},
                      %{version: nil, supported: false}}

      assert log =~ "CapCut schema version nil untested"
    end

    @tag :tmp_dir
    test "does not emit :schema_version when file is missing", %{tmp_dir: tmp} do
      attach_schema_version_event()

      assert {:error, _} = Reader.read_draft(tmp)

      refute_receive {[:capcut_mcp, :draft, :schema_version], _, _}, 50
    end
  end

  # ── D16-F3/F4: corrupted meta, path escapes, non-integer timestamps ────────

  describe "list_projects hardening" do
    @tag :tmp_dir
    test "filters draft_fold_path entries outside of root_path and emits telemetry",
         %{tmp_dir: tmp} do
      inside = Path.join(tmp, "legit_project")

      meta = %{
        "all_draft_store" => [
          %{
            "draft_id" => "legit",
            "draft_name" => "Legit",
            "draft_fold_path" => inside,
            "tm_draft_modified" => 1_000_000_000_000_000,
            "tm_duration" => 0
          },
          %{
            "draft_id" => "escape",
            "draft_name" => "Escape",
            "draft_fold_path" => "/absolute/outside/escape",
            "tm_draft_modified" => 1_000_000_000_000_000,
            "tm_duration" => 0
          }
        ],
        "draft_ids" => 2,
        "root_path" => tmp
      }

      File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))

      attach_meta_rejected_event()

      log =
        capture_log(fn ->
          assert {:ok, [legit]} = Reader.list_projects(tmp)
          assert legit.id == "legit"
        end)

      assert log =~ "outside of CAPCUT_PATH"

      assert_receive {[:capcut_mcp, :meta, :rejected], %{count: 1},
                      %{reason: :path_outside_root, path: "/absolute/outside/escape"}}
    end

    @tag :tmp_dir
    test "list_projects does not raise on non-integer tm_draft_modified or tm_duration",
         %{tmp_dir: tmp} do
      inside = Path.join(tmp, "weird_project")

      meta = %{
        "all_draft_store" => [
          %{
            "draft_id" => "weird",
            "draft_name" => "Weird",
            "draft_fold_path" => inside,
            "tm_draft_modified" => "not-a-number",
            "tm_duration" => 3.14
          }
        ],
        "draft_ids" => 1,
        "root_path" => tmp
      }

      File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))

      assert {:ok, [p]} = Reader.list_projects(tmp)
      assert p.id == "weird"
      assert p.modified_at == nil
      assert is_integer(p.duration_ms)
    end

    @tag :tmp_dir
    test "accepts a draft_fold_path that differs from root only in case or separator on Windows",
         %{tmp_dir: tmp} do
      # Windows filesystems are case-insensitive and CapCut may persist either
      # forward or backward slashes in root_meta_info.json. A mismatch of case
      # or separator between CAPCUT_PATH and the stored path must not cause
      # the entry to be silently dropped.
      unless match?({:win32, _}, :os.type()) do
        # On non-Windows the comparison is case-sensitive; skip by asserting
        # the classic path-through works and the case-mangled one is rejected.
        :ok
      end

      inside = Path.join(tmp, "case_mixed_project")
      File.mkdir_p!(inside)

      mangled_path =
        tmp
        |> String.replace("/", "\\")
        |> then(fn s ->
          # Flip case on alphabetic chars so the expanded path differs in case
          # from the root we pass into list_projects.
          s
          |> String.graphemes()
          |> Enum.map_join("", fn g ->
            case g do
              g when g >= "a" and g <= "z" -> String.upcase(g)
              g when g >= "A" and g <= "Z" -> String.downcase(g)
              g -> g
            end
          end)
        end)
        |> Path.join("case_mixed_project")

      meta = %{
        "all_draft_store" => [
          %{
            "draft_id" => "mixed",
            "draft_name" => "Mixed",
            "draft_fold_path" => mangled_path,
            "tm_draft_modified" => 1_000_000_000_000_000,
            "tm_duration" => 0
          }
        ],
        "draft_ids" => 1,
        "root_path" => tmp
      }

      File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))

      {:ok, projects} = Reader.list_projects(tmp)

      if match?({:win32, _}, :os.type()) do
        assert [%{id: "mixed"}] = projects
      else
        # Linux/macOS: case flip means a genuinely different directory — reject.
        assert projects == []
      end
    end

    @tag :tmp_dir
    test "list_projects skips malformed store entries (non-string keys)", %{tmp_dir: tmp} do
      meta = %{
        "all_draft_store" => [
          %{"draft_id" => "ok", "draft_name" => "OK", "draft_fold_path" => Path.join(tmp, "ok")},
          %{"draft_id" => nil, "draft_name" => "bad", "draft_fold_path" => nil},
          "scalar-not-a-map"
        ],
        "draft_ids" => 3,
        "root_path" => tmp
      }

      File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))
      assert {:ok, [p]} = Reader.list_projects(tmp)
      assert p.id == "ok"
    end
  end

  defp attach_meta_rejected_event do
    handler_id = {:meta_rejected, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:capcut_mcp, :meta, :rejected],
        fn event, measurements, metadata, _ ->
          send(test_pid, {event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp write_draft(tmp, overrides) do
    draft =
      Map.merge(
        %{"id" => "test-id", "name" => "Test", "tracks" => [], "fps" => 30.0},
        overrides
      )

    File.write!(Path.join(tmp, "draft_content.json"), Jason.encode!(draft))
  end

  defp attach_schema_version_event do
    handler_id = {:schema_version, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:capcut_mcp, :draft, :schema_version],
        fn event, measurements, metadata, _ ->
          send(test_pid, {event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
