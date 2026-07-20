defmodule CapcutMcp.MCP.ServerEncodingTest do
  @moduledoc """
  Regression test for the "Bad escaped character in JSON" bug.

  Under `-noshell` (both `mix run --no-halt` and the release), the BEAM's
  stdio device defaults to latin1. `IO.puts/2` on a latin1 device escapes any
  codepoint above 255 — e.g. the "•" bullet in `list_projects` output or an
  accented project name — into the *literal* text `\\x{2022}`, which is not a
  valid JSON escape, so the MCP client rejects the entire message and every
  tool call times out. The fix is `IO.binwrite/2`, which emits the already-UTF-8
  `Jason.encode!/1` bytes verbatim regardless of the device encoding.

  This test drives `Server.handle_info/2` directly (so it runs in the test
  process and its writes land in the captured device) under a **latin1**
  capture, exactly reproducing the production condition.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.MCP.Server

  setup %{tmp_dir: tmp} do
    project_id = "ENC-TEST-1"
    # Name deliberately carries both an accented letter and a bullet so the
    # encoded response is guaranteed to contain codepoints > 255.
    name = "Café • Draft"
    project_path = Path.join(tmp, "encoding_test_project")
    File.mkdir_p!(project_path)

    draft = %{
      "id" => project_id,
      "name" => name,
      "fps" => 30.0,
      "duration" => 0,
      "new_version" => "163.0.0",
      "canvas_config" => %{"width" => 1920, "height" => 1080, "ratio" => "original"},
      "tracks" => [],
      "materials" => %{}
    }

    File.write!(Path.join(project_path, "draft_content.json"), Jason.encode!(draft))

    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => project_id,
          "draft_name" => name,
          "draft_fold_path" => project_path,
          "draft_json_file" => Path.join(project_path, "draft_content.json"),
          "tm_draft_modified" => 1_750_000_000_000_000,
          "tm_duration" => 0
        }
      ],
      "draft_ids" => 1,
      "root_path" => tmp
    }

    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))
    start_supervised!({ProjectStore, [root_path: tmp]})
    :ok
  end

  @tag :tmp_dir
  test "a non-ASCII tool response is valid JSON on a latin1 stdio device" do
    request =
      ~s({"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"list_projects","arguments":{}}})

    output =
      capture_io([encoding: :latin1], fn ->
        assert {:noreply, _} = Server.handle_info({:line, request}, %{})
      end)

    # The literal broken-escape sequence must NOT appear...
    refute output =~ "\\x{",
           "response leaked an Elixir codepoint escape — reverted to IO.puts on a latin1 device?"

    # ...and the emitted bytes must parse as JSON and round-trip the real chars.
    decoded = output |> String.trim() |> Jason.decode!()
    text = decoded["result"]["content"] |> hd() |> Map.get("text")

    assert text =~ "•"
    assert text =~ "Café"
  end
end
