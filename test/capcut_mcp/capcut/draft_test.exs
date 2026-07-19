defmodule CapcutMcp.CapCut.DraftTest do
  @moduledoc """
  Pins the JSON shape of `%Draft{}` so schema drift against CapCut's
  `draft_content.json` surfaces here instead of at runtime against a real
  CapCut install. Exercises both the explicit `to_json/1` path and the
  `Jason.Encoder` protocol implementation.
  """

  use ExUnit.Case, async: true

  alias CapcutMcp.CapCut.Draft

  describe "new/1" do
    test "applies defaults when only :id and :name are given" do
      assert {:ok, draft} = Draft.new(id: "D-1", name: "Example")

      assert draft.id == "D-1"
      assert draft.name == "Example"
      assert draft.draft_type == "video"
      assert draft.canvas_config["width"] == 1920
      assert draft.canvas_config["height"] == 1080
      assert draft.canvas_config["ratio"] == "original"
      assert draft.fps == 30.0
      assert draft.duration == 0
      assert draft.tracks == []
      assert draft.version == 360_000
      # 175.0.0 confirmed live: created a project through CapCut's own macOS
      # UI (app_version 8.9.1) and read its new_version field back.
      assert draft.new_version == "175.0.0"
    end

    test "coerces integer :fps to float" do
      assert {:ok, %Draft{fps: 60.0}} = Draft.new(id: "x", name: "y", fps: 60)
    end

    test "accepts explicit float :fps" do
      assert {:ok, %Draft{fps: 23.976}} = Draft.new(id: "x", name: "y", fps: 23.976)
    end

    test "honours custom canvas dimensions" do
      assert {:ok, draft} = Draft.new(id: "x", name: "y", width: 1080, height: 1920)
      assert draft.canvas_config["width"] == 1080
      assert draft.canvas_config["height"] == 1920
    end

    test "raises KeyError when :id is missing" do
      assert_raise KeyError, fn -> Draft.new(name: "nope") end
    end

    test "raises KeyError when :name is missing" do
      assert_raise KeyError, fn -> Draft.new(id: "nope") end
    end

    test "rejects non-numeric :fps with a helpful message" do
      assert {:error, msg} = Draft.new(id: "x", name: "y", fps: "30")
      assert msg =~ "fps"
      assert msg =~ "Expected number"
      assert msg =~ ~s("30")
    end

    test "rejects non-integer :width" do
      assert {:error, msg} = Draft.new(id: "x", name: "y", width: "1080")
      assert msg =~ "width"
      assert msg =~ "expected integer"
    end

    test "rejects non-binary :name" do
      assert {:error, msg} = Draft.new(id: "x", name: :atomic)
      assert msg =~ "name"
      assert msg =~ "expected string"
    end
  end

  describe "to_json/1" do
    test "produces string-keyed map with every persisted field" do
      {:ok, draft} = Draft.new(id: "abc", name: "Roundtrip")
      json = Draft.to_json(draft)

      expected_keys =
        ~w(id name draft_type canvas_config fps duration tracks materials
           keyframes version new_version create_time update_time
           is_drop_frame_timecode color_space config group_container
           keyframe_graph_list platform last_modified_platform mutable_config
           cover retouch_cover extra_info relationships mixed_track_mode_on
           render_index_track_mode_on free_render_index_mode_on
           static_cover_image_path source time_marks path lyrics_effects
           uneven_animation_template_info smart_ads_info
           function_assistant_info)

      for key <- expected_keys do
        assert Map.has_key?(json, key), "expected key #{inspect(key)} in to_json output"
      end
    end

    test "materials map exposes the full 55-bucket shape CapCut requires to open a project" do
      # Confirmed via a pristine (CapCut-UI-created, zero edits) draft_info.json:
      # a materials map with only the original 8 "obvious" buckets is
      # list-visible but silently fails to open. No "filters" bucket here —
      # confirmed absent in the real capture (keyframes has one; materials
      # doesn't).
      {:ok, draft} = Draft.new(id: "abc", name: "Buckets")
      %{"materials" => materials} = Draft.to_json(draft)

      expected_buckets =
        ~w(ai_text_effects ai_translates audio_balances audio_effects audio_fades
           audio_pannings audio_pitch_shifts audio_track_indexes audios beats
           canvases chromas color_curves common_mask digital_human_model_dressing
           digital_humans drafts effects flowers green_screens handwrites hsl
           hsl_curves images log_color_wheels loudnesses manual_beautys
           manual_deformations material_animations material_colors
           multi_language_refs placeholder_infos placeholders plugin_effects
           primary_color_wheels realtime_denoises shapes smart_crops
           smart_relights sound_channel_mappings speeds stickers tail_leaders
           text_templates texts time_marks transitions video_effects
           video_radius video_shadows video_strokes video_trackings videos
           vocal_beautifys vocal_separations)

      assert length(expected_buckets) == 55
      assert Enum.sort(Map.keys(materials)) == Enum.sort(expected_buckets)

      for bucket <- expected_buckets do
        assert materials[bucket] == []
      end
    end

    test "keyframes map exposes all 8 buckets including handwrites" do
      {:ok, draft} = Draft.new(id: "abc", name: "Keyframes")
      %{"keyframes" => keyframes} = Draft.to_json(draft)

      for bucket <- ~w(adjusts audios effects filters handwrites stickers texts videos) do
        assert Map.has_key?(keyframes, bucket)
        assert keyframes[bucket] == []
      end
    end

    test "color_space defaults to -1, not 0" do
      # Confirmed via a pristine CapCut-created project's draft_info.json.
      {:ok, draft} = Draft.new(id: "abc", name: "ColorSpace")
      assert %{"color_space" => -1} = Draft.to_json(draft)
    end
  end

  describe "Jason.Encoder" do
    test "encoding a %Draft{} and decoding back yields a map equal to to_json/1" do
      {:ok, draft} =
        Draft.new(id: "rt-1", name: "Full Roundtrip", width: 1080, height: 1920, fps: 60)

      encoded = Jason.encode!(draft)
      assert is_binary(encoded)

      decoded = Jason.decode!(encoded)
      assert decoded == Draft.to_json(draft)
    end

    test "encoded JSON has string keys only (no atom leakage)" do
      {:ok, draft} = Draft.new(id: "k", name: "Keys")
      decoded = draft |> Jason.encode!() |> Jason.decode!()

      assert Enum.all?(Map.keys(decoded), &is_binary/1)
      assert Enum.all?(Map.keys(decoded["canvas_config"]), &is_binary/1)
      assert Enum.all?(Map.keys(decoded["materials"]), &is_binary/1)
      assert Enum.all?(Map.keys(decoded["keyframes"]), &is_binary/1)
    end
  end
end
