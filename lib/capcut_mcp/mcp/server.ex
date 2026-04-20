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
         response when not is_nil(response) <- Dispatcher.dispatch(msg) do
      IO.puts(:stdio, response)
    else
      {:error, _} -> IO.puts(:stdio, Protocol.encode_error(nil, -32700, "Parse error"))
      nil -> :ok
    end

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
end
