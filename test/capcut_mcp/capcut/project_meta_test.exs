defmodule CapcutMcp.CapCut.ProjectMetaTest do
  use ExUnit.Case, async: true
  alias CapcutMcp.CapCut.ProjectMeta

  test "ProjectMeta struct requires id, name, path" do
    meta = %ProjectMeta{id: "abc", name: "My Video", path: "/some/path"}
    assert meta.id == "abc"
    assert meta.name == "My Video"
    assert meta.path == "/some/path"
    assert meta.duration_ms == nil
  end

  test "ProjectMeta raises on missing required fields" do
    assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
      struct!(ProjectMeta, %{id: "abc"})
    end
  end
end
