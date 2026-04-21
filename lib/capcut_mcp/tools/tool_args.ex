defmodule CapcutMcp.Tools.ToolArgs do
  @moduledoc "Shared argument validation and error formatting helpers for tool modules."

  @spec missing_required_message(map() | term(), [String.t()]) :: String.t()
  def missing_required_message(args, required_keys) when is_map(args) do
    missing_keys = Enum.reject(required_keys, &Map.has_key?(args, &1))

    case missing_keys do
      [] ->
        "Invalid arguments: expected fields #{Enum.join(required_keys, ", ")}"

      missing ->
        "Missing required arguments: #{Enum.join(missing, ", ")}"
    end
  end

  def missing_required_message(_args, required_keys) do
    "Invalid arguments: expected object with required fields #{Enum.join(required_keys, ", ")}"
  end

  @doc """
  Normalizes the result of a `with` chain into a tool-friendly `{:ok, _} | {:error, String.t()}`.

  Passes through success tuples and converts common error shapes:
  - `{:error, :not_found}` with a project_id becomes a human-readable message
  - `{:error, binary}` passes through
  - `{:error, other}` gets `inspect/1`'d
  """
  @spec format_tool_result(term(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def format_tool_result({:ok, _} = ok, _project_id), do: ok

  def format_tool_result({:error, :not_found}, project_id),
    do: {:error, "Project not found: #{project_id}"}

  def format_tool_result({:error, reason}, _project_id) when is_binary(reason),
    do: {:error, reason}

  def format_tool_result({:error, reason}, _project_id), do: {:error, inspect(reason)}

  @doc """
  Coerces a number to `float`. CapCut's JSON schema expects floats for things like
  `alpha`, `scale`, and `rotation`; integer inputs from the wire need widening.

  ## Examples

      iex> CapcutMcp.Tools.ToolArgs.to_float(1)
      1.0

      iex> CapcutMcp.Tools.ToolArgs.to_float(0.5)
      0.5
  """
  @spec to_float(number()) :: float()
  def to_float(v) when is_integer(v), do: v * 1.0
  def to_float(v) when is_float(v), do: v

  @doc """
  Request-boundary variant of `to_float/1`: rejects non-numeric inputs with a
  human-readable error instead of raising `FunctionClauseError`.

  Used at the outermost tool boundary where JSON payloads can smuggle strings,
  atoms, maps, or `nil` into numeric slots. Callers `with`-propagate the
  `{:error, _}` into the normal tool-error path so the dispatcher can surface
  it as JSON-RPC `-32602` instead of crashing the server.

  ## Examples

      iex> CapcutMcp.Tools.ToolArgs.to_float_safe(1)
      {:ok, 1.0}

      iex> CapcutMcp.Tools.ToolArgs.to_float_safe(0.5)
      {:ok, 0.5}

      iex> CapcutMcp.Tools.ToolArgs.to_float_safe("0.8")
      {:error, "Expected number, got \\"0.8\\""}

      iex> CapcutMcp.Tools.ToolArgs.to_float_safe(nil)
      {:error, "Expected number, got nil"}
  """
  @spec to_float_safe(term()) :: {:ok, float()} | {:error, String.t()}
  def to_float_safe(v) when is_integer(v), do: {:ok, v * 1.0}
  def to_float_safe(v) when is_float(v), do: {:ok, v}
  def to_float_safe(v), do: {:error, "Expected number, got #{inspect(v)}"}
end
