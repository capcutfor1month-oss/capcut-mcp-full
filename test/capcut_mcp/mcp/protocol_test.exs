defmodule CapcutMcp.MCP.ProtocolTest do
  use ExUnit.Case, async: true
  alias CapcutMcp.MCP.Protocol

  test "decode_message parses valid JSON-RPC" do
    line = ~s({"jsonrpc":"2.0","id":1,"method":"tools/list"})
    assert {:ok, %{"method" => "tools/list", "id" => 1}} = Protocol.decode_message(line)
  end

  test "decode_message returns error for invalid JSON" do
    assert {:error, :invalid_json} = Protocol.decode_message("not json {{{")
  end

  test "decode_message returns error for missing jsonrpc field" do
    assert {:error, :invalid_jsonrpc} = Protocol.decode_message(~s({"id":1,"method":"foo"}))
  end

  test "encode_response wraps result in JSON-RPC envelope" do
    json = Protocol.encode_response(42, %{"tools" => []})
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["jsonrpc"] == "2.0"
    assert decoded["id"] == 42
    assert decoded["result"]["tools"] == []
  end

  test "encode_error wraps error in JSON-RPC envelope" do
    json = Protocol.encode_error(1, -32601, "Method not found")
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["error"]["code"] == -32601
    assert decoded["error"]["message"] == "Method not found"
    assert decoded["id"] == 1
  end

  test "encode_response with nil id" do
    json = Protocol.encode_error(nil, -32700, "Parse error")
    assert {:ok, decoded} = Jason.decode(json)
    assert decoded["id"] == nil
  end
end
