defmodule CapcutMcp.MCP.Dispatcher do
  @moduledoc "Routes JSON-RPC tool calls to the appropriate tool module."
  require Logger
  alias CapcutMcp.MCP.Protocol

  alias CapcutMcp.Tools.{
    AddClip,
    AddText,
    AddTextAnimation,
    CreateProject,
    GetProject,
    GetTimeline,
    ListProjects,
    ListTextAnimations,
    MoveClip,
    ReadDraftJson,
    RemoveClip,
    RemoveProject,
    SetClipBlendMode,
    SetClipKeyframe,
    SetClipLoop,
    SetClipOpacity,
    SetClipTransform,
    SetClipVolume,
    TrimClip
  }

  @tools [
    AddClip,
    AddText,
    AddTextAnimation,
    CreateProject,
    GetProject,
    GetTimeline,
    ListProjects,
    ListTextAnimations,
    MoveClip,
    ReadDraftJson,
    RemoveClip,
    RemoveProject,
    SetClipBlendMode,
    SetClipKeyframe,
    SetClipLoop,
    SetClipOpacity,
    SetClipTransform,
    SetClipVolume,
    TrimClip
  ]

  @tool_definitions Enum.map(@tools, & &1.definition())
  @tool_by_name Map.new(@tools, fn mod -> {mod.definition()["name"], mod} end)

  @spec dispatch(map()) :: String.t() | nil
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
    Logger.metadata(tool: name, request_id: id)

    :telemetry.span(
      [:capcut_mcp, :tool, :execute],
      %{tool: name, request_id: id},
      fn -> run_and_encode(id, name, args) end
    )
  end

  def dispatch(%{"id" => id}) do
    Protocol.encode_error(id, -32_601, "Method not found")
  end

  def dispatch(_msg), do: nil

  # ── Internals ────────────────────────────────────────────────────────────────

  # Executes the tool, encodes the response, and returns a
  # `{response, stop_metadata}` pair as expected by `:telemetry.span/3`.
  defp run_and_encode(id, name, args) do
    case run_tool(name, args) do
      {:ok, text} ->
        {Protocol.encode_response(id, %{"content" => [%{"type" => "text", "text" => text}]}),
         %{tool: name, request_id: id, result: :ok}}

      {:error, :tool_not_found} ->
        {Protocol.encode_error(id, -32_601, "Tool not found: #{name}"),
         %{tool: name, request_id: id, result: :error, reason: :tool_not_found}}

      {:error, {:missing_required, msg}} ->
        {Protocol.encode_error(id, -32_602, msg),
         %{tool: name, request_id: id, result: :error, reason: :missing_required}}

      {:error, {:invalid_arguments, msg}} ->
        {Protocol.encode_error(id, -32_602, msg),
         %{tool: name, request_id: id, result: :error, reason: :invalid_arguments}}

      {:error, reason} when is_binary(reason) ->
        {Protocol.encode_error(id, -32_602, reason),
         %{tool: name, request_id: id, result: :error, reason: reason}}

      {:error, reason} ->
        {Protocol.encode_error(id, -32_602, inspect(reason)),
         %{tool: name, request_id: id, result: :error, reason: reason}}
    end
  end

  defp run_tool(name, args) do
    with {:ok, tool} <- fetch_tool(name),
         :ok <- validate_required(tool.definition(), args) do
      tool.execute(args)
    end
  end

  defp fetch_tool(name) do
    case Map.fetch(@tool_by_name, name) do
      {:ok, tool} -> {:ok, tool}
      :error -> {:error, :tool_not_found}
    end
  end

  @doc false
  def validate_required(_definition, args) when not is_map(args) do
    {:error, {:invalid_arguments, "arguments must be an object, got #{inspect(args, limit: 20)}"}}
  end

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
