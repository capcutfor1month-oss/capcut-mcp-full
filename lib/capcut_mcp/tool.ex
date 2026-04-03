defmodule CapcutMcp.Tool do
  @moduledoc "Behaviour contract for MCP tool modules."

  @callback definition() :: map()
  @callback execute(args :: map()) :: {:ok, String.t()} | {:error, String.t()}
end
