defmodule CapcutMcp.MCP.StdinReader do
  @moduledoc """
  Reads JSON-RPC lines from stdin and forwards them to `CapcutMcp.MCP.Server`.

  Runs as its own supervised `Task` so the reader's failure mode is visible to
  the supervision tree (instead of hiding inside a `spawn_link/1` from the
  server's `init/1`). If the reader dies, the supervisor restarts it; if stdin
  closes cleanly (`:eof`), the task exits normally and the server is told to
  shut down.
  """

  use Task, restart: :transient
  require Logger

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(opts) do
    target = Keyword.get(opts, :target, CapcutMcp.MCP.Server)
    Task.start_link(__MODULE__, :loop, [target])
  end

  @doc false
  def loop(target) do
    # `binread`, not `IO.read`: under `-noshell` stdio is latin1, so `IO.read`
    # would corrupt any non-ASCII (UTF-8) bytes in an incoming request — e.g. a
    # project name argument with an accent. Reading raw bytes keeps the JSON-RPC
    # transport byte-clean UTF-8 end to end (see the matching `binwrite` on the
    # response side in `CapcutMcp.MCP.Server`).
    case IO.binread(:stdio, :line) do
      :eof ->
        send_to(target, :eof)

      {:error, reason} ->
        send_to(target, {:stdin_error, reason})

      line when is_binary(line) ->
        case String.trim(line) do
          "" -> :ok
          trimmed -> send_to(target, {:line, trimmed})
        end

        loop(target)
    end
  end

  defp send_to(target, msg) do
    case resolve(target) do
      nil ->
        Logger.warning(
          "StdinReader: target #{inspect(target)} not registered; dropping #{inspect(msg)}"
        )

      pid ->
        send(pid, msg)
    end
  end

  defp resolve(pid) when is_pid(pid), do: pid
  defp resolve(name) when is_atom(name), do: Process.whereis(name)
end
