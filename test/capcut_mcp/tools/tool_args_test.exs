defmodule CapcutMcp.Tools.ToolArgsTest do
  @moduledoc """
  Exercises every branch of the shared tool-argument helpers. Kept deliberately
  flat — these are pure functions, so no setup or fixtures are needed.
  """

  use ExUnit.Case, async: true

  alias CapcutMcp.Tools.ToolArgs

  doctest ToolArgs

  describe "to_float/1" do
    test "widens positive integers" do
      assert ToolArgs.to_float(3) === 3.0
    end

    test "widens zero" do
      assert ToolArgs.to_float(0) === 0.0
    end

    test "widens negative integers" do
      assert ToolArgs.to_float(-7) === -7.0
    end

    test "passes floats through unchanged" do
      assert ToolArgs.to_float(0.25) === 0.25
      assert ToolArgs.to_float(-1.5) === -1.5
    end
  end

  describe "missing_required_message/2" do
    test "lists missing keys when some are absent" do
      msg = ToolArgs.missing_required_message(%{"present" => 1}, ["present", "gone", "also_gone"])
      assert msg =~ "Missing required arguments"
      assert msg =~ "gone"
      assert msg =~ "also_gone"
      refute msg =~ "present"
    end

    test "lists missing keys when none are present" do
      msg = ToolArgs.missing_required_message(%{}, ["project_id", "clip_id"])
      assert msg =~ "project_id"
      assert msg =~ "clip_id"
    end

    test "falls back to invalid-shape message when all required keys are present" do
      msg = ToolArgs.missing_required_message(%{"a" => 1, "b" => 2}, ["a", "b"])
      assert msg =~ "Invalid arguments"
      assert msg =~ "a, b"
    end

    test "handles non-map args" do
      msg = ToolArgs.missing_required_message("not a map", ["a", "b"])
      assert msg =~ "Invalid arguments"
      assert msg =~ "expected object"
      assert msg =~ "a, b"
    end

    test "handles nil args" do
      msg = ToolArgs.missing_required_message(nil, ["x"])
      assert msg =~ "expected object"
      assert msg =~ "x"
    end
  end

  describe "format_tool_result/2" do
    test "passes :ok tuples through unchanged" do
      assert ToolArgs.format_tool_result({:ok, "done"}, "pid") == {:ok, "done"}
      assert ToolArgs.format_tool_result({:ok, %{foo: :bar}}, "pid") == {:ok, %{foo: :bar}}
    end

    test "turns :not_found into a human message including the project id" do
      assert ToolArgs.format_tool_result({:error, :not_found}, "PROJ-123") ==
               {:error, "Project not found: PROJ-123"}
    end

    test "passes binary error reasons through unchanged" do
      assert ToolArgs.format_tool_result({:error, "blank file_path"}, "pid") ==
               {:error, "blank file_path"}
    end

    test "inspects non-binary, non-:not_found error reasons" do
      assert {:error, reason} = ToolArgs.format_tool_result({:error, :enoent}, "pid")
      assert reason == ":enoent"

      assert {:error, tuple_reason} =
               ToolArgs.format_tool_result({:error, {:backup_failed, :eacces}}, "pid")

      assert tuple_reason =~ "backup_failed"
      assert tuple_reason =~ "eacces"
    end
  end
end
