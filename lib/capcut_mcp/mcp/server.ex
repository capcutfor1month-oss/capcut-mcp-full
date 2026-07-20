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
      write_line(response)
    else
      {:error, _} -> write_line(Protocol.encode_error(nil, -32_700, "Parse error"))
      nil -> :ok
    end

    Logger.reset_metadata()
    {:noreply, state}
  end

  # Write the JSON-RPC response as raw UTF-8 bytes. MUST be `binwrite`, not
  # `IO.puts`: under `-noshell` (both `mix run` and the release) stdio defaults
  # to latin1, and `IO.puts` on a latin1 device escapes any non-latin1 codepoint
  # — e.g. the "•" bullet or an accented project name — into the literal text
  # `\x{2022}`, which is not a valid JSON escape and makes the client reject the
  # whole message ("Bad escaped character in JSON"). `Jason.encode!/1` already
  # returns a proper UTF-8 binary; `binwrite` emits those bytes verbatim,
  # bypassing the device's character encoding entirely.
  defp write_line(iodata) do
    IO.binwrite(:stdio, [iodata, ?\n])
  end

  def handle_info(:eof, state) do
    Logger.info("stdin closed — shutting down")
    # The MCP client closed stdin, which is its signal to shut down. Stop
    # the whole runtime gracefully with exit status 0. Using `System.stop/1`
    # (rather than `{:stop, :normal, state}`) matters when running as a
    # release: a `:permanent` application terminating on its own brings the
    # node down abnormally ("Kernel pid terminated") and writes an
    # `erl_crash.dump`. `System.stop/0` runs every application's shutdown
    # callbacks in order and exits cleanly with no crash dump.
    System.stop(0)
    {:noreply, state}
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
