defmodule CapcutMcp.MCP.DispatcherInvalidArgsTest do
  @moduledoc """
  Boundary hardening: the dispatcher **must not raise** on adversarial or
  malformed `tools/call` payloads. For every registered tool we fuzz the
  `arguments` field with a random `StreamData.term()` and assert that the
  dispatch path either returns a JSON-RPC success or error string — never a
  `FunctionClauseError`, `ArgumentError`, or any other exception.

  Complements the property-based tests on the mutation layer
  (`timeline_helper_property_test.exs`) with coverage at the request boundary,
  which was the actual attack surface flagged by the security review (D16-F1).
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias CapcutMcp.CapCut.ProjectStore
  alias CapcutMcp.MCP.{Dispatcher, Protocol}

  @tool_names ~w(
    add_clip add_text create_project get_project get_timeline list_projects
    move_clip read_draft_json remove_clip set_clip_blend_mode set_clip_loop
    set_clip_opacity set_clip_transform set_clip_volume trim_clip
  )

  setup %{tmp_dir: tmp} do
    meta = %{"all_draft_store" => [], "draft_ids" => 0, "root_path" => tmp}
    File.write!(Path.join(tmp, "root_meta_info.json"), Jason.encode!(meta))
    start_supervised!({ProjectStore, [root_path: tmp]})
    :ok
  end

  describe "validate_required/2" do
    @tag :tmp_dir
    test "returns :invalid_arguments for non-map args" do
      defn = %{"inputSchema" => %{"required" => ["project_id"]}}

      for bad <- [nil, "oops", 42, [1, 2, 3], {:tuple}, :atom] do
        assert {:error, {:invalid_arguments, msg}} = Dispatcher.validate_required(defn, bad)
        assert msg =~ "arguments must be an object"
      end
    end

    @tag :tmp_dir
    test "passes :ok for valid map with all required keys" do
      defn = %{"inputSchema" => %{"required" => ["project_id"]}}
      assert :ok = Dispatcher.validate_required(defn, %{"project_id" => "abc"})
    end
  end

  describe "dispatch/1 fuzz: arguments of any shape never crash" do
    @tag :tmp_dir
    property "random terms as arguments produce a JSON string or nil (never raise)" do
      check all(
              tool_name <- StreamData.member_of(@tool_names),
              args <- StreamData.term(),
              max_runs: 40
            ) do
        payload = %{
          "jsonrpc" => "2.0",
          "id" => :rand.uniform(1_000_000),
          "method" => "tools/call",
          "params" => %{"name" => tool_name, "arguments" => args}
        }

        response =
          try do
            Dispatcher.dispatch(payload)
          rescue
            err ->
              flunk(
                "Dispatcher raised for tool=#{tool_name} args=#{inspect(args, limit: 20)}: " <>
                  Exception.format(:error, err, __STACKTRACE__)
              )
          end

        assert is_binary(response) or is_nil(response)

        if is_binary(response) do
          assert {:ok, decoded} = Jason.decode(response)
          assert decoded["jsonrpc"] == "2.0"
          assert Map.has_key?(decoded, "result") or Map.has_key?(decoded, "error")
        end
      end
    end

    @tag :tmp_dir
    test "non-map arguments get -32602 invalid_arguments, not a crash" do
      msg =
        ~s({"jsonrpc":"2.0","id":1,"method":"tools/call",) <>
          ~s("params":{"name":"remove_clip","arguments":[1,2,3]}})

      {:ok, decoded} = Protocol.decode_message(msg)

      response =
        try do
          Dispatcher.dispatch(decoded)
        rescue
          err -> flunk("Dispatcher raised: #{Exception.message(err)}")
        end

      assert {:ok, %{"error" => %{"code" => -32_602, "message" => body}}} = Jason.decode(response)
      assert body =~ "arguments must be an object"
    end

    @tag :tmp_dir
    test "stringified numeric value on set_clip_blend_mode returns an error, not a crash" do
      msg =
        ~s({"jsonrpc":"2.0","id":2,"method":"tools/call",) <>
          ~s("params":{"name":"set_clip_blend_mode","arguments":{) <>
          ~s("project_id":"X","clip_id":"Y","mode":"soft_light","value":"0.8"}}})

      {:ok, decoded} = Protocol.decode_message(msg)
      response = Dispatcher.dispatch(decoded)

      assert {:ok, %{"error" => %{"code" => -32_602, "message" => body}}} = Jason.decode(response)
      assert body =~ "Expected number"
    end

    @tag :tmp_dir
    test "stringified numeric fps on create_project returns an error, not a crash" do
      msg =
        ~s({"jsonrpc":"2.0","id":3,"method":"tools/call",) <>
          ~s("params":{"name":"create_project","arguments":{"name":"X","fps":"30"}}})

      {:ok, decoded} = Protocol.decode_message(msg)
      response = Dispatcher.dispatch(decoded)

      assert {:ok, %{"error" => %{"code" => -32_602, "message" => body}}} = Jason.decode(response)
      assert body =~ "fps"
    end
  end
end
