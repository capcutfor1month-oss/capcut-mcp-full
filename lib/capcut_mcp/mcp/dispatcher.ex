defmodule CapcutMcp.MCP.Dispatcher do
  @moduledoc "Routes JSON-RPC tool calls to the appropriate tool module."
  alias CapcutMcp.MCP.Protocol

  alias CapcutMcp.Tools.{
    ListProjects,
    GetProject,
    GetTimeline,
    CreateProject,
    AddText,
    AddClip,
    RemoveClip,
    ReadDraftJson,
    SetClipVolume,
    SetClipLoop,
    MoveClip,
    SetClipTransform,
    SetClipOpacity,
    TrimClip,
    SetClipBlendMode
  }

  @tools [
    ListProjects,
    GetProject,
    GetTimeline,
    CreateProject,
    AddText,
    AddClip,
    RemoveClip,
    ReadDraftJson,
    SetClipVolume,
    SetClipLoop,
    MoveClip,
    SetClipTransform,
    SetClipOpacity,
    TrimClip,
    SetClipBlendMode
  ]

  def dispatch(%{"method" => "initialize", "id" => id}) do
    Protocol.encode_response(id, %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "capcut-mcp", "version" => "0.1.0"}
    })
  end

  def dispatch(%{"method" => method})
      when method in ["notifications/initialized", "notifications/cancelled"] do
    nil
  end

  def dispatch(%{"method" => "tools/list", "id" => id}) do
    tools = Enum.map(@tools, & &1.definition())
    Protocol.encode_response(id, %{"tools" => tools})
  end

  def dispatch(%{
        "method" => "tools/call",
        "id" => id,
        "params" => %{"name" => name, "arguments" => args}
      }) do
    case Enum.find(@tools, fn t -> t.definition()["name"] == name end) do
      nil ->
        Protocol.encode_error(id, -32601, "Tool not found: #{name}")

      tool ->
        case tool.execute(args) do
          {:ok, text} ->
            Protocol.encode_response(id, %{"content" => [%{"type" => "text", "text" => text}]})

          {:error, reason} ->
            Protocol.encode_error(id, -32602, to_string(reason))
        end
    end
  end

  def dispatch(%{"id" => id}) do
    Protocol.encode_error(id, -32601, "Method not found")
  end

  def dispatch(_msg), do: nil
end
