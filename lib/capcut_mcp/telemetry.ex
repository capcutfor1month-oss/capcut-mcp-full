defmodule CapcutMcp.Telemetry do
  @moduledoc """
  Telemetry event definitions and the default log handler.

  ## Events

    * `[:capcut_mcp, :tool, :execute, :start]`
      * **measurements**: `:system_time`, `:monotonic_time`
      * **metadata**: `:tool`, `:request_id`
    * `[:capcut_mcp, :tool, :execute, :stop]`
      * **measurements**: `:duration` (native time units), `:monotonic_time`
      * **metadata**: `:tool`, `:request_id`, `:result` (`:ok` | `:error`),
        optional `:reason`
    * `[:capcut_mcp, :tool, :execute, :exception]` — emitted automatically by
      `:telemetry.span/3` if the tool function raises.
      * **metadata**: `:tool`, `:request_id`, `:kind`, `:reason`, `:stacktrace`

  The events are emitted in `CapcutMcp.MCP.Dispatcher` around every
  `tools/call` execution. Downstream consumers (Prometheus exporter, log
  ingestion, OpenTelemetry bridge, …) only need to attach a handler here.
  """
  require Logger

  @handler_id "capcut-mcp-default-logger"

  @events [
    [:capcut_mcp, :tool, :execute, :stop],
    [:capcut_mcp, :tool, :execute, :exception]
  ]

  @doc """
  Attaches a default handler that logs every tool-call's duration and outcome
  via `Logger`. Safe to call multiple times — duplicate attach attempts are
  ignored.
  """
  @spec attach_default_logger() :: :ok
  def attach_default_logger do
    case :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc "Detaches the default log handler. Mainly useful from tests."
  @spec detach_default_logger() :: :ok
  def detach_default_logger do
    _ = :telemetry.detach(@handler_id)
    :ok
  end

  @doc false
  def handle_event([:capcut_mcp, :tool, :execute, :stop], %{duration: duration}, meta, _cfg) do
    Logger.info(fn ->
      "tool=#{meta.tool} result=#{meta.result} duration=#{format_ms(duration)}ms"
    end)
  end

  def handle_event(
        [:capcut_mcp, :tool, :execute, :exception],
        %{duration: duration},
        meta,
        _cfg
      ) do
    Logger.error(fn ->
      "tool=#{meta.tool} crashed kind=#{meta.kind} duration=#{format_ms(duration)}ms"
    end)
  end

  defp format_ms(duration_native) do
    duration_native
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
    |> :erlang.float_to_binary(decimals: 2)
  end
end
