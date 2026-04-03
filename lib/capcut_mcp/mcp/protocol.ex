defmodule CapcutMcp.MCP.Protocol do
  @moduledoc "JSON-RPC 2.0 encode/decode for the MCP stdio transport."

  @doc "Decodes a JSON-RPC 2.0 message from a raw string line"
  @spec decode_message(String.t()) :: {:ok, map()} | {:error, :invalid_json | :invalid_jsonrpc}
  def decode_message(line) do
    case Jason.decode(line) do
      {:ok, %{"jsonrpc" => "2.0"} = msg} -> {:ok, msg}
      {:ok, _} -> {:error, :invalid_jsonrpc}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  @doc "Encodes a successful JSON-RPC 2.0 response"
  @spec encode_response(term(), map()) :: String.t()
  def encode_response(id, result) do
    Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  @doc "Encodes a JSON-RPC 2.0 error response"
  @spec encode_error(term(), integer(), String.t()) :: String.t()
  def encode_error(id, code, message) do
    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message}
    })
  end
end
