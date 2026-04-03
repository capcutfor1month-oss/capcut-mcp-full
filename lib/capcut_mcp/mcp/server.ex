defmodule CapcutMcp.MCP.Server do
  @moduledoc "GenServer that reads JSON-RPC messages from stdin and dispatches them."
  use GenServer
  require Logger
  alias CapcutMcp.MCP.{Protocol, Dispatcher}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    server_pid = self()
    spawn_link(fn -> stdin_loop(server_pid) end)
    Logger.info("CapCut MCP Server started — waiting for messages on stdin")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:line, line}, state) do
    case Protocol.decode_message(line) do
      {:ok, msg} ->
        case Dispatcher.dispatch(msg) do
          nil -> :ok
          response -> IO.puts(response)
        end
      {:error, _} ->
        IO.puts(Protocol.encode_error(nil, -32700, "Parse error"))
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

  defp stdin_loop(server_pid) do
    case IO.read(:stdio, :line) do
      :eof ->
        send(server_pid, :eof)
      {:error, reason} ->
        send(server_pid, {:stdin_error, reason})
      line ->
        trimmed = String.trim(line)
        unless trimmed == "", do: send(server_pid, {:line, trimmed})
        stdin_loop(server_pid)
    end
  end
end
