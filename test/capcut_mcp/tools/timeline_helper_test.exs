defmodule CapcutMcp.Tools.TimelineHelperTest do
  use ExUnit.Case, async: true

  alias CapcutMcp.Tools.TimelineHelper

  @video_segment %{
    "id" => "seg-video-1",
    "material_id" => "mat-1",
    "clip" => %{"alpha" => 1.0, "transform" => %{"x" => 0.0, "y" => 0.0}},
    "target_timerange" => %{"start" => 0, "duration" => 5_000_000},
    "volume" => 1.0
  }

  @audio_segment %{
    "id" => "seg-audio-1",
    "material_id" => "mat-2",
    "clip" => nil,
    "target_timerange" => %{"start" => 0, "duration" => 3_000_000},
    "volume" => 1.0
  }

  @draft %{
    "tracks" => [
      %{"id" => "track-1", "type" => "video", "segments" => [@video_segment]},
      %{"id" => "track-2", "type" => "audio", "segments" => [@audio_segment]}
    ],
    "materials" => %{"videos" => [], "audios" => []}
  }

  describe "find_segment/2" do
    test "finds a video segment" do
      assert {:ok, {0, 0, segment}} = TimelineHelper.find_segment(@draft, "seg-video-1")
      assert segment["id"] == "seg-video-1"
    end

    test "finds an audio segment" do
      assert {:ok, {1, 0, segment}} = TimelineHelper.find_segment(@draft, "seg-audio-1")
      assert segment["id"] == "seg-audio-1"
    end

    test "returns error for unknown segment" do
      assert {:error, "Segment not found: unknown"} = TimelineHelper.find_segment(@draft, "unknown")
    end

    test "returns error for empty tracks" do
      draft = %{"tracks" => []}
      assert {:error, _} = TimelineHelper.find_segment(draft, "seg-video-1")
    end

    test "returns error when tracks key is nil" do
      draft = %{"tracks" => nil}
      assert {:error, _} = TimelineHelper.find_segment(draft, "seg-video-1")
    end
  end

  describe "update_segment/3" do
    test "updates a segment in-place" do
      {:ok, updated} =
        TimelineHelper.update_segment(@draft, "seg-video-1", fn seg ->
          Map.put(seg, "volume", 0.5)
        end)

      [video_track | _] = updated["tracks"]
      [seg | _] = video_track["segments"]
      assert seg["volume"] == 0.5
      assert seg["id"] == "seg-video-1"
    end

    test "returns error for unknown segment" do
      assert {:error, _} =
               TimelineHelper.update_segment(@draft, "unknown", fn seg -> seg end)
    end

    test "preserves other tracks" do
      {:ok, updated} =
        TimelineHelper.update_segment(@draft, "seg-video-1", fn seg ->
          Map.put(seg, "volume", 0.0)
        end)

      audio_track = Enum.at(updated["tracks"], 1)
      [audio_seg | _] = audio_track["segments"]
      assert audio_seg["volume"] == 1.0
    end
  end
end
