defmodule CapcutMcp.Tools.AddTextAnimation do
  @moduledoc """
  MCP tool: apply an intro or outro text animation (fade, slide, blur,
  typewriter) to a text segment.

  ## Schema

  Ported from `GuanYixuan/pyCapCut`'s `animation.py` (see
  `CapcutMcp.CapCut.TextAnimations` for provenance of the effect/resource
  IDs). An animation is its own material — a `SegmentAnimations`-shaped
  object with `"type" => "sticker_animation"` (yes, text animations use the
  sticker_animation material type in CapCut's schema — confirmed in
  pyCapCut's source, not a typo) and an `"animations"` array holding one
  entry per attached animation (in/out/loop). It's appended to
  `materials.animations`, and its id is added to the segment's
  `extra_material_refs` — the same "material + back-reference" pattern
  CapCut uses everywhere (see `Draft`'s moduledoc for the analogous
  `timeline_id` vs `draft_id` split this whole investigation started from).

  Only one animation of a given direction (`in`/`out`) may be attached to a
  segment at a time — matches pyCapCut's own constraint
  (`SegmentAnimations.add_animation`), which mirrors what CapCut's own UI
  allows.
  """
  @behaviour CapcutMcp.Tool

  alias CapcutMcp.CapCut.TextAnimations
  alias CapcutMcp.Tools.{SegmentMutation, TimelineHelper, ToolArgs}

  @impl true
  def definition do
    %{
      "name" => "add_text_animation",
      "description" =>
        "Applies an intro or outro animation (fade, slide, blur, typewriter) to a text segment. " <>
          "See list_text_animations for available names.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project_id" => %{"type" => "string", "description" => "The draft_id of the project"},
          "clip_id" => %{
            "type" => "string",
            "description" => "The text segment ID (from get_timeline)"
          },
          "animation" => %{
            "type" => "string",
            "description" =>
              "Animation name, e.g. \"fade_in\", \"fade_out\", \"slide_up\", \"typewriter\". See list_text_animations."
          },
          "duration_ms" => %{
            "type" => "integer",
            "description" => "Override the animation's default duration, in milliseconds"
          }
        },
        "required" => ["project_id", "clip_id", "animation"]
      }
    }
  end

  @impl true
  def execute(%{"project_id" => id, "clip_id" => clip_id, "animation" => animation} = args) do
    duration_ms = Map.get(args, "duration_ms")

    with {:ok, entry} <- TextAnimations.fetch(animation),
         {:ok, duration_us} <- resolve_duration_us(entry, duration_ms) do
      SegmentMutation.run_draft(
        id,
        &apply_animation(&1, clip_id, entry, duration_us),
        success: "#{entry.display_name} (#{entry.type}) animation added to segment #{clip_id}."
      )
    end
  end

  def execute(args),
    do: {:error, ToolArgs.missing_required_message(args, ["project_id", "clip_id", "animation"])}

  defp resolve_duration_us(_entry, nil), do: {:ok, nil}

  defp resolve_duration_us(_entry, ms) when is_integer(ms) and ms > 0, do: {:ok, ms * 1000}

  defp resolve_duration_us(_entry, ms),
    do: {:error, "duration_ms must be a positive integer, got #{inspect(ms)}"}

  defp apply_animation(draft, clip_id, entry, override_duration_us) do
    with {:ok, {t_idx, s_idx, segment}} <- TimelineHelper.find_segment(draft, clip_id),
         :ok <- ensure_text_segment(segment),
         :ok <- ensure_no_conflicting_animation(draft, segment, entry.type) do
      duration_us = override_duration_us || entry.default_duration_us
      start_us = animation_start_us(segment, entry.type, duration_us)

      animation_material_id = TimelineHelper.generate_uuid()
      animation_entry_id = TimelineHelper.generate_uuid()

      animation_material = %{
        "id" => animation_material_id,
        "type" => "sticker_animation",
        "multi_language_current" => "none",
        "animations" => [
          %{
            "anim_adjust_params" => nil,
            "platform" => "all",
            "panel" => "",
            "material_type" => "sticker",
            "name" => entry.display_name,
            "id" => animation_entry_id,
            "type" => Atom.to_string(entry.type),
            "resource_id" => entry.resource_id,
            "start" => start_us,
            "duration" => duration_us
          }
        ]
      }

      updated_segment =
        Map.update(segment, "extra_material_refs", [animation_material_id], fn refs ->
          refs ++ [animation_material_id]
        end)

      updated_draft =
        draft
        |> TimelineHelper.add_material("animations", animation_material)
        |> put_segment(t_idx, s_idx, updated_segment)

      {:ok, updated_draft}
    end
  end

  defp ensure_text_segment(%{"material_id" => _}), do: :ok

  defp animation_start_us(_segment, :in, _duration_us), do: 0

  defp animation_start_us(segment, :out, duration_us) do
    segment_duration = get_in(segment, ["target_timerange", "duration"]) || duration_us
    max(segment_duration - duration_us, 0)
  end

  # Mirrors pyCapCut's own constraint: at most one "in" and one "out"
  # animation per segment (CapCut's UI enforces the same). Looks up each
  # already-attached animation material by extra_material_refs rather than
  # trusting a segment-local flag, since the animation's `type` only lives
  # on the material.
  defp ensure_no_conflicting_animation(draft, segment, type) do
    refs = segment["extra_material_refs"] || []
    animations = get_in(draft, ["materials", "animations"]) || []

    conflict? =
      animations
      |> Enum.filter(&(&1["id"] in refs))
      |> Enum.any?(fn material ->
        Enum.any?(material["animations"] || [], &(&1["type"] == Atom.to_string(type)))
      end)

    if conflict? do
      {:error,
       "Segment #{segment["id"]} already has an #{type} animation attached; remove it first."}
    else
      :ok
    end
  end

  defp put_segment(draft, t_idx, s_idx, segment) do
    update_in(draft, ["tracks", Access.at(t_idx), "segments", Access.at(s_idx)], fn _ ->
      segment
    end)
  end
end
