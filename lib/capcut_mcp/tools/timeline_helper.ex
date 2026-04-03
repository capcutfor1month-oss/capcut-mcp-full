defmodule CapcutMcp.Tools.TimelineHelper do
  @moduledoc """
  Shared helper functions for manipulating CapCut timelines.
  Provides UUID generation, segment insertion, material addition, and validation logic.
  """

  @doc "Generates a v4-like UUID using crypto-safe random bytes."
  @spec generate_uuid() :: String.t()
  def generate_uuid do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)
    <<hex::binary-size(32)>> = Base.encode16(<<a::48, 4::4, b::12, 2::2, c::62>>, case: :upper)

    <<g1::binary-size(8), g2::binary-size(4), g3::binary-size(4), g4::binary-size(4),
      g5::binary-size(12)>> = hex

    "#{g1}-#{g2}-#{g3}-#{g4}-#{g5}"
  end

  @doc "Inserts a segment into the appropriate track."
  def insert_segment(tracks, segment, type, nil) do
    case Enum.find_index(tracks, fn t -> t["type"] == type end) do
      nil ->
        new_track = %{
          "id" => generate_uuid(),
          "type" => type,
          "segments" => [segment],
          "attribute" => 0,
          "flag" => 0
        }

        {tracks ++ [new_track], length(tracks)}

      idx ->
        updated = Map.update!(Enum.at(tracks, idx), "segments", &(&1 ++ [segment]))
        {List.replace_at(tracks, idx, updated), idx}
    end
  end

  def insert_segment(tracks, segment, _type, idx)
      when is_integer(idx) and idx >= 0 and idx < length(tracks) do
    updated = Map.update!(Enum.at(tracks, idx), "segments", &(&1 ++ [segment]))
    {List.replace_at(tracks, idx, updated), idx}
  end

  def insert_segment(tracks, segment, type, _idx), do: insert_segment(tracks, segment, type, nil)

  @doc "Adds a material to the draft's materials map."
  def add_material(draft, category, material) do
    materials = draft["materials"] || %{}
    updated_materials = Map.update(materials, category, [material], &(&1 ++ [material]))
    Map.put(draft, "materials", updated_materials)
  end

  @doc "Validates that the track index is within bounds, or nil."
  def validate_track_index(_tracks, nil), do: {:ok, nil}

  def validate_track_index(tracks, idx)
      when is_integer(idx) and idx >= 0 and idx < length(tracks) do
    {:ok, idx}
  end

  def validate_track_index(_tracks, idx), do: {:error, "Invalid track index: #{inspect(idx)}"}

  @doc "Validates start_ms and duration_ms."
  def validate_timing(start_ms, duration_ms)
      when is_integer(start_ms) and start_ms >= 0 and is_integer(duration_ms) and duration_ms > 0 do
    {:ok, {start_ms, duration_ms}}
  end

  def validate_timing(start_ms, _duration_ms) when not is_integer(start_ms),
    do: {:error, "Invalid start_ms: #{inspect(start_ms)}"}

  def validate_timing(start_ms, _duration_ms) when is_integer(start_ms) and start_ms < 0,
    do: {:error, "Invalid start_ms: #{inspect(start_ms)}"}

  def validate_timing(_start_ms, duration_ms) when not is_integer(duration_ms),
    do: {:error, "Invalid duration_ms: #{inspect(duration_ms)}"}

  def validate_timing(_start_ms, duration_ms),
    do: {:error, "Invalid duration_ms: #{inspect(duration_ms)}"}
end
