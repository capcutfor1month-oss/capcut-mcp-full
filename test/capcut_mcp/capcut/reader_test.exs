defmodule CapcutMcp.CapCut.ReaderTest do
  use ExUnit.Case, async: true
  alias CapcutMcp.CapCut.Reader
  alias CapcutMcp.CapCut.ProjectMeta

  @tag :tmp_dir
  test "list_projects returns empty list when no drafts", %{tmp_dir: tmp} do
    meta = %{"all_draft_store" => [], "draft_ids" => 0, "root_path" => tmp}
    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))
    assert {:ok, []} = Reader.list_projects(tmp)
  end

  @tag :tmp_dir
  test "list_projects returns ProjectMeta list", %{tmp_dir: tmp} do
    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => "abc-123",
          "draft_name" => "My Video",
          "draft_fold_path" => "/some/path",
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
             path: "/some/path",
             modified_at: 1_000_000_000_000_000,
             duration_ms: 5000
           } = project
  end

  @tag :tmp_dir
  test "list_projects returns error when file missing", %{tmp_dir: tmp} do
    assert {:error, _} = Reader.list_projects(tmp)
  end

  @tag :tmp_dir
  test "read_draft returns parsed map", %{tmp_dir: tmp} do
    draft = %{"id" => "test-id", "name" => "Test", "tracks" => [], "fps" => 30.0}
    File.write!(Path.join(tmp, "draft_content.json"), Jason.encode!(draft))
    assert {:ok, %{"id" => "test-id", "name" => "Test"}} = Reader.read_draft(tmp)
  end

  @tag :tmp_dir
  test "read_draft returns error when file missing", %{tmp_dir: tmp} do
    assert {:error, _} = Reader.read_draft(tmp)
  end
end
