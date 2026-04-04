defmodule CapcutMcp.Tools.ToolArgs do
  @moduledoc false

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
end
