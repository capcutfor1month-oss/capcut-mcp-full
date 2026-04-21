defmodule CapcutMcp.Tools.ListProjectsTest do
  @moduledoc """
  Boundary coverage for `ListProjects.execute/1` against corrupt
  `root_meta_info.json` metadata: invalid timestamp shapes must surface as
  `"Modified: unknown"` instead of crashing the tool (D16-F4).
  """

  use ExUnit.Case, async: false

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.Tools.ListProjects

  describe "execute/1 corrupted timestamps" do
    @tag :tmp_dir
    test "renders 'unknown' for string-shaped tm_draft_modified", %{tmp_dir: tmp} do
      project_path = Path.join(tmp, "string_ts_project")
      File.mkdir_p!(project_path)

      meta = %{
        "all_draft_store" => [
          %{
            "draft_id" => "weird-1",
            "draft_name" => "Weird Timestamps",
            "draft_fold_path" => project_path,
            "tm_draft_modified" => "not-a-number",
            "tm_duration" => 0
          }
        ],
        "draft_ids" => 1,
        "root_path" => tmp
      }

      File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))
      start_supervised!({ProjectStore, [root_path: tmp]})

      assert {:ok, text} = ListProjects.execute(%{})
      assert text =~ "Weird Timestamps"
      assert text =~ "Modified: unknown"
    end

    @tag :tmp_dir
    test "renders 'unknown' for overflowed unix timestamps", %{tmp_dir: tmp} do
      project_path = Path.join(tmp, "overflow_project")
      File.mkdir_p!(project_path)

      # 10^22 microseconds ≈ year 317_097 — far beyond `DateTime.from_unix/1`'s
      # supported range of 0..9999, so the /! variant would raise.
      meta = %{
        "all_draft_store" => [
          %{
            "draft_id" => "overflow-1",
            "draft_name" => "Overflow",
            "draft_fold_path" => project_path,
            "tm_draft_modified" => 10_000_000_000_000_000_000_000,
            "tm_duration" => 0
          }
        ],
        "draft_ids" => 1,
        "root_path" => tmp
      }

      File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))
      start_supervised!({ProjectStore, [root_path: tmp]})

      assert {:ok, text} = ListProjects.execute(%{})
      assert text =~ "Overflow"
      assert text =~ "Modified: unknown"
    end
  end
end
