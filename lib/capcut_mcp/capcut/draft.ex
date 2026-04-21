defmodule CapcutMcp.CapCut.Draft do
  @moduledoc """
  A typed representation of CapCut's `draft_content.json` schema.

  CapCut persists drafts as JSON with string keys. This module provides a
  **type-safe construction path** — you build a `%Draft{}` struct and serialize
  it via `to_json/1`, eliminating the class of "typo in string key" bugs at the
  point where the shape matters most (creation).

  Consumers that only read drafts may still work with the raw decoded map
  returned by `CapcutMcp.CapCut.Reader.read_draft/1` — converting to a struct
  is optional and only valuable when the entire field set is known.
  """

  alias __MODULE__

  @type canvas :: %{
          required(String.t()) => term()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          draft_type: String.t(),
          canvas_config: canvas(),
          fps: float(),
          duration: non_neg_integer(),
          tracks: [map()],
          materials: map(),
          keyframes: map(),
          version: integer(),
          new_version: String.t(),
          create_time: integer(),
          update_time: integer()
        }

  @enforce_keys [:id, :name]
  defstruct id: nil,
            name: nil,
            draft_type: "video",
            canvas_config: %{
              "width" => 1920,
              "height" => 1080,
              "ratio" => "original",
              "background" => nil
            },
            fps: 30.0,
            duration: 0,
            tracks: [],
            materials: %{
              "videos" => [],
              "audios" => [],
              "texts" => [],
              "images" => [],
              "effects" => [],
              "transitions" => [],
              "stickers" => [],
              "filters" => []
            },
            keyframes: %{
              "adjusts" => [],
              "audios" => [],
              "effects" => [],
              "filters" => [],
              "stickers" => [],
              "texts" => [],
              "videos" => []
            },
            version: 360_000,
            new_version: "163.0.0",
            create_time: 0,
            update_time: 0

  @doc """
  Builds a fresh empty draft.

  Returns `{:error, msg}` for non-numeric `:fps`, non-integer `:width`/`:height`,
  and non-binary `:name` so the create_project boundary surfaces bad client
  input as a JSON-RPC error instead of crashing the store GenServer.

  ## Examples

      iex> {:ok, d} = CapcutMcp.CapCut.Draft.new(id: "abc", name: "My Clip", width: 1080, height: 1920, fps: 60)
      iex> d.canvas_config["width"]
      1080
      iex> d.fps
      60.0

      iex> CapcutMcp.CapCut.Draft.new(id: "abc", name: "My Clip", fps: "30")
      {:error, "fps: Expected number, got \\"30\\""}
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(opts) do
    id = Keyword.fetch!(opts, :id)
    name = Keyword.fetch!(opts, :name)
    width = Keyword.get(opts, :width, 1920)
    height = Keyword.get(opts, :height, 1080)
    fps_input = Keyword.get(opts, :fps, 30.0)

    with :ok <- check_binary(:name, name),
         :ok <- check_integer(:width, width),
         :ok <- check_integer(:height, height),
         {:ok, fps} <- coerce_fps(fps_input) do
      {:ok,
       %Draft{
         id: id,
         name: name,
         canvas_config: %{
           "width" => width,
           "height" => height,
           "ratio" => "original",
           "background" => nil
         },
         fps: fps
       }}
    end
  end

  defp check_binary(_, value) when is_binary(value), do: :ok

  defp check_binary(field, value),
    do: {:error, "#{field}: expected string, got #{inspect(value)}"}

  defp check_integer(_, value) when is_integer(value), do: :ok

  defp check_integer(field, value),
    do: {:error, "#{field}: expected integer, got #{inspect(value)}"}

  defp coerce_fps(v) when is_integer(v), do: {:ok, v * 1.0}
  defp coerce_fps(v) when is_float(v), do: {:ok, v}
  defp coerce_fps(v), do: {:error, "fps: Expected number, got #{inspect(v)}"}

  @doc "Serializes a `%Draft{}` into the string-keyed map shape CapCut expects on disk."
  @spec to_json(t()) :: map()
  def to_json(%Draft{} = d) do
    %{
      "id" => d.id,
      "name" => d.name,
      "draft_type" => d.draft_type,
      "canvas_config" => d.canvas_config,
      "fps" => d.fps,
      "duration" => d.duration,
      "tracks" => d.tracks,
      "materials" => d.materials,
      "keyframes" => d.keyframes,
      "version" => d.version,
      "new_version" => d.new_version,
      "create_time" => d.create_time,
      "update_time" => d.update_time
    }
  end

  defimpl Jason.Encoder do
    def encode(draft, opts), do: Jason.Encode.map(@for.to_json(draft), opts)
  end
end
