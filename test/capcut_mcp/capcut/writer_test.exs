defmodule CapcutMcp.CapCut.WriterTest do
  use ExUnit.Case, async: true
  alias CapcutMcp.CapCut.Writer

  @tag :tmp_dir
  test "write_draft creates draft_info.json when no draft file exists yet", %{tmp_dir: tmp} do
    # Neither draft_content.json nor draft_info.json exists — this is the
    # brand-new-project case. Confirmed via a live filesystem diff that
    # current CapCut (macOS) writes new projects to draft_info.json, not
    # draft_content.json — see Writer.write_draft/2's moduledoc.
    draft = %{"id" => "test-id", "name" => "Test"}
    assert :ok = Writer.write_draft(tmp, draft)
    assert File.exists?(Path.join(tmp, "draft_info.json"))
    refute File.exists?(Path.join(tmp, "draft_content.json"))
    {:ok, content} = File.read(Path.join(tmp, "draft_info.json"))
    assert {:ok, %{"id" => "test-id"}} = Jason.decode(content)
  end

  @tag :tmp_dir
  test "write_draft targets draft_info.json when only that file already exists", %{tmp_dir: tmp} do
    File.write!(Path.join(tmp, "draft_info.json"), Jason.encode!(%{"id" => "v1"}))
    assert :ok = Writer.write_draft(tmp, %{"id" => "v2"})
    {:ok, new} = File.read(Path.join(tmp, "draft_info.json"))
    assert {:ok, %{"id" => "v2"}} = Jason.decode(new)
    refute File.exists?(Path.join(tmp, "draft_content.json"))
  end

  @tag :tmp_dir
  test "write_draft creates .bak backup of existing draft_content.json file (legacy format)",
       %{tmp_dir: tmp} do
    original = %{"id" => "v1"}
    File.write!(Path.join(tmp, "draft_content.json"), Jason.encode!(original))
    assert :ok = Writer.write_draft(tmp, %{"id" => "v2"})
    {:ok, bak} = File.read(Path.join(tmp, "draft_content.json.bak"))
    assert {:ok, %{"id" => "v1"}} = Jason.decode(bak)
    {:ok, new} = File.read(Path.join(tmp, "draft_content.json"))
    assert {:ok, %{"id" => "v2"}} = Jason.decode(new)
  end

  @tag :tmp_dir
  test "write_root_meta writes root_meta_info.json", %{tmp_dir: tmp} do
    data = %{"all_draft_store" => [], "draft_ids" => 0}
    assert :ok = Writer.write_root_meta(tmp, data)
    {:ok, content} = File.read(Path.join(tmp, "root_meta_info.json"))
    assert {:ok, %{"draft_ids" => 0}} = Jason.decode(content)
  end

  @tag :tmp_dir
  test "write_root_meta without backup leaves no .bak file", %{tmp_dir: tmp} do
    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(%{"draft_ids" => 1}))
    assert :ok = Writer.write_root_meta(tmp, %{"draft_ids" => 0})
    refute File.exists?(Path.join(tmp, "root_meta_info.json.bak"))
  end

  @tag :tmp_dir
  test "write_root_meta with backup: true preserves prior contents in .bak", %{tmp_dir: tmp} do
    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(%{"draft_ids" => 1}))
    assert :ok = Writer.write_root_meta(tmp, %{"draft_ids" => 0}, backup: true)
    {:ok, bak} = File.read(Path.join(tmp, "root_meta_info.json.bak"))
    assert {:ok, %{"draft_ids" => 1}} = Jason.decode(bak)
    {:ok, new} = File.read(Path.join(tmp, "root_meta_info.json"))
    assert {:ok, %{"draft_ids" => 0}} = Jason.decode(new)
  end

  @tag :tmp_dir
  test "write_root_meta with backup: true succeeds when no prior file exists", %{tmp_dir: tmp} do
    assert :ok = Writer.write_root_meta(tmp, %{"draft_ids" => 0}, backup: true)
    refute File.exists?(Path.join(tmp, "root_meta_info.json.bak"))
    {:ok, content} = File.read(Path.join(tmp, "root_meta_info.json"))
    assert {:ok, %{"draft_ids" => 0}} = Jason.decode(content)
  end

  @tag :tmp_dir
  test "write_draft removes the .tmp file when rename/backup fails", %{tmp_dir: tmp} do
    # Make `draft_content.json` a directory so File.copy (backup) cannot succeed.
    # The .tmp file must NOT be left behind — otherwise a loop of retries
    # would litter the CapCut project folder with orphaned .tmp garbage.
    draft_dir_target = Path.join(tmp, "draft_content.json")
    File.mkdir_p!(draft_dir_target)

    assert {:error, _} = Writer.write_draft(tmp, %{"id" => "v1"})
    refute File.exists?(Path.join(tmp, "draft_content.json.tmp"))
  end
end
