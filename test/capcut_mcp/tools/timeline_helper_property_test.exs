defmodule CapcutMcp.Tools.TimelineHelperPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias CapcutMcp.Tools.TimelineHelper

  @uuid_v4_regex ~r/^[0-9A-F]{8}-[0-9A-F]{4}-4[0-9A-F]{3}-[89AB][0-9A-F]{3}-[0-9A-F]{12}$/

  describe "generate_uuid/0" do
    property "always returns a syntactically valid v4 UUID" do
      check all _ <- StreamData.constant(:ok), max_runs: 1000 do
        uuid = TimelineHelper.generate_uuid()
        assert uuid =~ @uuid_v4_regex
      end
    end
  end

  describe "update_segment/3" do
    property "updating with identity yields an equal draft for every existing segment id" do
      check all draft <- draft_gen(), max_runs: 100 do
        for id <- all_segment_ids(draft) do
          assert {:ok, updated} =
                   TimelineHelper.update_segment(draft, id, &Function.identity/1)

          assert updated == draft
        end
      end
    end

    property "find_segment after update_segment returns the updated segment" do
      check all draft <- draft_gen(),
                volume <- StreamData.float(min: 0.0, max: 1.0),
                max_runs: 100 do
        ids = all_segment_ids(draft)

        # Skip drafts without segments — nothing to update.
        if ids != [] do
          id = Enum.random(ids)

          assert {:ok, updated_draft} =
                   TimelineHelper.update_segment(draft, id, fn seg ->
                     Map.put(seg, "volume", volume)
                   end)

          assert {:ok, {_t_idx, _s_idx, seg}} =
                   TimelineHelper.find_segment(updated_draft, id)

          assert seg["volume"] == volume
          assert seg["id"] == id
        end
      end
    end
  end

  describe "ensure_timerange/3" do
    property "is idempotent — applying twice equals applying once" do
      check all segment <- segment_gen(),
                key <- StreamData.member_of(["target_timerange", "source_timerange", "custom"]),
                defaults <- timerange_defaults_gen(),
                max_runs: 100 do
        once = TimelineHelper.ensure_timerange(segment, key, defaults)
        twice = TimelineHelper.ensure_timerange(once, key, defaults)
        assert twice == once
      end
    end

    property "always stores a map under the requested key" do
      check all segment <- segment_gen(),
                key <- StreamData.member_of(["target_timerange", "source_timerange", "custom"]),
                defaults <- timerange_defaults_gen(),
                max_runs: 100 do
        result = TimelineHelper.ensure_timerange(segment, key, defaults)
        assert is_map(Map.get(result, key))
      end
    end
  end

  describe "insert_segment/4 with nil track_index" do
    property "raises the total segment count by exactly one and lands the new segment once" do
      check all tracks <- tracks_gen(),
                type <- StreamData.member_of(["video", "audio", "text", "effect"]),
                max_runs: 100 do
        # A fresh UUID is practically guaranteed not to collide with the short
        # generated ids above, so we can count occurrences safely.
        new_seg = build_segment("new-" <> TimelineHelper.generate_uuid())

        {new_tracks, idx} = TimelineHelper.insert_segment(tracks, new_seg, type, nil)

        assert total_segments(new_tracks) == total_segments(tracks) + 1
        assert count_id_occurrences(new_tracks, new_seg["id"]) == 1
        assert idx >= 0 and idx < length(new_tracks)
        assert Enum.at(new_tracks, idx)["type"] == type
      end
    end

    property "reuses an existing track of the given type, else appends a new one" do
      check all tracks <- tracks_gen(),
                type <- StreamData.member_of(["video", "audio", "text", "effect"]),
                max_runs: 100 do
        new_seg = build_segment("new-" <> TimelineHelper.generate_uuid())
        {new_tracks, _idx} = TimelineHelper.insert_segment(tracks, new_seg, type, nil)

        if Enum.any?(tracks, &(&1["type"] == type)) do
          assert length(new_tracks) == length(tracks)
        else
          assert length(new_tracks) == length(tracks) + 1
          assert List.last(new_tracks)["type"] == type
        end
      end
    end
  end

  describe "insert_segment/4 with an in-range integer track_index" do
    property "keeps track count stable and appends to exactly that track" do
      check all tracks <- tracks_gen(min_tracks: 1),
                type <- StreamData.member_of(["video", "audio"]),
                max_runs: 100 do
        idx = :rand.uniform(length(tracks)) - 1
        new_seg = build_segment("new-" <> TimelineHelper.generate_uuid())

        {new_tracks, returned_idx} = TimelineHelper.insert_segment(tracks, new_seg, type, idx)

        assert returned_idx == idx
        assert length(new_tracks) == length(tracks)
        assert total_segments(new_tracks) == total_segments(tracks) + 1

        target_track = Enum.at(new_tracks, idx)
        assert List.last(target_track["segments"])["id"] == new_seg["id"]
      end
    end
  end

  describe "validate_timing/2" do
    property "accepts non-negative integer starts paired with positive integer durations" do
      check all start_ms <- StreamData.integer(0..100_000_000),
                duration_ms <- StreamData.positive_integer(),
                max_runs: 100 do
        assert {:ok, {^start_ms, ^duration_ms}} =
                 TimelineHelper.validate_timing(start_ms, duration_ms)
      end
    end

    property "rejects negative or non-integer start values" do
      check all bad_start <-
                  StreamData.one_of([
                    StreamData.integer(-1_000_000..-1),
                    StreamData.float(),
                    StreamData.string(:alphanumeric)
                  ]),
                duration_ms <- StreamData.positive_integer(),
                max_runs: 50 do
        assert {:error, msg} = TimelineHelper.validate_timing(bad_start, duration_ms)
        assert msg =~ "Invalid"
      end
    end

    property "rejects zero or negative durations" do
      check all start_ms <- StreamData.integer(0..1_000),
                bad_duration <- StreamData.integer(-1_000..0),
                max_runs: 50 do
        assert {:error, msg} = TimelineHelper.validate_timing(start_ms, bad_duration)
        assert msg =~ "Invalid duration_ms"
      end
    end
  end

  # --- Generators ---------------------------------------------------------

  defp segment_gen do
    gen all id <- StreamData.string(:alphanumeric, min_length: 1, max_length: 8),
            material_id <- StreamData.string(:alphanumeric, min_length: 1, max_length: 8),
            start <- StreamData.integer(0..10_000_000),
            duration <- StreamData.integer(1..10_000_000),
            volume <- StreamData.float(min: 0.0, max: 1.0) do
      %{
        "id" => id,
        "material_id" => material_id,
        "target_timerange" => %{"start" => start, "duration" => duration},
        "volume" => volume
      }
    end
  end

  defp timerange_defaults_gen do
    gen all start <- StreamData.integer(0..1_000_000),
            duration <- StreamData.integer(1..1_000_000) do
      %{"start" => start, "duration" => duration}
    end
  end

  # Generates tracks with unique segment ids across the whole draft, so that
  # find_segment/update_segment have unambiguous targets.
  defp tracks_gen(opts \\ []) do
    min_tracks = Keyword.get(opts, :min_tracks, 0)

    gen all n_tracks <- StreamData.integer(min_tracks..4),
            sizes <- StreamData.list_of(StreamData.integer(0..3), length: n_tracks) do
      {tracks, _next_id} =
        sizes
        |> Enum.with_index()
        |> Enum.map_reduce(1, fn {size, t_idx}, counter ->
          {segments, counter2} =
            Enum.map_reduce(1..size//1, counter, fn _, c ->
              {build_segment("seg-#{c}"), c + 1}
            end)

          type = if rem(t_idx, 2) == 0, do: "video", else: "audio"

          {%{
             "id" => "track-#{t_idx}",
             "type" => type,
             "segments" => segments
           }, counter2}
        end)

      tracks
    end
  end

  defp draft_gen do
    gen all tracks <- tracks_gen() do
      %{"tracks" => tracks, "materials" => %{}}
    end
  end

  # --- Helpers ------------------------------------------------------------

  defp build_segment(id) do
    %{
      "id" => id,
      "material_id" => "mat-#{id}",
      "target_timerange" => %{"start" => 0, "duration" => 1_000_000},
      "volume" => 1.0
    }
  end

  defp all_segment_ids(%{"tracks" => tracks}) do
    for track <- tracks,
        seg <- track["segments"] || [],
        do: seg["id"]
  end

  defp total_segments(tracks) do
    Enum.reduce(tracks, 0, fn t, acc -> acc + length(t["segments"] || []) end)
  end

  defp count_id_occurrences(tracks, id) do
    Enum.reduce(tracks, 0, fn t, acc ->
      acc + Enum.count(t["segments"] || [], &(&1["id"] == id))
    end)
  end
end
