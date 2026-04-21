defmodule CapcutMcp.MCP.DispatcherIntegrationTest do
  @moduledoc """
  Integration tests driving the full JSON-RPC stack:
  raw JSON string → `Protocol.decode_message/1` → `Dispatcher.dispatch/1`
  → parsed response, plus assertions on the `:telemetry` events emitted
  around `tools/call` dispatch.

  The tests share a `ProjectStore` seeded from a temporary directory so the
  happy-path tool calls actually resolve against a real draft on disk. The
  telemetry handlers are attached per-test and detached via `on_exit/1` so
  the global `:telemetry` registry stays clean.
  """

  use ExUnit.Case, async: false

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.MCP.{Dispatcher, Protocol}

  @tool_execute_events [
    [:capcut_mcp, :tool, :execute, :start],
    [:capcut_mcp, :tool, :execute, :stop],
    [:capcut_mcp, :tool, :execute, :exception]
  ]

  @cache_events [
    [:capcut_mcp, :cache, :hit],
    [:capcut_mcp, :cache, :miss],
    [:capcut_mcp, :cache, :write]
  ]

  setup %{tmp_dir: tmp} do
    project_id = "INT-TEST-001"
    project_path = Path.join(tmp, "integration_test_project")
    File.mkdir_p!(project_path)

    draft = %{
      "id" => project_id,
      "name" => "Integration Test",
      "fps" => 30.0,
      "duration" => 10_000_000,
      "new_version" => "163.0.0",
      "canvas_config" => %{
        "width" => 1920,
        "height" => 1080,
        "ratio" => "original",
        "background" => nil
      },
      "tracks" => [
        %{
          "id" => "track-001",
          "type" => "text",
          "segments" => [
            %{
              "id" => "seg-001",
              "material_id" => "mat-001",
              "target_timerange" => %{"start" => 0, "duration" => 3_000_000},
              "source_timerange" => %{"start" => 0, "duration" => 3_000_000}
            }
          ]
        }
      ],
      "materials" => %{}
    }

    File.write!(Path.join(project_path, "draft_content.json"), Jason.encode!(draft))

    meta = %{
      "all_draft_store" => [
        %{
          "draft_id" => project_id,
          "draft_name" => "Integration Test",
          "draft_fold_path" => project_path,
          "draft_json_file" => Path.join(project_path, "draft_content.json"),
          "tm_draft_modified" => 1_750_000_000_000_000,
          "tm_duration" => 10_000_000
        }
      ],
      "draft_ids" => 1,
      "root_path" => tmp
    }

    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))

    start_supervised!({ProjectStore, [root_path: tmp]})
    %{project_id: project_id}
  end

  # ── Envelope-only cases (no ProjectStore needed, but harmless to have it) ──

  @tag :tmp_dir
  test "initialize returns protocolVersion and serverInfo" do
    msg = ~s({"jsonrpc":"2.0","id":1,"method":"initialize"})
    response = dispatch(msg)

    assert %{"id" => 1, "jsonrpc" => "2.0", "result" => result} = response
    assert result["protocolVersion"] == "2024-11-05"
    assert result["serverInfo"]["name"] == "capcut-mcp"
    assert is_map(result["capabilities"])
  end

  @tag :tmp_dir
  test "notifications/initialized produces no response" do
    msg = ~s({"jsonrpc":"2.0","method":"notifications/initialized"})
    {:ok, decoded} = Protocol.decode_message(msg)
    assert Dispatcher.dispatch(decoded) == nil
  end

  @tag :tmp_dir
  test "notifications/cancelled produces no response" do
    msg = ~s({"jsonrpc":"2.0","method":"notifications/cancelled"})
    {:ok, decoded} = Protocol.decode_message(msg)
    assert Dispatcher.dispatch(decoded) == nil
  end

  @tag :tmp_dir
  test "tools/list returns all registered tools with input schemas" do
    msg = ~s({"jsonrpc":"2.0","id":2,"method":"tools/list"})
    response = dispatch(msg)

    assert %{"result" => %{"tools" => tools}} = response
    assert length(tools) == 16
    assert Enum.all?(tools, &is_map(&1["inputSchema"]))
    assert Enum.all?(tools, &is_binary(&1["name"]))

    names = Enum.map(tools, & &1["name"])
    assert "list_projects" in names
    assert "add_text" in names
    assert "remove_project" in names
  end

  @tag :tmp_dir
  test "unknown method returns -32601 Method not found" do
    msg = ~s({"jsonrpc":"2.0","id":99,"method":"does/not/exist"})
    response = dispatch(msg)

    assert %{"id" => 99, "error" => %{"code" => -32_601, "message" => "Method not found"}} =
             response
  end

  # ── tools/call + telemetry cases ───────────────────────────────────────────

  @tag :tmp_dir
  test "tools/call list_projects emits start + stop telemetry with :ok", %{project_id: id} do
    attach_tool_events()

    msg =
      ~s({"jsonrpc":"2.0","id":3,"method":"tools/call",) <>
        ~s("params":{"name":"list_projects","arguments":{}}})

    response = dispatch(msg)

    assert %{"result" => %{"content" => [%{"type" => "text", "text" => text}]}} = response
    assert text =~ "Integration Test"
    assert text =~ id

    assert_receive {[:capcut_mcp, :tool, :execute, :start], _measurements,
                    %{tool: "list_projects", request_id: 3}}

    assert_receive {[:capcut_mcp, :tool, :execute, :stop], %{duration: duration},
                    %{tool: "list_projects", result: :ok}}

    assert is_integer(duration) and duration >= 0
  end

  @tag :tmp_dir
  test "tools/call with missing required argument returns -32602 and reason :missing_required" do
    attach_tool_events()

    msg =
      ~s({"jsonrpc":"2.0","id":4,"method":"tools/call",) <>
        ~s("params":{"name":"get_project","arguments":{}}})

    response = dispatch(msg)

    assert %{"id" => 4, "error" => %{"code" => -32_602, "message" => message}} = response
    assert message =~ "project_id"

    assert_receive {[:capcut_mcp, :tool, :execute, :stop], _measurements,
                    %{tool: "get_project", result: :error, reason: :missing_required}}
  end

  @tag :tmp_dir
  test "tools/call with unknown tool returns -32601 and reason :tool_not_found" do
    attach_tool_events()

    msg =
      ~s({"jsonrpc":"2.0","id":5,"method":"tools/call",) <>
        ~s("params":{"name":"imaginary_tool","arguments":{}}})

    response = dispatch(msg)

    assert %{"id" => 5, "error" => %{"code" => -32_601, "message" => message}} = response
    assert message =~ "imaginary_tool"

    assert_receive {[:capcut_mcp, :tool, :execute, :stop], _measurements,
                    %{tool: "imaginary_tool", result: :error, reason: :tool_not_found}}
  end

  @tag :tmp_dir
  test "tools/call with tool-level error surfaces as -32602 and reason string" do
    attach_tool_events()

    msg =
      ~s({"jsonrpc":"2.0","id":6,"method":"tools/call",) <>
        ~s("params":{"name":"get_project","arguments":{"project_id":"NOPE"}}})

    response = dispatch(msg)

    assert %{"id" => 6, "error" => %{"code" => -32_602, "message" => message}} = response
    assert message =~ "not found"

    assert_receive {[:capcut_mcp, :tool, :execute, :stop], _measurements,
                    %{tool: "get_project", result: :error, reason: reason}}

    assert is_binary(reason) and reason =~ "not found"
  end

  @tag :tmp_dir
  test "two get_project calls emit miss+write then hit on the cache layer", %{project_id: id} do
    attach_cache_events()

    msg =
      ~s({"jsonrpc":"2.0","id":10,"method":"tools/call",) <>
        ~s("params":{"name":"get_project","arguments":{"project_id":") <>
        id <> ~s("}}})

    dispatch(msg)

    assert_receive {[:capcut_mcp, :cache, :miss], _, %{id: ^id}}
    assert_receive {[:capcut_mcp, :cache, :write], _, %{id: ^id, reason: :load}}

    dispatch(msg)

    assert_receive {[:capcut_mcp, :cache, :hit], _, %{id: ^id}}
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  # Decodes a raw JSON-RPC string, runs it through the dispatcher, and
  # decodes the response back to a map for assertion convenience.
  defp dispatch(raw_msg) do
    {:ok, decoded} = Protocol.decode_message(raw_msg)
    response_json = Dispatcher.dispatch(decoded)
    assert is_binary(response_json), "expected dispatcher to return a JSON string"
    {:ok, parsed} = Jason.decode(response_json)
    parsed
  end

  # Attaches a telemetry handler that forwards every tool-execute event
  # (`:start`, `:stop`, `:exception`) as a message to the current test
  # process, then detaches it at the end of the test.
  defp attach_tool_events do
    handler_id = {:tool_events, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        @tool_execute_events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp attach_cache_events do
    handler_id = {:cache_events, make_ref()}
    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        @cache_events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {event, measurements, metadata})
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
