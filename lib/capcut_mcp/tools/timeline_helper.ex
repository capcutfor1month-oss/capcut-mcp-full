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
  @spec insert_segment([map()], map(), String.t(), non_neg_integer() | nil) ::
          {[map()], non_neg_integer()}
  def insert_segment(tracks, segment, type, nil) do
    case Enum.find_index(tracks, &(&1["type"] == type)) do
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
        {append_segment_at(tracks, idx, segment), idx}
    end
  end

  def insert_segment(tracks, segment, _type, idx)
      when is_integer(idx) and idx >= 0 and idx < length(tracks) do
    {append_segment_at(tracks, idx, segment), idx}
  end

  def insert_segment(tracks, segment, type, _idx), do: insert_segment(tracks, segment, type, nil)

  defp append_segment_at(tracks, idx, segment) do
    List.update_at(tracks, idx, fn track ->
      Map.update!(track, "segments", &(&1 ++ [segment]))
    end)
  end

  @doc "Adds a material to the draft's materials map."
  @spec add_material(map(), String.t(), map()) :: map()
  def add_material(draft, category, material) do
    materials = draft["materials"] || %{}
    updated_materials = Map.update(materials, category, [material], &(&1 ++ [material]))
    Map.put(draft, "materials", updated_materials)
  end

  @doc "Validates that the track index is within bounds, or nil."
  @spec validate_track_index([map()], non_neg_integer() | nil) ::
          {:ok, non_neg_integer() | nil} | {:error, String.t()}
  def validate_track_index(_tracks, nil), do: {:ok, nil}

  def validate_track_index(tracks, idx)
      when is_integer(idx) and idx >= 0 and idx < length(tracks) do
    {:ok, idx}
  end

  def validate_track_index(_tracks, idx), do: {:error, "Invalid track index: #{inspect(idx)}"}

  @doc "Finds a segment by ID across all tracks. Returns {:ok, {track_idx, seg_idx, segment}} or error."
  @spec find_segment(map(), String.t()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), map()}} | {:error, String.t()}
  def find_segment(draft, segment_id) do
    tracks = draft["tracks"] || []

    result =
      tracks
      |> Enum.with_index()
      |> Enum.find_value(fn {track, t_idx} ->
        segments = track["segments"] || []

        case Enum.find_index(segments, &(&1["id"] == segment_id)) do
          nil -> nil
          s_idx -> {t_idx, s_idx, Enum.at(segments, s_idx)}
        end
      end)

    case result do
      nil -> {:error, "Segment not found: #{segment_id}"}
      tuple -> {:ok, tuple}
    end
  end

  @doc "Updates a segment in-place by ID. Applies update_fn to the found segment and returns the updated draft."
  @spec update_segment(map(), String.t(), (map() -> map())) :: {:ok, map()} | {:error, String.t()}
  def update_segment(draft, segment_id, update_fn) do
    with {:ok, {t_idx, s_idx, segment}} <- find_segment(draft, segment_id) do
      updated_segment = update_fn.(segment)
      tracks = draft["tracks"]
      track = Enum.at(tracks, t_idx)
      updated_segments = List.replace_at(track["segments"], s_idx, updated_segment)
      updated_track = Map.put(track, "segments", updated_segments)
      updated_tracks = List.replace_at(tracks, t_idx, updated_track)
      {:ok, Map.put(draft, "tracks", updated_tracks)}
    end
  end

  @doc "Ensures a segment timerange field exists as a map merged with defaults."
  @spec ensure_timerange(map(), String.t(), map()) :: map()
  def ensure_timerange(segment, key, defaults \\ %{}) when is_binary(key) and is_map(defaults) do
    timerange =
      case Map.get(segment, key) do
        existing when is_map(existing) -> Map.merge(defaults, existing)
        _ -> defaults
      end

    Map.put(segment, key, timerange)
  end

  @doc "Validates that `start_ms` is a non-negative integer and `duration_ms` a positive integer."
  @spec validate_timing(term(), term()) ::
          {:ok, {non_neg_integer(), pos_integer()}} | {:error, String.t()}
  def validate_timing(start_ms, duration_ms)
      when is_integer(start_ms) and start_ms >= 0 and is_integer(duration_ms) and duration_ms > 0 do
    {:ok, {start_ms, duration_ms}}
  end

  def validate_timing(start_ms, _duration_ms) when not (is_integer(start_ms) and start_ms >= 0),
    do: {:error, "Invalid start_ms: #{inspect(start_ms)}"}

  def validate_timing(_start_ms, duration_ms),
    do: {:error, "Invalid duration_ms: #{inspect(duration_ms)}"}
end
