defmodule CapcutMcp.CapCut.TextAnimations do
  @moduledoc """
  A small curated catalog of CapCut's built-in text intro/outro animations.

  ## Provenance

  Unlike `BlendModes` (which discovers `MixMode.json` from the local CapCut
  install because Windows caches it per-version), these `effect_id`/
  `resource_id` pairs are IDs baked into every CapCut client globally — they
  don't come from a local resource file, so there's nothing to discover on
  disk. Sourced from `GuanYixuan/pyCapCut`
  (https://github.com/GuanYixuan/pyCapCut), an open-source Python library
  that bundles CapCut's full animation catalog as static metadata
  (`pycapcut/metadata/text_intro.py`, `text_outro.py`). Cross-referenced
  against our own `common_mask` / `materials.animations` schema findings
  from the write-path investigation — the structural shape matches.

  Only a handful of animations are curated here (not the full ~200-entry
  catalog): a clean, minimal set suited to an "Apple-style" text treatment —
  fade, slide, blur, typewriter — each with a matched intro/outro pair where
  one exists. Add more by copying the `{effect_id, resource_id, md5,
  duration_us}` tuple straight out of pyCapCut's `text_intro.py` /
  `text_outro.py` for the animation you want; the pairing (same name
  appearing in both files) is what makes an intro/outro pair "matched" —
  CapCut does not enforce this, it's a curation choice for a coherent look.
  """

  @type animation_type :: :in | :out | :loop

  @type entry :: %{
          name: String.t(),
          effect_id: String.t(),
          resource_id: String.t(),
          type: animation_type(),
          default_duration_us: pos_integer()
        }

  # {curated_name, {display_name, effect_id, resource_id, duration_seconds}}
  @intros %{
    "fade_in" => {"渐显", "6724916044072227332", "6724916044072227332", 0.500},
    "typewriter" => {"打字机", "7210980292243231233", "7210980292243231233", 2.000},
    "slide_up" => {"向上滑动", "6763470111253729803", "6763470111253729803", 0.500},
    "slide_left" => {"向左滑动", "7403255792146584081", "7403255792146584081", 0.500},
    "blur_in" => {"模糊", "6923135604519604737", "6923135604519604737", 0.500}
  }

  @outros %{
    "fade_out" => {"渐隐", "6724919382104871427", "6724919382104871427", 1.600},
    "slide_down" => {"向下滑动", "7403256664498901520", "7403256664498901520", 0.500},
    "slide_right" => {"向右滑动", "6724920744431587853", "6724920744431587853", 0.500},
    "blur_out" => {"模糊", "6923134492760609282", "6923134492760609282", 0.500}
  }

  @doc "Returns all curated animation names, grouped by `:in`/`:out`."
  @spec names() :: %{in: [String.t()], out: [String.t()]}
  def names do
    %{in: Map.keys(@intros), out: Map.keys(@outros)}
  end

  @doc """
  Looks up a curated animation by name. Returns `{:ok, entry}` with the
  effect/resource IDs and default duration (in microseconds), or
  `{:error, message}` listing valid names.
  """
  @spec fetch(String.t()) :: {:ok, entry()} | {:error, String.t()}
  def fetch(name) when is_binary(name) do
    case Map.get(@intros, name) do
      nil ->
        case Map.get(@outros, name) do
          nil -> {:error, not_found_message(name)}
          entry -> {:ok, build_entry(name, entry, :out)}
        end

      entry ->
        {:ok, build_entry(name, entry, :in)}
    end
  end

  defp build_entry(name, {display_name, effect_id, resource_id, duration_s}, type) do
    %{
      name: name,
      display_name: display_name,
      effect_id: effect_id,
      resource_id: resource_id,
      type: type,
      default_duration_us: round(duration_s * 1_000_000)
    }
  end

  defp not_found_message(name) do
    all = Map.keys(@intros) ++ Map.keys(@outros)
    "Unknown animation: #{inspect(name)}. Available: #{Enum.join(Enum.sort(all), ", ")}"
  end
end
