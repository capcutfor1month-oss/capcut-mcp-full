defmodule CapcutMcp.MCP.Server do
  @moduledoc """
  GenServer that handles JSON-RPC messages forwarded from `CapcutMcp.MCP.StdinReader`.

  Decoding, dispatching, and stdout replies live here; stdin reading lives in a
  separate supervised `Task` so each concern has its own failure domain.
  """
  use GenServer
  require Logger
  alias CapcutMcp.MCP.{Dispatcher, Protocol}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("CapCut MCP Server started — waiting for messages on stdin")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:line, line}, state) do
    with {:ok, msg} <- Protocol.decode_message(line),
         :ok <- set_request_metadata(msg),
         response when not is_nil(response) <- Dispatcher.dispatch(msg) do
      IO.puts(:stdio, response)
    else
      {:error, _} -> IO.puts(:stdio, Protocol.encode_error(nil, -32_700, "Parse error"))
      nil -> :ok
    end

    Logger.reset_metadata()
    {:noreply, state}
  end

  def handle_info(:eof, state) do
    Logger.info("stdin closed — shutting down")
    {:stop, :normal, state}
  end

  def handle_info({:stdin_error, reason}, state) do
    Logger.error("stdin error: #{inspect(reason)}")
    {:stop, reason, state}
  end

  # Tag every log emitted downstream with the MCP request id + method so we can
  # `grep mcp_request_id=42` across the whole pipeline, including tool code.
  defp set_request_metadata(%{} = msg) do
    Logger.metadata(
      mcp_request_id: Map.get(msg, "id"),
      mcp_method: Map.get(msg, "method")
    )

    :ok
  end
end
