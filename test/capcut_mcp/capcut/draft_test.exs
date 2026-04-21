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
      draft = Draft.new(id: "D-1", name: "Example")

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
      assert draft.new_version == "163.0.0"
    end

    test "coerces integer :fps to float" do
      assert %Draft{fps: 60.0} = Draft.new(id: "x", name: "y", fps: 60)
    end

    test "accepts explicit float :fps" do
      assert %Draft{fps: 23.976} = Draft.new(id: "x", name: "y", fps: 23.976)
    end

    test "honours custom canvas dimensions" do
      draft = Draft.new(id: "x", name: "y", width: 1080, height: 1920)
      assert draft.canvas_config["width"] == 1080
      assert draft.canvas_config["height"] == 1920
    end

    test "raises KeyError when :id is missing" do
      assert_raise KeyError, fn -> Draft.new(name: "nope") end
    end

    test "raises KeyError when :name is missing" do
      assert_raise KeyError, fn -> Draft.new(id: "nope") end
    end
  end

  describe "to_json/1" do
    test "produces string-keyed map with every persisted field" do
      draft = Draft.new(id: "abc", name: "Roundtrip")
      json = Draft.to_json(draft)

      expected_keys =
        ~w(id name draft_type canvas_config fps duration tracks materials
           keyframes version new_version create_time update_time)

      for key <- expected_keys do
        assert Map.has_key?(json, key), "expected key #{inspect(key)} in to_json output"
      end
    end

    test "materials map exposes the eight canonical buckets" do
      draft = Draft.new(id: "abc", name: "Buckets")
      %{"materials" => materials} = Draft.to_json(draft)

      for bucket <- ~w(videos audios texts images effects transitions stickers filters) do
        assert Map.has_key?(materials, bucket)
        assert materials[bucket] == []
      end
    end
  end

  describe "Jason.Encoder" do
    test "encoding a %Draft{} and decoding back yields a map equal to to_json/1" do
      draft = Draft.new(id: "rt-1", name: "Full Roundtrip", width: 1080, height: 1920, fps: 60)

      encoded = Jason.encode!(draft)
      assert is_binary(encoded)

      decoded = Jason.decode!(encoded)
      assert decoded == Draft.to_json(draft)
    end

    test "encoded JSON has string keys only (no atom leakage)" do
      draft = Draft.new(id: "k", name: "Keys")
      decoded = draft |> Jason.encode!() |> Jason.decode!()

      assert Enum.all?(Map.keys(decoded), &is_binary/1)
      assert Enum.all?(Map.keys(decoded["canvas_config"]), &is_binary/1)
      assert Enum.all?(Map.keys(decoded["materials"]), &is_binary/1)
      assert Enum.all?(Map.keys(decoded["keyframes"]), &is_binary/1)
    end
  end
end
