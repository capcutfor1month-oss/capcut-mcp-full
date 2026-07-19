defmodule CapcutMcp.CapCut.PathUtilTest do
  use ExUnit.Case, async: true
  doctest CapcutMcp.CapCut.PathUtil

  alias CapcutMcp.CapCut.PathUtil

  describe "to_forward/1" do
    test "converts all backslashes to forward slashes" do
      assert PathUtil.to_forward("C:\\Users\\u\\Projects") == "C:/Users/u/Projects"
    end

    test "leaves forward-slash paths unchanged (idempotent)" do
      assert PathUtil.to_forward("C:/already/forward") == "C:/already/forward"
    end

    test "normalizes the Path.join hybrid that caused the original bug" do
      # The exact shape observed in the broken MCP-written entry:
      # %LOCALAPPDATA% returns backslashes; Path.join adds forward slashes.
      hybrid = "C:\\Users\\tspor\\AppData\\Local/CapCut/User Data/Projects"

      assert PathUtil.to_forward(hybrid) ==
               "C:/Users/tspor/AppData/Local/CapCut/User Data/Projects"
    end

    test "handles empty string" do
      assert PathUtil.to_forward("") == ""
    end

    test "collapses only separators, not backslashes inside filenames is not a concern on Windows" do
      # Windows disallows `\` in filenames, so every backslash in a path is a
      # separator. We don't need to preserve any literal backslashes.
      assert PathUtil.to_forward("\\\\\\") == "///"
    end
  end

  describe "draft_json_file/1" do
    # CapCut's on-disk convention genuinely differs by platform: Windows
    # wants "forward slashes, trailing backslash"; macOS (and everything
    # else) wants pure forward slashes throughout. These tests assert
    # against the branch that actually runs on the host running the suite,
    # rather than hardcoding the Windows shape unconditionally.
    case :os.type() do
      {:win32, _} ->
        test "produces the CapCut-native 'forward slashes, trailing backslash' shape on Windows" do
          assert PathUtil.draft_json_file("C:/Users/u/Projects/MyClip") ==
                   "C:/Users/u/Projects/MyClip\\draft_info.json"
        end

        test "normalizes a Windows-native folder path before appending the backslash+filename" do
          assert PathUtil.draft_json_file("C:\\Users\\u\\Projects\\MyClip") ==
                   "C:/Users/u/Projects/MyClip\\draft_info.json"
        end

        test "result has exactly one backslash and it sits right before the filename" do
          path = PathUtil.draft_json_file("C:\\a\\b\\c")

          assert String.ends_with?(path, "\\draft_info.json")
          # The backslash count in the final path must be 1 — anything else means
          # we leaked separator weirdness into the manifest.
          assert path |> String.graphemes() |> Enum.count(&(&1 == "\\")) == 1
        end

      _ ->
        test "produces a pure forward-slash path on macOS/Linux" do
          assert PathUtil.draft_json_file("/Users/u/Projects/MyClip") ==
                   "/Users/u/Projects/MyClip/draft_info.json"
        end

        test "normalizes a backslash-containing folder path before appending the filename" do
          assert PathUtil.draft_json_file("C:\\Users\\u\\Projects\\MyClip") ==
                   "C:/Users/u/Projects/MyClip/draft_info.json"
        end

        test "result contains no backslashes" do
          path = PathUtil.draft_json_file("/a/b/c")

          refute String.contains?(path, "\\")
          assert String.ends_with?(path, "/draft_info.json")
        end
    end
  end

  describe "draft_cover/1" do
    test "is a forward-slash path pointing at draft_cover.jpg inside the folder" do
      assert PathUtil.draft_cover("C:\\Users\\u\\Projects\\MyClip") ==
               "C:/Users/u/Projects/MyClip/draft_cover.jpg"
    end

    test "contains no backslashes" do
      refute String.contains?(PathUtil.draft_cover("C:\\a\\b\\c"), "\\")
    end
  end
end
