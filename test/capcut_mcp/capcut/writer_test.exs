defmodule CapcutMcp.CapCut.WriterTest do
  use ExUnit.Case, async: true
  alias CapcutMcp.CapCut.Writer

  @tag :tmp_dir
  test "write_draft creates draft_content.json", %{tmp_dir: tmp} do
    draft = %{"id" => "test-id", "name" => "Test"}
    assert :ok = Writer.write_draft(tmp, draft)
    assert File.exists?(Path.join(tmp, "draft_content.json"))
    {:ok, content} = File.read(Path.join(tmp, "draft_content.json"))
    assert {:ok, %{"id" => "test-id"}} = Jason.decode(content)
  end

  @tag :tmp_dir
  test "write_draft creates .bak backup of existing file", %{tmp_dir: tmp} do
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
end
