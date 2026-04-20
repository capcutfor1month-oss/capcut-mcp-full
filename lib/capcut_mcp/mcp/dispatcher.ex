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

  @tool_definitions Enum.map(@tools, & &1.definition())
  @tool_by_name Map.new(@tools, fn mod -> {mod.definition()["name"], mod} end)

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
    Protocol.encode_response(id, %{"tools" => @tool_definitions})
  end

  def dispatch(%{
        "method" => "tools/call",
        "id" => id,
        "params" => %{"name" => name} = params
      }) do
    args = Map.get(params, "arguments", %{})

    with {:ok, tool} <- fetch_tool(name),
         :ok <- validate_required(tool.definition(), args),
         {:ok, text} <- tool.execute(args) do
      Protocol.encode_response(id, %{"content" => [%{"type" => "text", "text" => text}]})
    else
      {:error, :tool_not_found} ->
        Protocol.encode_error(id, -32601, "Tool not found: #{name}")

      {:error, {:missing_required, msg}} ->
        Protocol.encode_error(id, -32602, msg)

      {:error, reason} ->
        Protocol.encode_error(id, -32602, to_string(reason))
    end
  end

  def dispatch(%{"id" => id}) do
    Protocol.encode_error(id, -32601, "Method not found")
  end

  def dispatch(_msg), do: nil

  # ── Internals ────────────────────────────────────────────────────────────────

  defp fetch_tool(name) do
    case Map.fetch(@tool_by_name, name) do
      {:ok, tool} -> {:ok, tool}
      :error -> {:error, :tool_not_found}
    end
  end

  @doc false
  def validate_required(%{"inputSchema" => %{"required" => required}}, args)
      when is_list(required) and is_map(args) do
    case Enum.reject(required, &Map.has_key?(args, &1)) do
      [] ->
        :ok

      missing ->
        {:error, {:missing_required, "Missing required arguments: #{Enum.join(missing, ", ")}"}}
    end
  end

  def validate_required(_definition, _args), do: :ok
end
